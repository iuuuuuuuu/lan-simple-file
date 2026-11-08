// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import java.net.Inet4Address

internal fun isLanTransport(wifi: Boolean, ethernet: Boolean, cellular: Boolean, vpn: Boolean): Boolean =
    (wifi || ethernet) && !cellular && !vpn

/** Reads connected local transports without changing system/process routing. */
@Suppress("DEPRECATION")
internal fun readLanInterfaces(context: Context): List<Map<String, Any>> {
    val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    return manager.allNetworks.mapNotNull { network ->
        val caps = manager.getNetworkCapabilities(network) ?: return@mapNotNull null
        if (!isLanTransport(
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET),
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
                caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN),
            )) return@mapNotNull null
        val links = manager.getLinkProperties(network) ?: return@mapNotNull null
        val name = links.interfaceName ?: return@mapNotNull null
        mapOf(
            "name" to name,
            "isDefault" to (network == manager.activeNetwork),
            "addresses" to links.linkAddresses.mapNotNull {
                (it.address as? Inet4Address)?.hostAddress
            },
        )
    }
}
