// SPDX-License-Identifier: GPL-3.0-only

/// Directory cursors retain the entry kind even when that entry is deleted.
/// Control characters cannot occur in ItemKey, so file keys stay unambiguous.
const _directoryPrefix = '\u0001d/';

String directoryCursor(String key, bool isDirectory) =>
    isDirectory ? '$_directoryPrefix$key' : key;

({String key, bool isDirectory}) decodeDirectoryCursor(String cursor) =>
    cursor.startsWith(_directoryPrefix)
    ? (key: cursor.substring(_directoryPrefix.length), isDirectory: true)
    : (key: cursor, isDirectory: false);

int compareDirectoryKeys(String a, bool aDir, String b, bool bDir) =>
    aDir == bDir
    ? a.compareTo(b)
    : aDir
    ? -1
    : 1;

bool isAfterDirectoryCursor(String key, bool isDirectory, String cursor) {
  final previous = decodeDirectoryCursor(cursor);
  return compareDirectoryKeys(
        key,
        isDirectory,
        previous.key,
        previous.isDirectory,
      ) >
      0;
}
