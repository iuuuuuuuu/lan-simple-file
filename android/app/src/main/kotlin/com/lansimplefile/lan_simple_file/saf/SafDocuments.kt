// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file.saf

import android.content.ContentResolver
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import java.io.FileInputStream
import java.io.FileNotFoundException

/**
 * 一条 SAF 目录项的投影。size / lastModified 允许未知（部分 provider 不返回）。
 */
internal data class SafItem(
    val documentId: String,
    val name: String,
    val isDirectory: Boolean,
    val size: Long?,
    val lastModified: Long?,
    val mime: String?,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "documentId" to documentId,
        "name" to name,
        "isDirectory" to isDirectory,
        "size" to size,
        "lastModified" to lastModified,
        "mime" to mime,
    )
}

/**
 * 直接基于 ContentResolver + DocumentsContract 的 SAF 操作集合。
 *
 * 单次遍历的条目上限：超过后放弃扫描并抛 unsupported，
 * 避免超大目录把内存吃光（计划 50 万项上限，见 docs/plan.md 第 3.1 节）。
 */
internal class SafDocuments(private val context: Context, private val resolver: ContentResolver) {

    companion object {
        private const val MAX_SCAN_ITEMS = 200_000

        private val LIST_PROJECTION = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )

        private val STAT_PROJECTION = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )

    }

    /**
     * 列出 [parentDocumentId] 下的一页子项。
     *
     * Directories precede files, then documentId orders each kind. The cursor
     * retains its kind so deletion between pages cannot change the boundary.
     */
    fun listChildren(
        treeUri: Uri,
        parentDocumentId: String,
        cursor: String?,
        limit: Int,
        cursorIsDirectory: Boolean = false,
    ): List<SafItem> {
        if (limit <= 0) {
            throw SafFailure(SafErrorCode.INVALID_ARGUMENT, "limit 必须为正：$limit")
        }
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocumentId)
        // Keep only the first limit entries, including their directory rank.
        val kept = java.util.PriorityQueue<SafItem>(
            limit,
            safListingOrder.reversed(),
        )
        var scanned = 0
        resolver.query(childrenUri, LIST_PROJECTION, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                scanned++
                if (scanned > MAX_SCAN_ITEMS) {
                    throw SafFailure(
                        SafErrorCode.UNSUPPORTED,
                        "目录项超过 $MAX_SCAN_ITEMS，请改用索引缓存后再分页：$parentDocumentId",
                    )
                }
                val item = readItem(c) ?: continue
                if (cursor != null && !isAfterSafCursor(item, cursor, cursorIsDirectory)) {
                    continue
                }
                kept.add(item)
                if (kept.size > limit) {
                    kept.poll()
                }
            }
        } ?: throw SafFailure(SafErrorCode.PROVIDER_OFFLINE, "子项查询返回空游标：$parentDocumentId")

        return kept.sortedWith(safListingOrder)
    }

    /**
     * 读取单条文档属性。
     *
     * 存在性、类型、名称走 DocumentFile（它对 provider 差异做了归一）；
     * size / lastModified 仍取 DocumentsContract 的原始列，因为 DocumentFile.length()
     * 在未知时返回 0，会把「未知」和「零字节」混为一谈。
     */
    fun statItem(treeUri: Uri, documentId: String): SafItem {
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
        val document = DocumentFile.fromSingleUri(context, documentUri)
            ?: throw SafFailure(SafErrorCode.NOT_FOUND, "无法构造文档句柄：$documentId")
        if (!document.exists()) {
            throw SafFailure(SafErrorCode.NOT_FOUND, "文档不存在：$documentId")
        }

        var size: Long? = null
        var lastModified: Long? = null
        try {
            resolver.query(documentUri, STAT_PROJECTION, null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    size = columnLongOrNull(c, DocumentsContract.Document.COLUMN_SIZE)
                    lastModified = columnLongOrNull(c, DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                }
            }
        } catch (_: SecurityException) {
            // provider 拒答列查询时仍返回 DocumentFile 能给出的部分，size/mtime 保持未知。
        }

        return SafItem(
            documentId = documentId,
            name = document.name ?: documentId.substringAfterLast('/').substringAfterLast(':'),
            isDirectory = document.isDirectory,
            size = if (document.isDirectory) null else size,
            lastModified = lastModified,
            mime = document.type,
        )
    }

    /** 源是否仍可访问；权限撤回与文档消失都算 false，不抛异常。 */
    fun exists(treeUri: Uri, documentId: String): Boolean {
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
        return try {
            DocumentFile.fromSingleUri(context, documentUri)?.exists() ?: false
        } catch (_: SecurityException) {
            false
        } catch (_: FileNotFoundException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    /**
     * 树 URI 的读权限是否仍在。
     *
     * 两道判定：先看 persistedUriPermissions 里有没有这条授权（重启后仍有效的那种），
     * 再实际查一次子项确认 provider 侧没撤权。
     */
    fun canRead(treeUri: Uri): Boolean {
        if (!DocumentsContract.isTreeUri(treeUri)) {
            throw SafFailure(SafErrorCode.INVALID_ARGUMENT, "不是树 URI：$treeUri")
        }
        val persisted = context.contentResolver.persistedUriPermissions
        val granted = persisted.any { permission ->
            permission.isReadPermission && permission.uri == treeUri
        }
        if (!granted) {
            return false
        }
        return try {
            val rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, rootDocumentId)
            resolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
                null,
                null,
                null,
            )?.use { true } ?: false
        } catch (_: SecurityException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    /**
     * 打开 [start, endExclusive) 的底层句柄。
     *
     * 定位优先用 FileChannel.position（普通文件可随机定位）；
     * 管道类 provider 不支持定位时退化为 skip 循环。
     */
    fun openStream(treeUri: Uri, documentId: String, start: Long, endExclusive: Long?): OpenStream {
        if (start < 0) {
            throw SafFailure(SafErrorCode.INVALID_ARGUMENT, "start 不能为负：$start")
        }
        if (endExclusive != null && endExclusive < start) {
            throw SafFailure(
                SafErrorCode.INVALID_ARGUMENT,
                "endExclusive($endExclusive) < start($start)",
            )
        }
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
        val pfd: ParcelFileDescriptor = try {
            resolver.openFileDescriptor(documentUri, "r")
        } catch (e: FileNotFoundException) {
            throw SafFailure(SafErrorCode.NOT_FOUND, "打不开文档：$documentId", e)
        } ?: throw SafFailure(SafErrorCode.NOT_FOUND, "provider 返回空描述符：$documentId")

        val stream = FileInputStream(pfd.fileDescriptor)
        try {
            seekTo(stream, start)
        } catch (e: Throwable) {
            runCatching { stream.close() }
            runCatching { pfd.close() }
            throw e.toSafFailure("openRead")
        }
        return OpenStream(pfd, stream, start, endExclusive)
    }

    /** 定位到 [target]：先试 FileChannel，失败退化为 skip 循环。 */
    private fun seekTo(stream: FileInputStream, target: Long) {
        if (target == 0L) {
            return
        }
        val positioned = runCatching { stream.channel.position(target) }.isSuccess
        if (positioned) {
            return
        }
        var remaining = target
        while (remaining > 0) {
            val skipped = stream.skip(remaining)
            if (skipped <= 0) {
                // 有的 provider 不支持 skip，只能靠读丢弃；读到 EOF 说明越界。
                if (stream.read() < 0) {
                    throw SafFailure(
                        SafErrorCode.INVALID_ARGUMENT,
                        "start($target) 超出文件长度",
                    )
                }
                remaining -= 1
            } else {
                remaining -= skipped
            }
        }
    }

    private fun columnLongOrNull(cursor: Cursor, column: String): Long? {
        val index = cursor.getColumnIndex(column)
        return if (index >= 0 && !cursor.isNull(index)) cursor.getLong(index) else null
    }

    private fun readItem(cursor: Cursor): SafItem? {
        val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
        val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        val mimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
        val sizeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
        val modifiedIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
        if (idIndex < 0 || cursor.isNull(idIndex)) {
            return null
        }
        val documentId = cursor.getString(idIndex) ?: return null
        val name = if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
            cursor.getString(nameIndex)
        } else {
            null
        } ?: documentId.substringAfterLast('/').substringAfterLast(':')
        val mime = if (mimeIndex >= 0 && !cursor.isNull(mimeIndex)) {
            cursor.getString(mimeIndex)
        } else {
            null
        }
        return SafItem(
            documentId = documentId,
            name = name,
            isDirectory = mime == DocumentsContract.Document.MIME_TYPE_DIR,
            size = if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) cursor.getLong(sizeIndex) else null,
            lastModified = if (modifiedIndex >= 0 && !cursor.isNull(modifiedIndex)) {
                cursor.getLong(modifiedIndex)
            } else {
                null
            },
            mime = mime,
        )
    }
}

