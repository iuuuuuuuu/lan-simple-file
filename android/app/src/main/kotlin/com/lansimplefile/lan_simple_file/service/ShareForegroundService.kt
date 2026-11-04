// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.lansimplefile.lan_simple_file.MainActivity

/**
 * 会话级前台服务。
 *
 * 语义（docs/plan.md M7 + 决策笔记 android-session-scoped-sharing）：
 * - 只有存在活跃共享时才由 Dart 侧显式 start；无共享立即 stopSelf。
 * - Android 14+ 必须在 manifest 声明 foregroundServiceType=dataSync 且在
 *   startForeground 时传同一个类型，否则抛 MissingForegroundServiceTypeException。
 * - 服务不自己决定生死：状态由 ForegroundServiceBridge 推过来，
 *   本类只做「按指令起停 + 维护通知 + 维护组播锁」。
 *
 * 通知栏文案：共享中 · N 个文件 · 已连接 X 台 · [停止共享]
 */
class ShareForegroundService : Service() {

    companion object {
        /** 与 Dart 侧 kForegroundChannelName 对应。 */
        const val ACTION_START = "com.lansimplefile.lan_simple_file.action.START_SHARE"
        const val ACTION_STOP = "com.lansimplefile.lan_simple_file.action.STOP_SHARE"
        const val EXTRA_SHARE_COUNT = "shareCount"
        const val EXTRA_CONNECTED_PEERS = "connectedPeers"

        private const val CHANNEL_ID = "lan_simple_file_sharing"
        private const val CHANNEL_NAME = "共享状态"
        private const val NOTIFICATION_ID = 0x4C53

        /**
         * 通知文案直接内联，不走 res/values/strings.xml。
         *
         * 原因：本任务的写入范围只包含 service 包与 manifest/gradle/xml，
         * 新增 res/values/strings.xml 属越界；文案集中在本文件的常量里，
         * 后续要做 i18n 时再整体迁到 strings.xml。
         */
        private const val NOTIFICATION_TITLE_SHARING = "共享中"
        private const val NOTIFICATION_ACTION_STOP = "停止共享"

        /**
         * Android 14 起前台服务类型必须与 manifest 声明一致。
         *
         * 不能写成 `const val`——它依赖运行时读到的 SDK_INT，编译期无法求值。
         */
        private val fgsType: Int
            get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            }

        /** 服务的存活状态；Dart 侧 isRunning 直接读它，避免自己去问系统。 */
        @Volatile
        var isRunning: Boolean = false
            private set
    }

    private val multicast by lazy { MulticastLockHolder(this) }

    /** 当前展示的共享条目数，供 FLAG_UPDATE_CURRENT 之外的场合复用。 */
    private var shareCount: Int = 0

    private var connectedPeers: Int = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // 通知栏「停止共享」走的也是这里：停服务 + 释放锁，Dart 侧随后会收到状态同步。
            stopEverything()
            return START_NOT_STICKY
        }

        shareCount = intent?.getIntExtra(EXTRA_SHARE_COUNT, 0) ?: 0
        connectedPeers = intent?.getIntExtra(EXTRA_CONNECTED_PEERS, 0) ?: 0

        if (shareCount <= 0) {
            // 没有共享就没有前台服务存在的理由。
            stopEverything()
            return START_NOT_STICKY
        }

        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, fgsType)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (error: RuntimeException) {
            // Android 12+ 在后台启动前台服务会抛 ForegroundServiceStartNotAllowedException；
            // 这里把状态标记为未运行并停掉自己，让 Dart 侧能如实汇报失败。
            isRunning = false
            multicast.sync(false)
            stopSelf()
            return START_NOT_STICKY
        }

        isRunning = true
        // 有共享 = 需要收组播，此时才持锁。
        multicast.sync(true)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        multicast.sync(false)
        super.onDestroy()
    }

    private fun stopEverything() {
        isRunning = false
        multicast.sync(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    /** 供桥接层查询当前是否持锁。 */
    fun isMulticastHeld(): Boolean = multicast.isHeld

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) {
            return
        }
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "共享进行中的常驻提醒"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            pendingIntentFlags(),
        )

        val stopSharing = PendingIntent.getService(
            this,
            1,
            Intent(this, ShareForegroundService::class.java).apply {
                action = ACTION_STOP
            },
            pendingIntentFlags(),
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle(NOTIFICATION_TITLE_SHARING)
            .setContentText(notificationBody())
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(openApp)
            .addAction(
                Notification.Action.Builder(
                    null,
                    NOTIFICATION_ACTION_STOP,
                    stopSharing,
                ).build(),
            )
            .build()
    }

    /** 通知栏正文：N 个文件 · 已连接 X 台。 */
    private fun notificationBody(): String =
        "$shareCount 个文件 · 已连接 $connectedPeers 台"

    private fun pendingIntentFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
}
