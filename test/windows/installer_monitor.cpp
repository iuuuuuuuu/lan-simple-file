// SPDX-License-Identifier: GPL-3.0-only
#include <windows.h>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace fs = std::filesystem;

std::wstring Quote(const fs::path& path) { return L"\"" + path.wstring() + L"\""; }

LRESULT CALLBACK LegacyWindow(HWND window, UINT message, WPARAM wp, LPARAM lp) {
  if (message == WM_CLOSE) { ShowWindow(window, SW_HIDE); return 0; }
  if (message == WM_QUERYENDSESSION) return FALSE;
  return DefWindowProcW(window, message, wp, lp);
}

int LegacyClient(const fs::path& output) {
  WNDCLASSW wc{};
  wc.lpfnWndProc = LegacyWindow;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = L"LanSimpleInstallerLegacyFixture";
  RegisterClassW(&wc);
  if (!CreateWindowW(wc.lpszClassName, L"Legacy tray client", WS_OVERLAPPEDWINDOW,
                    0, 0, 100, 100, nullptr, nullptr, wc.hInstance, nullptr)) return 2;
  fs::create_directories(output);
  std::ofstream(output / L"ready") << "legacy";
  MSG message;
  while (GetMessageW(&message, nullptr, 0, 0)) DispatchMessageW(&message);
  return 0;
}

struct Child {
  PROCESS_INFORMATION process{};
  DWORD completed_code = STILL_ACTIVE;
  ~Child() {
    if (process.hThread) CloseHandle(process.hThread);
    if (process.hProcess) CloseHandle(process.hProcess);
  }
  bool Start(const fs::path& exe, const std::wstring& args,
             const std::wstring& desktop, HANDLE job) {
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.lpDesktop = const_cast<wchar_t*>(desktop.c_str());
    auto command = Quote(exe) + L" " + args;
    if (!CreateProcessW(exe.c_str(), command.data(), nullptr, nullptr, FALSE,
                        CREATE_SUSPENDED | CREATE_NO_WINDOW, nullptr,
                        exe.parent_path().c_str(), &startup, &process)) return false;
    if (!AssignProcessToJobObject(job, process.hProcess)) {
      TerminateProcess(process.hProcess, 2);
      return false;
    }
    ResumeThread(process.hThread);
    CloseHandle(process.hThread);
    process.hThread = nullptr;
    return true;
  }
  void ObserveExit() {
    if (process.hProcess && WaitForSingleObject(process.hProcess, 0) == WAIT_OBJECT_0) {
      GetExitCodeProcess(process.hProcess, &completed_code);
      CloseHandle(process.hProcess);
      process.hProcess = nullptr;
    }
  }
  bool Alive() const {
    return process.hProcess && WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT;
  }
  DWORD ExitCode() const {
    DWORD code = completed_code;
    if (process.hProcess) GetExitCodeProcess(process.hProcess, &code);
    return code;
  }
};

bool Ready(const Child& child, const fs::path& output) {
  const auto deadline = GetTickCount64() + 30000;
  while (child.Alive() && GetTickCount64() < deadline) {
    if (fs::exists(output / L"ready")) return true;
    Sleep(20);
  }
  return false;
}

// Exercise the real wizard using HWND messages on our private desktop only.
bool install_clicked = false;
BOOL CALLBACK AdvanceControl(HWND control, LPARAM) {
  if (!IsWindowVisible(control) || !IsWindowEnabled(control)) return TRUE;
  wchar_t text[256]{};
  GetWindowTextW(control, text, 256);
  const std::wstring caption(text);
  if (caption == L"&Install") {
    if (install_clicked) return TRUE;
    install_clicked = true;
  }
  if (caption == L"I &accept the agreement" || caption == L"&Next >" || caption == L"&Next" ||
      caption == L"&Install" || caption == L"&Finish") {
    SendMessageTimeoutW(control, BM_CLICK, 0, 0, SMTO_ABORTIFHUNG, 1000, nullptr);
  }
  return TRUE;
}

BOOL CALLBACK AdvanceWizard(HWND window, LPARAM) {
  wchar_t name[128]{};
  GetClassNameW(window, name, 128);
  if (std::wstring(name).find(L"TWizardForm") == 0) EnumChildWindows(window, AdvanceControl, 0);
  return TRUE;
}

