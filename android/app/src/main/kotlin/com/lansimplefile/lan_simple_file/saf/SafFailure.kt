// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file.saf

import java.io.FileNotFoundException
import java.io.IOException

/**
 * SAF 桥的错误码。Dart 侧 SafBridge 按 code 映射为 LanFileErrorCode。
 */
internal object SafErrorCode {
    const val INVALID_ARGUMENT = "invalidArgument"
    const val NOT_FOUND = "notFound"
    const val ACCESS_DENIED = "accessDenied"
    const val PROVIDER_OFFLINE = "providerOffline"
    const val UNSUPPORTED = "unsupported"
    const val IO = "io"
    const val INTERNAL = "internal"
}

/**
 * 桥内统一的失败载体：所有可预期失败都以它抛出，再由 handler 翻译成
 * PlatformException(code, message)。
 */
internal class SafFailure(val code: String, message: String, cause: Throwable? = null) :
    Exception(message, cause)

/**
 * 把任意异常收敛成 SafFailure，保证 Dart 侧永远拿到可判定的 code。
 *
 * 注意 FileNotFoundException 必须先于 IOException 判定（前者是后者的子类）。
 */
internal fun Throwable.toSafFailure(operation: String): SafFailure {
    if (this is SafFailure) {
        return this
    }
    return when (this) {
        is SecurityException -> SafFailure(
            SafErrorCode.ACCESS_DENIED,
            "SAF $operation 被拒绝：${message ?: this::class.java.simpleName}",
            this,
        )
        is FileNotFoundException -> SafFailure(
            SafErrorCode.NOT_FOUND,
            "SAF $operation 找不到文档：${message ?: "no message"}",
            this,
        )
        is IllegalArgumentException -> SafFailure(
            SafErrorCode.INVALID_ARGUMENT,
            "SAF $operation 参数非法：${message ?: "no message"}",
            this,
        )
        is UnsupportedOperationException -> SafFailure(
            SafErrorCode.UNSUPPORTED,
            "SAF $operation 不受该 provider 支持：${message ?: "no message"}",
            this,
        )
        is IOException -> SafFailure(
            SafErrorCode.IO,
            "SAF $operation IO 失败：${message ?: this::class.java.simpleName}",
            this,
        )
        else -> SafFailure(
            SafErrorCode.INTERNAL,
            "SAF $operation 内部错误：${this::class.java.simpleName}: ${message ?: "no message"}",
            this,
        )
    }
}
