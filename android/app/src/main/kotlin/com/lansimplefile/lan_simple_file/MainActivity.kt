// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file

import android.content.Intent
import android.os.Bundle
import com.lansimplefile.lan_simple_file.saf.SafBridgeHandler
import com.lansimplefile.lan_simple_file.service.ForegroundChannelHandler
import com.lansimplefile.lan_simple_file.service.ShareIntentHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var safBridge: SafBridgeHandler? = null

    private var foreground: ForegroundChannelHandler? = null

    private var shareIntent: ShareIntentHandler? = null

    /**
     * 冷启动那一刻的 SEND intent。
     *
     * 不能在 onCreate 里就交给 ShareIntentHandler —— 那时 FlutterEngine 还不存在，
     * 没有 BinaryMessenger。先原样存下 LaunchIntent，等 configureFlutterEngine
     * 建好通道后再 acceptIntent，Dart 侧启动后 takePendingIntent 就能取到。
     */
    private var launchIntent: Intent? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        launchIntent = intent
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val saf = SafBridgeHandler(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        saf.attach()
        safBridge = saf

        foreground = ForegroundChannelHandler.attach(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )

        val intentHandler = ShareIntentHandler.attach(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        shareIntent = intentHandler
        // 冷启动分享：此时通道已就绪，可以安全挂起等 Dart 来取。
        intentHandler.acceptIntent(launchIntent ?: intent)
        launchIntent = null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // 热启动分享：通道已存在，直接推给 Dart。
        val handler = shareIntent ?: return
        if (!handler.acceptIntent(intent)) {
            return
        }
        val payload = handler.takePending() ?: return
        handler.deliverToDart(payload)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        safBridge?.detach()
        safBridge = null
        foreground?.detach()
        foreground = null
        shareIntent?.detach()
        shareIntent = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
