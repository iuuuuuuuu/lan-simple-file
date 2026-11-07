// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file

internal fun resolveDeviceName(model: String?, readers: List<() -> String?>): String {
    fun clean(value: String?) = value?.trim()?.takeIf {
        it.isNotEmpty() && !it.equals("null", ignoreCase = true)
    }
    fun comparable(value: String) = value.lowercase().filter { it.isLetterOrDigit() }
    val fallback = clean(model) ?: "Android"
    var first: String? = null
    for (read in readers) {
        val candidate = try { clean(read()) } catch (_: SecurityException) { null }
        if (candidate != null) {
            if (first == null) first = candidate
            // Some ROMs retain the model in Global after the owner renames the device.
            if (comparable(candidate) != comparable(fallback)) return candidate
        }
    }
    return first ?: fallback
}