/**
 * 一个已定位的读取句柄。读取量受 endExclusive 约束，越界即 EOF。
 */
internal class OpenStream(
    private val pfd: ParcelFileDescriptor,
    private val stream: FileInputStream,
    private val start: Long,
    private val endExclusive: Long?,
) {
    private var position: Long = start
    private var closed: Boolean = false

    /** 读取至多 [maxBytes]；到达 endExclusive 或文件尾返回 null。 */
    fun read(maxBytes: Int): ByteArray? {
        if (closed) {
            throw SafFailure(SafErrorCode.INVALID_ARGUMENT, "句柄已关闭")
        }
        if (maxBytes <= 0) {
            throw SafFailure(SafErrorCode.INVALID_ARGUMENT, "maxBytes 必须为正：$maxBytes")
        }
        var want = maxBytes.toLong()
        val end = endExclusive
        if (end != null) {
            val left = end - position
            if (left <= 0) {
                return null
            }
            if (left < want) {
                want = left
            }
        }
        val buffer = ByteArray(want.toInt())
        var filled = 0
        while (filled < buffer.size) {
            val read = stream.read(buffer, filled, buffer.size - filled)
            if (read < 0) {
                break
            }
            filled += read
        }
        if (filled == 0) {
            return null
        }
        position += filled
        return if (filled == buffer.size) buffer else buffer.copyOf(filled)
    }

    fun close() {
        if (closed) {
            return
        }
        closed = true
        runCatching { stream.close() }
        runCatching { pfd.close() }
    }
}
