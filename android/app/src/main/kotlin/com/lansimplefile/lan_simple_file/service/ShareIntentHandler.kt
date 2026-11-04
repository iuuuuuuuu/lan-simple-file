// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file.service

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicReference

/**
 * ACTION_SEND / ACTION_SEND_MULTIPLE 的接收端。
 *
 * 两条入口：
 * 1. 冷启动：MainActivity 的 intent 里已经带数据，Dart 侧启动后调 takePendingIntent 取走。
 * 2. 热启动：onNewIntent 推过来，经 onShareIntent 通道回调主动推给 Dart。
 *
 * 取走即清，保证同一次分享不会被重复建 share。
 */
internal class ShareIntentHandler private constructor(
    private val context: Context,
    private val channel: MethodChannel,
) {

    companion object {
        const val CHANNEL = "lan.simple.file/share-intent"

        /** 单次分享最多处理的条目数，与 Dart 侧 kMaxSharedItems 保持一致。 */
        const val MAX_ITEMS = 100

        fun attach(context: Context, messenger: BinaryMessenger): ShareIntentHandler {
            val handler = ShareIntentHandler(
                context.applicationContext,
                MethodChannel(messenger, CHANNEL),
            )
            handler.channel.setMethodCallHandler { call, result ->
                if (call.method == "takePendingIntent") {
                    result.success(handler.takePending())
                } else {
                    result.notImplemented()
                }
            }
            return handler
        }
    }

    private val pending = AtomicReference<Map<String, Any?>?>(null)

    fun detach() {
        channel.setMethodCallHandler(null)
    }

    /**
     * 从 Intent 里提取分享内容并挂起（不直接消费），返回是否采到了东西。
     *
     * 只接受 SEND / SEND_MULTIPLE；其它 action 一律忽略，不影响正常启动。
     */
    fun acceptIntent(intent: Intent?): Boolean {
        val action = intent?.action ?: return false
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return false
        }
        val payload = extract(action, intent) ?: return false
        pending.set(payload)
        return true
    }

    /** 取走待处理分享，取完即清。 */
    fun takePending(): Map<String, Any?>? = pending.getAndSet(null)

    /** 有新分享时主动推给 Dart（热启动路径）。 */
    fun deliverToDart(payload: Map<String, Any?>) {
        channel.invokeMethod("onShareIntent", payload)
    }

    private fun extract(action: String, intent: Intent): Map<String, Any?>? {
        val items = ArrayList<Map<String, Any?>>()
        val mime = intent.type

        if (action == Intent.ACTION_SEND) {
            val uri = firstUriOf(intent) ?: return null
            items.add(mapOf("uri" to uri.toString(), "mime" to mime))
        } else {
            val clip = intent.clipData
            val extraUris: List<Uri> = if (clip != null) {
                (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
            } else {
                @Suppress("DEPRECATION")
                (intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList())
            }
            for (uri in extraUris) {
                if (items.size >= MAX_ITEMS) {
                    // 超限时如实报给 Dart，由它给出「分批分享」的提示；
                    // 这里不静默截断，避免用户以为全都共享了。
                    items.add(mapOf("uri" to "overflow://too-many", "mime" to mime))
                    break
                }
                items.add(mapOf("uri" to uri.toString(), "mime" to mime))
            }
        }

        if (items.isEmpty()) {
            return null
        }
        return mapOf(
            "action" to action,
            "subject" to (intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: ""),
            "items" to items,
        )
    }

    private fun firstUriOf(intent: Intent): Uri? {
        val clip: ClipData? = intent.clipData
        if (clip != null && clip.itemCount > 0) {
            return clip.getItemAt(0).uri
        }
        @Suppress("DEPRECATION")
        return intent.getParcelableExtra(Intent.EXTRA_STREAM)
    }
}
