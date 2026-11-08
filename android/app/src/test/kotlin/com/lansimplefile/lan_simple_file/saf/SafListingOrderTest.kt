// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file.saf

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SafListingOrderTest {
    private fun entry(key: String, folder: Boolean) =
        SafItem("primary:1/$key", key, folder, null, null, null)

    @Test fun foldersPrecedeFilesRegardlessOfProviderOrder() {
        val items = listOf(entry("b", false), entry("z", true), entry("a", false), entry("y", true))
        assertEquals(listOf("y", "z", "a", "b"), items.sortedWith(safListingOrder).map { it.name })
    }

    @Test fun cursorCrossesKindBoundaryAndSurvivesDeletedDirectory() {
        assertTrue(isAfterSafCursor(entry("z", true), "primary:1/y", true))
        assertTrue(isAfterSafCursor(entry("a", false), "primary:1/y", true))
        assertFalse(isAfterSafCursor(entry("x", true), "primary:1/y", true))
        assertFalse(isAfterSafCursor(entry("y", true), "primary:1/y", true))
        assertFalse(isAfterSafCursor(entry("z", true), "primary:1/a", false))
        assertTrue(isAfterSafCursor(entry("b", false), "primary:1/a", false))
    }
}
