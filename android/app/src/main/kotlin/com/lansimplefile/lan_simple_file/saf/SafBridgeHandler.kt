// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file.saf

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * 安卓侧 SAF 桥。通道名必须与 Dart 侧 kSafChannelName 一致：
 * "lan.simple.file/saf"。
 *
 * 方法：
 *   listChildren(treeUri, documentId, cursor?, limit) -> List<Map>
 *   statItem(treeUri, documentId)                     -> Map
 *   openRead(treeUri, documentId, start?, endExclusive?) -> String handle
 *   readChunk(handle, maxBytes)                       -> ByteArray?（null = EOF）
 *   closeRead(handle)                                 -> null
 *   exists(treeUri, documentId)                       -> Boolean
 *   canRead(treeUri)                                  -> Boolean
 *
 * 全部工作在单线程 executor 上顺序执行：句柄表不需要加锁，
 * 也避免 ContentResolver 在多个线程上并发访问同一 provider。
 */
internal class SafBridgeHandler(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "lan.simple.file/saf"

        /** 与 Dart 侧 kSafReadChunkBytes 一致：256 KiB。 */
        const val MAX_CHUNK_BYTES = 256 * 1024

        /** 同时存在的读取句柄上限，防止泄漏把 fd 吃光。 */
        const val MAX_OPEN_HANDLES = 64
    }

    private val appContext: Context = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val documents = SafDocuments(appContext, appContext.contentResolver)
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "saf-bridge").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val handleSeq = AtomicLong(0)
    private val handles = LinkedHashMap<String, OpenStream>()

    fun attach() {
        channel.setMethodCallHandler(this)
    }

    fun detach() {
        channel.setMethodCallHandler(null)
        worker.execute { closeAllHandles() }
        worker.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        worker.execute {
            val outcome = runCatching { dispatch(call) }
            mainHandler.post {
                outcome.fold(
                    { value -> result.success(value) },
                    { error ->
                        val failure = error.toSafFailure(call.method)
                        result.error(failure.code, failure.message, null)
                    },
                )
            }
        }
    }

    private fun dispatch(call: MethodCall): Any? = when (call.method) {
        "listChildren" -> listChildren(call)
        "statItem" -> statItem(call)
        "openRead" -> openRead(call)
        "readChunk" -> readChunk(call)
        "closeRead" -> closeRead(call)
        "exists" -> exists(call)
        "canRead" -> canRead(call)
        else -> throw SafFailure(SafErrorCode.UNSUPPORTED, "未知方法：${call.method}")
    }

    private fun listChildren(call: MethodCall): List<Map<String, Any?>> {
        val treeUri = requireTreeUri(call, "treeUri")
        val documentId = requireDocumentId(call, "documentId")
        val cursor = call.argument<String>("cursor")?.takeIf { it.isNotEmpty() }
        val limit = requireLimit(call, "limit")
        return documents.listChildren(treeUri, documentId, cursor, limit).map { it.toMap() }
    }

    private fun statItem(call: MethodCall): Map<String, Any?> {
        val treeUri = requireTreeUri(call, "treeUri")
        val documentId = requireDocumentId(call, "documentId")
        return documents.statItem(treeUri, documentId).toMap()
    }

    private fun openRead(call: MethodCall): String {
        val treeUri = requireTreeUri(call, "treeUri")
        val documentId = requireDocumentId(call, "documentId")
        val start = call.argument<Int>("start")?.toLong() ?: 0L
        val endExclusive = call.argument<Int>("endExclusive")?.toLong()
        if (handles.size >= MAX_OPEN_HANDLES) {
            val oldest = handles.keys.firstOrNull()
                ?: throw SafFailure(SafErrorCode.INTERNAL, "句柄表异常")
            handles.remove(oldest)?.close()
        }
        val stream = documents.openStream(treeUri, documentId, start, endExclusive)
        val handle = "saf-" + handleSeq.incrementAndGet()
        handles[handle] = stream
        return handle
    }

    private fun readChunk(call: MethodCall): ByteArray? {
        val handle = call.argument<String>("handle")
            ?: throw SafFailure(SafErrorCode.INVALID_ARGUMENT, "缺少 handle")
        val stream = handles[handle]
            ?: throw SafFailure(SafErrorCode.INVALID_ARGUMENT, "句柄不存在或已关闭：$handle")
        val maxBytes = call.argument<Int>("maxBytes") ?: MAX_CHUNK_BYTES
        if (maxBytes <= 0 || maxBytes > MAX_CHUNK_BYTES) {
            throw SafFailure(
                SafErrorCode.INVALID_ARGUMENT,
                "maxBytes 越界：$maxBytes（允许 1..$MAX_CHUNK_BYTES）",
            )
        }
        val chunk = stream.read(maxBytes)
        if (chunk == null) {
            handles.remove(handle)?.close()
        }
        return chunk
    }

    private fun closeRead(call: MethodCall): Any? {
        val handle = call.argument<String>("handle")
            ?: throw SafFailure(SafErrorCode.INVALID_ARGUMENT, "缺少 handle")
        // 重复关闭是幂等的：Dart 侧流结束时可能已自动回收。
        handles.remove(handle)?.close()
        return null
    }

    private fun exists(call: MethodCall): Boolean {
        val treeUri = requireTreeUri(call, "treeUri")
        val documentId = requireDocumentId(call, "documentId")
        return documents.exists(treeUri, documentId)
    }

    private fun canRead(call: MethodCall): Boolean {
        val treeUri = requireTreeUri(call, "treeUri")
        return documents.canRead(treeUri)
    }

    private fun closeAllHandles() {
        for (stream in handles.values) {
            stream.close()
        }
        handles.clear()
    }

    private fun requireTreeUri(call: MethodCall, key: String): Uri {
        val raw = call.argument<String>(key)
            ?: throw SafFailure(SafErrorCode.INVALID_ARGUMENT, "缺少参数：$key")
        if (raw.isEmpty() || !raw.startsWith("content://") || !raw.contains("/tree/")) {
            throw SafFailure(SafErrorCode.INVALID_ARGUMENT, "$key 不是 SAF 树 URI：$raw")
        }
        return Uri.parse(raw)
    }

    private fun requireDocumentId(call: MethodCall, key: String): String {
        val raw = call.argument<String>(key)
            ?: throw SafFailure(SafErrorCode.INVALID_ARGUMENT, "缺少参数：$key")
        if (raw.isEmpty()) {
            throw SafFailure(SafErrorCode.INVALID_ARGUMENT, "$key 不能为空")
        }
        return raw
    }

    private fun requireLimit(call: MethodCall, key: String): Int {
        val limit = call.argument<Int>(key)
            ?: throw SafFailure(SafErrorCode.INVALID_ARGUMENT, "缺少参数：$key")
        if (limit <= 0) {
            throw SafFailure(SafErrorCode.INVALID_ARGUMENT, "$key 必须为正：$limit")
        }
        return limit
    }
}
