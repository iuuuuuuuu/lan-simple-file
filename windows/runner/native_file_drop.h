// SPDX-License-Identifier: GPL-3.0-only
#ifndef RUNNER_NATIVE_FILE_DROP_H_
#define RUNNER_NATIVE_FILE_DROP_H_

#include <windows.h>
#include <shellapi.h>

#include <string>
#include <vector>

struct NativeFileDrop {
  POINT position{};
  std::vector<std::string> paths;
};

bool EnableElevatedFileDrop(HWND window, HWND flutter_view);
NativeFileDrop ReadNativeFileDrop(HDROP drop, HWND window, HWND flutter_view);

#endif  // RUNNER_NATIVE_FILE_DROP_H_
