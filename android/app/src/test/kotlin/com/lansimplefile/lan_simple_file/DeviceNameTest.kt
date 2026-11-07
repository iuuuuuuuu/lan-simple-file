// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file

import org.junit.Assert.assertEquals
import org.junit.Test

class DeviceNameTest {
    @Test fun prefersOwnerNameOverModel() {
        assertEquals("好好吃饭", resolveDeviceName("Xiaomi 15 Pro", listOf(
            { " 好好吃饭 " }, { "xiaomi-15-pro" },
        )))
        assertEquals("好好吃饭", resolveDeviceName("Xiaomi 15 Pro", listOf(
            { null }, { "xiaomi-15-pro" }, { "好好吃饭" },
        )))
    }

    @Test fun skipsIndividualDeniedOrEmptySettings() {
        assertEquals("Owner", resolveDeviceName("Model", listOf(
            { throw SecurityException() }, { "null" }, { " " }, { "Owner" },
        )))
        assertEquals("Model", resolveDeviceName("Model", listOf({ null })))
        assertEquals("Android", resolveDeviceName(" ", emptyList()))
    }
}