BOOL CALLBACK DescribeControl(HWND window, LPARAM) {
  wchar_t name[128]{}, text[256]{};
  GetClassNameW(window, name, 128);
  GetWindowTextW(window, text, 256);
  if (IsWindowVisible(window)) {
    std::wcout << L"window=" << name << L" caption=" << text
               << L" enabled=" << IsWindowEnabled(window) << std::endl;
  }
  return TRUE;
}

BOOL CALLBACK DescribeWindow(HWND window, LPARAM) {
  DescribeControl(window, 0);
  EnumChildWindows(window, DescribeControl, 0);
  return TRUE;
}

int wmain(int argc, wchar_t** argv) {
  if (argc == 3 && std::wstring(argv[1]) == L"--legacy") return LegacyClient(argv[2]);
  if (argc != 6) return 2;
  const fs::path installer = fs::absolute(argv[1]);
  const fs::path probe = fs::absolute(argv[2]);
  const fs::path output = fs::absolute(argv[3]);
  const std::wstring mode = argv[4];
  const bool silent = std::wstring(argv[5]) == L"silent";
  const auto target = output / L"installed app";
  const auto other = output / L"other copy";
  if (fs::exists(output)) return 3;
  fs::create_directories(target);
  fs::create_directories(other);
  fs::create_directories(output / L"client");
  wchar_t self[32768]{};
  GetModuleFileNameW(nullptr, self, 32768);
  fs::copy_file(self, other / L"lan_simple_file.exe");
  if (mode == L"legacy") {
    fs::copy_file(self, target / L"lan_simple_file.exe");
  } else if (mode != L"fresh") {
    fs::copy(probe.parent_path(), target, fs::copy_options::recursive);
  }
  std::ofstream(output / L"client" / L"preserve.txt") << "user data must survive";
  const std::wstring desktop_name = L"LanSimpleInstallerTest-" + std::to_wstring(GetCurrentProcessId());
  HDESK desktop = CreateDesktopW(desktop_name.c_str(), nullptr, nullptr, 0, GENERIC_ALL, nullptr);
  if (!desktop || !SetThreadDesktop(desktop)) return 4;
  // Never switch the input desktop or send input to the user's windows.
  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) return 5;
  Child unrelated, client, setup;
  if (!unrelated.Start(other / L"lan_simple_file.exe", L"--legacy " + Quote(other), desktop_name, job) ||
      !Ready(unrelated, other)) return 6;
  if (mode != L"fresh") {
    const auto args = mode == L"legacy" ? L"--legacy " + Quote(output / L"client") :
        Quote(output / L"client") + L" installer-" + mode;
    if (!client.Start(target / L"lan_simple_file.exe", args, desktop_name, job) ||
        !Ready(client, output / L"client")) return 7;
  }
  auto args = L"/SP- /NORESTART /DIR=" + Quote(target) + L" /LOG=" + Quote(output / L"setup.log");
  if (silent) args += L" /VERYSILENT /SUPPRESSMSGBOXES";
  const auto start = GetTickCount64();
  if (!setup.Start(installer, args, desktop_name, job)) return 8;
  while (setup.Alive() && GetTickCount64() - start < 120000) {
    // Do not keep an exited process's image mapped while Setup replaces it.
    if (mode != L"fresh") client.ObserveExit();
    if (!silent) EnumDesktopWindows(desktop, AdvanceWizard, 0);
    Sleep(50);
  }
  if (setup.Alive()) EnumDesktopWindows(desktop, DescribeWindow, 0);
  const bool exited = mode == L"fresh" || !client.Alive();
  const DWORD client_code = mode == L"fresh" ? 0 : client.ExitCode();
  const bool passed = !setup.Alive() && setup.ExitCode() == 0 && exited &&
      (mode == L"legacy" || client_code == 0) && unrelated.Alive() &&
      fs::exists(target / L"data" / L"app.so") &&
      fs::exists(output / L"client" / L"preserve.txt");
  std::wcout << L"mode=" << mode << L" silent=" << silent
            << " setup_exit=" << setup.ExitCode() << " client_exit=" << client_code
            << " unrelated_alive=" << unrelated.Alive() << " duration_ms=" << GetTickCount64() - start
            << " passed=" << passed << '\n';
  // All remaining children belong to this disposable test job.
  TerminateJobObject(job, 0);
  CloseHandle(job);
  return passed ? 0 : 1;
}
