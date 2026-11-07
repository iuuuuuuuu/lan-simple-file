// SPDX-License-Identifier: GPL-3.0-only
#include <windows.h>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace fs = std::filesystem;
bool saw_visible = false;

bool IsRunner(HWND window) {
  wchar_t name[128]{};
  GetClassNameW(window, name, 128);
  return std::wstring(name) == L"FLUTTER_RUNNER_WIN32_WINDOW";
}

void CALLBACK VisibilityEvent(HWINEVENTHOOK, DWORD, HWND window, LONG object,
                              LONG, DWORD, DWORD) {
  if (object == OBJID_WINDOW && IsRunner(window)) saw_visible = true;
}

int wmain(int argc, wchar_t** argv) {
  if (argc != 4) return 2;
  const fs::path exe = fs::absolute(argv[1]);
  const fs::path output = fs::absolute(argv[2]);
  const std::wstring mode = argv[3];
  fs::create_directories(output);
  const std::wstring desktop_name =
      L"LanSimpleStartupTest-" + std::to_wstring(GetCurrentProcessId());
  HDESK desktop = CreateDesktopW(desktop_name.c_str(), nullptr, nullptr, 0,
                                 GENERIC_ALL, nullptr);
  if (!desktop || !SetThreadDesktop(desktop)) return 3;
  // No SwitchDesktop call: all test windows stay off the user's input desktop.
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.lpDesktop = const_cast<wchar_t*>(desktop_name.c_str());
  PROCESS_INFORMATION process{};
  auto command = L"\"" + exe.wstring() + L"\" \"" + output.wstring() +
                 L"\" " + mode;
  if (!CreateProcessW(exe.c_str(), command.data(), nullptr, nullptr, FALSE,
                      CREATE_SUSPENDED, nullptr, exe.parent_path().c_str(),
                      &startup, &process)) return 4;
  const auto hook = SetWinEventHook(EVENT_OBJECT_SHOW, EVENT_OBJECT_SHOW,
                                    nullptr, VisibilityEvent, process.dwProcessId,
                                    0, WINEVENT_OUTOFCONTEXT);
  if (!hook) {
    TerminateProcess(process.hProcess, 5);
    return 5;
  }
  ResumeThread(process.hThread);
  const auto deadline = GetTickCount64() + 30000;
  bool checked = false;
  bool correct_visibility = false;
  while (GetTickCount64() < deadline &&
         WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT) {
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    if (!checked && fs::exists(output / L"ready")) {
      correct_visibility = saw_visible == (mode == L"normal" || mode == L"show");
      checked = true;
      std::ofstream(output / L"continue") << "continue";
    }
    Sleep(5);
  }
  DWORD code = 1;
  if (WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT) {
    TerminateProcess(process.hProcess, 6);
    WaitForSingleObject(process.hProcess, 3000);
  }
  GetExitCodeProcess(process.hProcess, &code);
  UnhookWinEvent(hook);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  const bool passed = code == 0 && checked && correct_visibility &&
                      fs::exists(output / L"passed") &&
                      !fs::exists(output / L"failed");
  std::cout << "exit=" << code << " checked=" << checked
            << " initial_visibility_correct=" << correct_visibility << '\n';
  if (fs::exists(output / L"failed")) {
    std::ifstream error(output / L"failed");
    std::cout << error.rdbuf();
  }
  // The process exit releases the private desktop, including any helper HWNDs.
  return passed ? 0 : 1;
}
