// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LanNetworksTest {
    @Test fun wifiAndEthernetAreLocalTransports() {
        assertTrue(isLanTransport(wifi = true, ethernet = false, cellular = false, vpn = false))
        assertTrue(isLanTransport(wifi = false, ethernet = true, cellular = false, vpn = false))
    }

    @Test fun cellularAndVpnAreExcludedEvenWithUnderlyingWifi() {
        assertFalse(isLanTransport(wifi = false, ethernet = false, cellular = true, vpn = false))
        assertFalse(isLanTransport(wifi = true, ethernet = false, cellular = false, vpn = true))
        assertFalse(isLanTransport(wifi = true, ethernet = false, cellular = true, vpn = false))
        assertFalse(isLanTransport(wifi = false, ethernet = false, cellular = false, vpn = false))
    }
}
