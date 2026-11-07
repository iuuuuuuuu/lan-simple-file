// SPDX-License-Identifier: GPL-3.0-only
#include "native_file_drop.h"

#include <ole2.h>
#include <utility>

namespace {
bool IsElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
  TOKEN_ELEVATION elevation{};
  DWORD size = 0;
  const bool elevated =
      GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation),
                          &size) &&
      elevation.TokenIsElevated != 0;
  CloseHandle(token);
  return elevated;
}

std::string ToUtf8(const std::wstring& value) {
  const auto length = static_cast<int>(value.size());
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                      value.data(), length, nullptr, 0,
                                      nullptr, nullptr);
  if (size == 0) return {};
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), length,
                      result.data(), size, nullptr, nullptr);
  return result;
}
}  // namespace

bool EnableElevatedFileDrop(HWND window, HWND flutter_view) {
  if (!IsElevated()) return false;
  // OLE cannot cross integrity levels. Permit only the legacy file-drop
  // message and its HGLOBAL transfer on this window, not arbitrary IPC.
  constexpr UINT kCopyGlobalData = 0x0049;
  if (!ChangeWindowMessageFilterEx(window, WM_DROPFILES, MSGFLT_ALLOW, nullptr) ||
      !ChangeWindowMessageFilterEx(window, kCopyGlobalData, MSGFLT_ALLOW,
                                   nullptr)) {
    return false;
  }
  const HRESULT result = RevokeDragDrop(flutter_view);
  if (FAILED(result) && result != DRAGDROP_E_NOTREGISTERED) return false;
  DragAcceptFiles(window, TRUE);
  return true;
}

NativeFileDrop ReadNativeFileDrop(HDROP drop, HWND window, HWND flutter_view) {
  NativeFileDrop result;
  DragQueryPoint(drop, &result.position);
  ClientToScreen(window, &result.position);
  ScreenToClient(flutter_view, &result.position);
  const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT index = 0; index < count; ++index) {
    const UINT length = DragQueryFileW(drop, index, nullptr, 0);
    if (length == 0) continue;
    std::wstring path(length + 1, L'\0');
    if (DragQueryFileW(drop, index, path.data(), length + 1) != length) continue;
    path.resize(length);
    auto utf8 = ToUtf8(path);
    if (!utf8.empty()) result.paths.push_back(std::move(utf8));
  }
  DragFinish(drop);
  return result;
}
