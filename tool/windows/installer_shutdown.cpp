// SPDX-License-Identifier: GPL-3.0-only
#include <windows.h>
#include <restartmanager.h>
#include <shellapi.h>
#include <tlhelp32.h>

#include <string>
#include <vector>

namespace {
struct ShutdownStats {
  unsigned matched = 0;
  unsigned graceful = 0;
  unsigned forced = 0;
  unsigned acknowledged = 0;
  bool restart_manager = false;
};
struct ExitRequest {
  DWORD pid;
  UINT message;
  bool accepted = false;
};

BOOL CALLBACK RequestExit(HWND window, LPARAM data) {
  auto& request = *reinterpret_cast<ExitRequest*>(data);
  DWORD pid = 0;
  GetWindowThreadProcessId(window, &pid);
  if (pid != request.pid) return TRUE;
  wchar_t name[128]{};
  GetClassNameW(window, name, 128);
  if (std::wstring(name) != L"FLUTTER_RUNNER_WIN32_WINDOW") return TRUE;
  DWORD_PTR reply = 0;
  if (SendMessageTimeoutW(window, request.message, 0, 0, SMTO_ABORTIFHUNG,
                          1000, &reply) && reply == 1) request.accepted = true;
  return TRUE;
}

class Handle {
 public:
  explicit Handle(HANDLE value) : value_(value) {}
  ~Handle() { if (value_ && value_ != INVALID_HANDLE_VALUE) CloseHandle(value_); }
  Handle(const Handle&) = delete;
  Handle& operator=(const Handle&) = delete;
  operator HANDLE() const { return value_; }
 private:
  HANDLE value_;
};

std::wstring FinalPath(const wchar_t* path) {
  Handle file(CreateFileW(path, FILE_READ_ATTRIBUTES,
                         FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                         nullptr, OPEN_EXISTING, 0, nullptr));
  if (file == INVALID_HANDLE_VALUE) return {};
  std::wstring result(32768, L'\0');
  const DWORD size = GetFinalPathNameByHandleW(file, result.data(),
                                             static_cast<DWORD>(result.size()), 0);
  if (!size || size >= result.size()) return {};
  result.resize(size);
  return result;
}

DWORD StopInstalledApp(const wchar_t* executable, ShutdownStats& stats) {
  if (GetFileAttributesW(executable) == INVALID_FILE_ATTRIBUTES) {
    const DWORD error = GetLastError();
    return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND
               ? ERROR_SUCCESS : error;
  }
  const auto target = FinalPath(executable);
  if (target.empty()) return ERROR_ACCESS_DENIED;
  const auto name = target.substr(target.find_last_of(L'\\') + 1);
  if (_wcsicmp(name.c_str(), L"lan_simple_file.exe") != 0) return ERROR_BAD_ARGUMENTS;

  DWORD session_id = 0;
  if (!ProcessIdToSessionId(GetCurrentProcessId(), &session_id)) return GetLastError();
  Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
  if (snapshot == INVALID_HANDLE_VALUE) return GetLastError();
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  std::vector<RM_UNIQUE_PROCESS> applications;
  if (!Process32FirstW(snapshot, &entry)) return GetLastError();
  do {
    if (_wcsicmp(entry.szExeFile, name.c_str()) != 0) continue;
    DWORD other_session = 0;
    if (!ProcessIdToSessionId(entry.th32ProcessID, &other_session) ||
        other_session != session_id) continue;
    Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                               entry.th32ProcessID));
    if (!process) {
      if (GetLastError() == ERROR_INVALID_PARAMETER) continue;
      return GetLastError();
    }
    std::wstring path(32768, L'\0');
    DWORD size = static_cast<DWORD>(path.size());
    if (!QueryFullProcessImageNameW(process, 0, path.data(), &size)) continue;
    path.resize(size);
    if (_wcsicmp(FinalPath(path.c_str()).c_str(), target.c_str()) != 0) continue;
    RM_UNIQUE_PROCESS app{entry.th32ProcessID, {}};
    FILETIME end{}, kernel{}, user{};
    if (GetProcessTimes(process, &app.ProcessStartTime, &end, &kernel, &user)) {
      ++stats.matched;
      ExitRequest request{app.dwProcessId,
          RegisterWindowMessageW(L"LanSimpleFile.ShutdownForUpdate.v1")};
      // An installer or client can be on a non-input desktop. Enumerate only
      // this process's threads instead of the caller's desktop window list.
      Handle threads(CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0));
      THREADENTRY32 thread{};
      thread.dwSize = sizeof(thread);
      if (threads != INVALID_HANDLE_VALUE && Thread32First(threads, &thread)) {
        do {
          if (thread.th32OwnerProcessID == app.dwProcessId) {
            EnumThreadWindows(thread.th32ThreadID, RequestExit,
                              reinterpret_cast<LPARAM>(&request));
          }
        } while (Thread32Next(threads, &thread));
      }
      if (request.accepted) {
        ++stats.acknowledged;
        Handle exiting(OpenProcess(SYNCHRONIZE, FALSE, app.dwProcessId));
        if ((exiting && WaitForSingleObject(exiting, 5000) == WAIT_OBJECT_0) ||
            (!exiting && GetLastError() == ERROR_INVALID_PARAMETER)) {
          ++stats.graceful;
          continue;
        }
      }
      applications.push_back(app);
    }
  } while (Process32NextW(snapshot, &entry));
  if (applications.empty()) return ERROR_SUCCESS;

  // Register process identities, not shared DLLs or all processes with this name.
  DWORD session = 0;
  wchar_t key[CCH_RM_SESSION_KEY + 1]{};
  stats.restart_manager = true;
  DWORD result = RmStartSession(&session, 0, key);
  if (result != ERROR_SUCCESS) return result;
  result = RmRegisterResources(session, 0, nullptr,
                              static_cast<UINT>(applications.size()),
                              applications.data(), 0, nullptr);
  if (result == ERROR_SUCCESS) result = RmShutdown(session, RmForceShutdown, nullptr);
  RmEndSession(session);

  for (const auto& app : applications) {
    Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE |
                                   PROCESS_TERMINATE, FALSE, app.dwProcessId));
    if (!process) {
      if (GetLastError() == ERROR_INVALID_PARAMETER) continue;
      return GetLastError();
    }
    FILETIME start{}, end{}, kernel{}, user{};
    if (!GetProcessTimes(process, &start, &end, &kernel, &user)) return GetLastError();
    // A PID can be reused between enumeration and shutdown.
    if (CompareFileTime(&start, &app.ProcessStartTime) != 0) continue;
    if (WaitForSingleObject(process, 0) == WAIT_OBJECT_0) continue;
    // Older clients may ignore WM_ENDSESSION or veto it with a close dialog.
    if (!TerminateProcess(process, ERROR_PROCESS_ABORTED)) return GetLastError();
    ++stats.forced;
    if (WaitForSingleObject(process, 5000) != WAIT_OBJECT_0) return ERROR_TIMEOUT;
  }
  return ERROR_SUCCESS;
}
}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  int argc = 0;
  auto argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv) return ERROR_BAD_ARGUMENTS;
  ShutdownStats stats;
  const DWORD result = argc == 3 ? StopInstalledApp(argv[1], stats) : ERROR_BAD_ARGUMENTS;
  if (argc == 3) {
    const auto details = "matched=" + std::to_string(stats.matched) +
        " graceful=" + std::to_string(stats.graceful) +
        " restart_manager=" + std::to_string(stats.restart_manager) +
        " forced=" + std::to_string(stats.forced) +
        " acknowledged=" + std::to_string(stats.acknowledged);
    Handle log(CreateFileW(argv[2], GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                           CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr));
    if (log != INVALID_HANDLE_VALUE) {
      DWORD written = 0;
      WriteFile(log, details.data(), static_cast<DWORD>(details.size()), &written, nullptr);
    }
  }
  LocalFree(argv);
  return static_cast<int>(result);
}
