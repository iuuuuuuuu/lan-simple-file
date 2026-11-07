// SPDX-License-Identifier: GPL-3.0-only
#include "drop_test_data.h"

#include <filesystem>
#include <fstream>

int WINAPI wWinMain(HINSTANCE, HINSTANCE, wchar_t*, int) {
  int count = 0;
  auto arguments = CommandLineToArgvW(GetCommandLineW(), &count);
  if (!arguments || count != 3) return 1;
  const auto window = reinterpret_cast<HWND>(_wcstoui64(arguments[1], nullptr, 10));
  const std::filesystem::path output(arguments[2]);
  const auto ordinary_test = std::filesystem::path(arguments[0]).parent_path() /
                             L"native_file_drop_test.exe";
  LocalFree(arguments);
  HANDLE token = nullptr;
  OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token);
  TOKEN_ELEVATION elevation{};
  DWORD size = 0;
  const bool token_read = GetTokenInformation(
      token, TokenElevation, &elevation, sizeof(elevation), &size);
  CloseHandle(token);
  if (!token_read) return 1;
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  bool normal_test = false;
  if (CreateProcessW(ordinary_test.c_str(), nullptr, nullptr, nullptr, FALSE,
                     CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) {
    if (WaitForSingleObject(process.hProcess, 5000) == WAIT_OBJECT_0) {
      DWORD exit_code = 1;
      normal_test = GetExitCodeProcess(process.hProcess, &exit_code) &&
                    exit_code == 0;
    } else {
      TerminateProcess(process.hProcess, 1);
      WaitForSingleObject(process.hProcess, 3000);
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
  }
  auto drop = MakeTestDrop();
  // Shell's legacy drop protocol first copies the HGLOBAL into the receiver.
  // Sending our process-local handle directly does not transfer file data.
  constexpr UINT kCopyGlobalData = 0x0049;
  const auto data = GlobalLock(drop);
  DWORD_PTR remote_drop = 0;
  SetLastError(0);
  const auto copied = SendMessageTimeoutW(
      window, kCopyGlobalData, GlobalSize(drop),
      reinterpret_cast<LPARAM>(data), SMTO_ABORTIFHUNG, 3000, &remote_drop);
  const auto copy_error = GetLastError();
  GlobalUnlock(drop);
  DWORD_PTR result = 0;
  SetLastError(0);
  const auto sent = copied && remote_drop && SendMessageTimeoutW(
      window, WM_DROPFILES, remote_drop, 0, SMTO_ABORTIFHUNG, 3000, &result);
  const auto error = GetLastError();
  // The cross-process transfer owns cleanup after delivery.
  if (!copied) DragFinish(drop);
  std::ofstream(output) << "elevated=" << elevation.TokenIsElevated
                       << "\nnormal_test=" << normal_test
                       << "\ncopied=" << (copied != 0)
                       << "\ncopy_error=" << copy_error
                       << "\nremote_drop=" << remote_drop
                       << "\nsent=" << (sent != 0) << "\nerror=" << error << '\n';
  return normal_test && sent && elevation.TokenIsElevated == 0 ? 0 : 1;
}
