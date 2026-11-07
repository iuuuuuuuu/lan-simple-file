// SPDX-License-Identifier: GPL-3.0-only
#ifndef DROP_TEST_DATA_H_
#define DROP_TEST_DATA_H_

#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <string>
#include <vector>

inline std::vector<std::wstring> TestDropPaths() {
  return {L"C:\\drop\\\u4e2d\u6587.txt",
          L"C:\\drop\\" + std::wstring(400, L'a') + L".txt"};
}

inline HDROP MakeTestDrop() {
  const auto paths = TestDropPaths();
  size_t chars = 1;
  for (const auto& path : paths) chars += path.size() + 1;
  auto memory = GlobalAlloc(GHND, sizeof(DROPFILES) + chars * sizeof(wchar_t));
  if (!memory) return nullptr;
  auto data = static_cast<DROPFILES*>(GlobalLock(memory));
  data->pFiles = sizeof(DROPFILES);
  data->fWide = TRUE;
  data->pt = {30, 40};
  auto cursor = reinterpret_cast<wchar_t*>(
      reinterpret_cast<char*>(data) + sizeof(DROPFILES));
  for (const auto& path : paths) {
    std::copy(path.begin(), path.end(), cursor);
    cursor += path.size() + 1;
  }
  GlobalUnlock(memory);
  return static_cast<HDROP>(memory);
}
#endif
