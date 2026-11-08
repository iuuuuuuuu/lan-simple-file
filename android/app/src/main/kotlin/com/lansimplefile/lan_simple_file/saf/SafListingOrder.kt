// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file.saf

internal val safListingOrder: Comparator<SafItem> =
    compareByDescending<SafItem> { it.isDirectory }.thenBy { it.documentId }

internal fun isAfterSafCursor(item: SafItem, key: String, isDirectory: Boolean): Boolean =
    if (item.isDirectory == isDirectory) item.documentId > key else !item.isDirectory
