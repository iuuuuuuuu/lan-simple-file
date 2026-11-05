// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file.service

import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 前台服务 + 组播锁 + 权限查询的通道实现。
 *
 * 通道名 "lan.simple.file/foreground" 与 "lan.simple.file/permissions"：
 * 两件事分两条通道是因为生命周期不同——前台服务在共享期间高频同步，
 * 权限引导只在设置页进入时跑一次。
 */
internal class ForegroundChannelHandler private constructor(
    private val context: Context,
    private val foregroundChannel: MethodChannel,
    private val permissionChannel: MethodChannel,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val FOREGROUND_CHANNEL = "lan.simple.file/foreground"
        const val PERMISSION_CHANNEL = "lan.simple.file/permissions"

        fun attach(context: Context, messenger: BinaryMessenger): ForegroundChannelHandler {
            val handler = ForegroundChannelHandler(
                context.applicationContext,
                MethodChannel(messenger, FOREGROUND_CHANNEL),
                MethodChannel(messenger, PERMISSION_CHANNEL),
            )
            handler.foregroundChannel.setMethodCallHandler(handler)
            handler.permissionChannel.setMethodCallHandler(handler)
            return handler
        }
    }

    private val multicast by lazy { MulticastLockHolder(context) }

    private val stopRequested = AtomicBoolean(false)

    val isStopRequested: Boolean
        get() = stopRequested.get()

    fun requestStop() {
        stopRequested.set(true)
    }

    fun clearStopRequest() {
        stopRequested.set(false)
    }

    fun detach() {
        foregroundChannel.setMethodCallHandler(null)
        permissionChannel.setMethodCallHandler(null)
        multicast.sync(false)
    }

    fun isMulticastHeld(): Boolean = multicast.isHeld

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "apply" -> applyState(call, result)
            "isRunning" -> result.success(isServiceRunning())
            "syncMulticastLock" -> syncMulticastLock(call, result)
            "androidSdk" -> result.success(Build.VERSION.SDK_INT)
            "queryStates" -> result.success(queryPermissionStates())
            "openAllFilesAccessSettings" -> openAllFilesAccessSettings(result)
            "request" -> requestPermission(call, result)
            else -> result.notImplemented()
        }
    }

    // ---- 前台服务 ----

    private fun applyState(call: MethodCall, result: MethodChannel.Result) {
        val running = call.argument<Boolean>("running")
        if (running == null) {
            result.error("invalidArgument", "缺少 running 参数", null)
            return
        }
        val shareCount = call.argument<Int>("shareCount") ?: 0
        val connectedPeers = call.argument<Int>("connectedPeers") ?: 0

        if (!running || shareCount <= 0) {
            stopService()
            multicast.sync(false)
            result.success(null)
            return
        }

        if (!notificationsEnabled()) {
            // Android 13+ 没有通知权限时前台服务通知不可见，系统会直接拒绝；
            // 提前给出可判定的错误码，比让 startForeground 抛更好读。
            result.error(
                "notificationDenied",
                "缺少通知权限，无法展示共享中通知",
                null,
            )
            return
        }

        val intent = Intent(context, ShareForegroundService::class.java).apply {
            action = ShareForegroundService.ACTION_START
            putExtra(ShareForegroundService.EXTRA_SHARE_COUNT, shareCount)
            putExtra(ShareForegroundService.EXTRA_CONNECTED_PEERS, connectedPeers)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        } catch (error: IllegalStateException) {
            // Android 12+ 后台启动限制。
            result.error("startRejected", error.message ?: "无法启动前台服务", null)
            return
        } catch (error: SecurityException) {
            result.error("notificationDenied", error.message ?: "缺少前台服务权限", null)
            return
        }
        multicast.sync(true)
        result.success(null)
    }

    private fun isServiceRunning(): Boolean {
        // 不便于直接问系统（ActivityManager 在 Android 8+ 对外部查询有限制），
        // 因此服务自己在生命周期里维护 isRunning 标志。
        return ShareForegroundService.isRunning
    }

    private fun stopService() {
        context.stopService(Intent(context, ShareForegroundService::class.java))
    }

    private fun syncMulticastLock(call: MethodCall, result: MethodChannel.Result) {
        val hold = call.argument<Boolean>("hold")
        if (hold == null) {
            result.error("invalidArgument", "缺少 hold 参数", null)
            return
        }
        result.success(multicast.sync(hold))
    }

    // ---- 权限 ----

    private fun queryPermissionStates(): Map<String, String> {
        val states = LinkedHashMap<String, String>()
        states["notifications"] = when {
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU -> "notRequired"
            notificationsEnabled() -> "granted"
            else -> "denied"
        }
        states["batteryOptimization"] = if (ignoringBatteryOptimizations()) {
            "granted"
        } else {
            "denied"
        }
        // SAF 授权由 Dart 侧通过 SAF 通道单独判定（persistedUriPermissions），
        // 这里只报"是否已有一条持久授权"，没有就是 denied。
        states["safGrant"] = if (hasPersistedSafGrant()) "granted" else "denied"
        states["allFilesAccess"] = when {
            Build.VERSION.SDK_INT < Build.VERSION_CODES.R -> "notRequired"
            Environment.isExternalStorageManager() -> "granted"
            else -> "denied"
        }
        return states
    }

    private fun openAllFilesAccessSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.error("unsupported", "所有文件访问设置需要 Android 11 或更高版本", null)
            return
        }
        val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
            data = Uri.fromParts("package", context.packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            try {
                context.startActivity(intent)
            } catch (error: ActivityNotFoundException) {
                context.startActivity(
                    Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    },
                )
            }
            // Opening Settings is not a grant; query again after the user returns.
            result.success(null)
        } catch (error: ActivityNotFoundException) {
            result.error("settingsUnavailable", "系统没有提供所有文件访问设置", null)
        } catch (error: SecurityException) {
            result.error("settingsRejected", error.message ?: "系统拒绝打开授权设置", null)
        }
    }

    private fun requestPermission(call: MethodCall, result: MethodChannel.Result) {
        val step = call.argument<String>("step")
        when (step) {
            "notifications" -> openAppNotificationSettings()
            "batteryOptimization" -> openBatteryOptimizationSettings()
            "safGrant" -> openDocumentTreePicker()
            else -> {
                result.error("invalidArgument", "未知步骤: " + (step ?: "null"), null)
                return
            }
        }
        // 这些都是跳到系统页由用户操作，无法同步得知结果；
        // 调用方需在回到前台后用 queryStates 复核。
        result.success(false)
    }

    private fun notificationsEnabled(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return NotificationManagerCompat.from(context).areNotificationsEnabled()
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    private fun ignoringBatteryOptimizations(): Boolean {
        val manager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return manager.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun hasPersistedSafGrant(): Boolean {
        val resolver = context.contentResolver
        return resolver.persistedUriPermissions.any { it.isReadPermission }
    }

    private fun openAppNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            }
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", context.packageName, null)
            }
        }
        launch(intent)
    }

    private fun openBatteryOptimizationSettings() {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:" + context.packageName)
        }
        launch(intent)
    }

    private fun openDocumentTreePicker() {
        // 真正的选择器由 SAF 模块弹出；这里只给出设置入口，
        // 避免两个模块各自弹一次选择器。
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", context.packageName, null)
        }
        launch(intent)
    }

    private fun launch(intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (error: android.content.ActivityNotFoundException) {
            // 系统没有这个设置页（定制 ROM），静默降级：用户仍可手动去设置里改。
        }
    }
}
