// SPDX-License-Identifier: GPL-3.0-only
#include "native_file_drop.h"
#include "drop_test_data.h"

#include <ole2.h>
#include <filesystem>
#include <fstream>
#include <iostream>

namespace {
struct State {
  HWND view = nullptr;
  bool received = false;
  NativeFileDrop drop;
};

LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  auto state = reinterpret_cast<State*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    auto create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  } else if (message == WM_DROPFILES && state) {
    state->drop = ReadNativeFileDrop(reinterpret_cast<HDROP>(wparam), window,
                                    state->view);
    state->received = true;
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

bool Matches(const NativeFileDrop& drop) {
  return drop.paths.size() == 2 &&
         drop.paths[0] == u8"C:\\drop\\\u4e2d\u6587.txt" &&
         drop.paths[1] == "C:\\drop\\" + std::string(400, 'a') + ".txt" &&
         drop.position.x == 20 && drop.position.y == 20;
}

class FakeTarget : public IDropTarget {
 public:
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override {
    if (iid != IID_IUnknown && iid != IID_IDropTarget) return E_NOINTERFACE;
    *object = this;
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override { return --references_; }
  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject*, DWORD, POINTL, DWORD*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE DragOver(DWORD, POINTL, DWORD*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE DragLeave() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE Drop(IDataObject*, DWORD, POINTL, DWORD*) override { return S_OK; }
 private:
  ULONG references_ = 1;
};
}  // namespace

int wmain(int argc, wchar_t** argv) {
  HANDLE token = nullptr;
  TOKEN_ELEVATION elevation{};
  DWORD token_size = 0;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return 1;
  const bool token_read = GetTokenInformation(
      token, TokenElevation, &elevation, sizeof(elevation), &token_size);
  CloseHandle(token);
  if (!token_read) return 1;
  OleInitialize(nullptr);
  WNDCLASSW type{};
  type.lpfnWndProc = WindowProc;
  type.hInstance = GetModuleHandleW(nullptr);
  type.lpszClassName = L"LsfHiddenDropTest";
  RegisterClassW(&type);
  State state;
  HWND window = CreateWindowW(type.lpszClassName, L"", WS_OVERLAPPEDWINDOW,
                              50, 30, 640, 480, nullptr, nullptr,
                              type.hInstance, &state);
  state.view = CreateWindowW(L"STATIC", L"", WS_CHILD, 10, 20, 500, 300,
                             window, nullptr, type.hInstance, nullptr);
  FakeTarget target;
  bool success = window && state.view &&
                 RegisterDragDrop(state.view, &target) == S_OK;
  const bool enabled = EnableElevatedFileDrop(window, state.view);
  success = success && enabled == (elevation.TokenIsElevated != 0);
  const HRESULT registration = RegisterDragDrop(state.view, &target);
  success = success &&
            registration == (enabled ? S_OK : DRAGDROP_E_ALREADYREGISTERED);
  if (enabled) RevokeDragDrop(state.view);
  auto drop = MakeTestDrop();
  success = success && drop &&
            Matches(ReadNativeFileDrop(drop, window, state.view));
  if (argc == 3 && success && enabled) {
    std::ofstream(std::filesystem::path(argv[1]))
        << reinterpret_cast<uintptr_t>(window) << '\n';
    const auto deadline = GetTickCount64() + 15000;
    while (!state.received && GetTickCount64() < deadline) {
      MSG message;
      while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
      }
      Sleep(10);
    }
    success = state.received && Matches(state.drop);
    std::ofstream report{std::filesystem::path(argv[2])};
    report << (success ? "passed" : "failed") << '\n'
           << "received=" << state.received << '\n'
           << "paths=" << state.drop.paths.size() << '\n'
           << "position=" << state.drop.position.x << ','
           << state.drop.position.y << '\n';
    for (const auto& path : state.drop.paths) report << path << '\n';
  } else if (argc != 1) {
    success = false;
  }
  RevokeDragDrop(state.view);
  DestroyWindow(window);
  OleUninitialize();
  std::cout << (success ? "Native drop tests passed" : "Native drop tests failed")
            << "; elevated compatibility=" << enabled << std::endl;
  return success ? 0 : 1;
}
