// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file

import android.app.Activity
import android.app.ActivityManager
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** App-owned metadata only. No SSID, MAC, serial, shared files, or credentials. */
class NetworkDiagnosticsHandler(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val multicastHeld: () -> Boolean,
) {
    private val channel = MethodChannel(messenger, "lan_simple_file/network_diagnostics")
    private var pendingSave: MethodChannel.Result? = null
    private var pendingFile: File? = null

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "snapshot" -> result.success(snapshot())
                    "share", "save" -> {
                        val file = File(call.argument<String>("path") ?: "").canonicalFile
                        val allowed = File(activity.cacheDir, "network-diagnostics/lan-network-diagnostics.txt").canonicalFile
                        require(file == allowed && file.isFile && file.length() <= 2 * 1024 * 1024)
                        if (call.method == "share") {
                            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.diagnostics", file)
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                clipData = ClipData.newRawUri("Network diagnostics", uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            activity.startActivity(Intent.createChooser(intent, "分享网络诊断日志"))
                            result.success(true)
                        } else if (pendingSave != null) {
                            result.error("busy", "正在保存日志", null)
                        } else {
                            pendingSave = result
                            pendingFile = file
                            @Suppress("DEPRECATION")
                            activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TITLE, "lan-network-diagnostics.txt")
                            }, SAVE_REQUEST)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                if (pendingSave === result) {
                    pendingSave = null
                    pendingFile = null
                }
                result.error("diagnostics", e.javaClass.simpleName, null)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun snapshot(): Map<String, Any?> {
        val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val wifi = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val power = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
        return mapOf(
            "version" to info.versionName,
            "versionCode" to if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong(),
            "sdk" to Build.VERSION.SDK_INT,
            "androidRelease" to Build.VERSION.RELEASE,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "targetSdk" to activity.applicationInfo.targetSdkVersion,
            "wifiEnabled" to wifi.isWifiEnabled,
            "activityMulticastHeld" to multicastHeld(),
            "powerSave" to power.isPowerSaveMode,
            "deviceIdle" to power.isDeviceIdleMode,
            "ignoresBatteryOptimizations" to power.isIgnoringBatteryOptimizations(activity.packageName),
            "backgroundRestricted" to if (Build.VERSION.SDK_INT >= 28) am.isBackgroundRestricted else null,
            "restrictBackgroundStatus" to cm.restrictBackgroundStatus,
            "permissions" to listOf("INTERNET", "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE", "CHANGE_WIFI_MULTICAST_STATE", "NEARBY_WIFI_DEVICES", "ACCESS_LOCAL_NETWORK").associateWith {
                activity.checkSelfPermission("android.permission.$it") == PackageManager.PERMISSION_GRANTED
            },
            "networks" to cm.allNetworks.take(12).map { network ->
                val caps = cm.getNetworkCapabilities(network)
                val links = cm.getLinkProperties(network)
                mapOf(
                    "default" to (network == cm.activeNetwork),
                    "wifi" to caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
                    "cellular" to caps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
                    "vpn" to caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN),
                    "ethernet" to caps?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET),
                    "internet" to caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
                    "validated" to caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
                    "notRestricted" to caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED),
                    "interface" to links?.interfaceName,
                    "addresses" to links?.linkAddresses?.map { it.toString() },
                    "routes" to links?.routes?.map { mapOf("destination" to it.destination.toString(), "gateway" to it.gateway?.hostAddress, "interface" to it.`interface`) },
                    "dns" to links?.dnsServers?.map { it.hostAddress },
                    "proxyHost" to links?.httpProxy?.host,
                    "proxyPort" to links?.httpProxy?.port,
                    "proxyPac" to (links?.httpProxy?.pacFileUrl?.toString()?.isNotEmpty() == true),
                )
            },
        )
    }

    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != SAVE_REQUEST) return false
        val result = pendingSave ?: return true
        val file = pendingFile
        pendingSave = null
        pendingFile = null
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null || file == null) {
            result.success(false)
            return true
        }
        // Copying up to 1.5 MiB must not block the Android UI thread.
        Thread {
            try {
                activity.contentResolver.openOutputStream(uri, "wt").use { output ->
                    requireNotNull(output)
                    file.inputStream().use { it.copyTo(output) }
                }
                activity.runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("save_failed", e.javaClass.simpleName, null) }
            }
        }.start()
        return true
    }

    fun detach() {
        pendingSave?.success(false)
        pendingSave = null
        pendingFile = null
        channel.setMethodCallHandler(null)
    }

    companion object { private const val SAVE_REQUEST = 4917 }
}
