// SPDX-License-Identifier: GPL-3.0-only
package com.lansimplefile.lan_simple_file.service

import android.content.Context
import android.net.wifi.WifiManager
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 组播锁的会话级持有者。
 *
 * Activity 可见期间用于发现与 mDNS；后台共享服务独立持有自己的锁。
 * 调用方在各自生命周期结束时 release，避免空闲时持续接收组播。
 *
 * 用 AtomicBoolean 保证 acquire/release 幂等：重复 acquire 不叠加引用计数，
 * 重复 release 也不会把别人的锁释放掉。
 */
internal class MulticastLockHolder(private val context: Context) {

    private val held = AtomicBoolean(false)

    private var lock: WifiManager.MulticastLock? = null

    /** 当前是否持有组播锁。 */
    val isHeld: Boolean
        get() = held.get()

    /**
     * 按需持有或释放；返回操作后是否持有。
     *
     * 获取 WiFi 服务失败（极少数机型在 WiFi 关闭时会抛）当作「拿不到锁」，
     * 返回 false 而不是让调用方崩——共享本身仍然可用，只是收不到组播。
     */
    fun sync(shouldHold: Boolean): Boolean {
        if (shouldHold) {
            return acquire()
        }
        release()
        return false
    }

    private fun acquire(): Boolean {
        if (held.get()) {
            return true
        }
        val manager = context.applicationContext
            .getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return false
        return try {
            val next = manager.createMulticastLock(LOCK_TAG).apply {
                setReferenceCounted(false)
            }
            next.acquire()
            lock = next
            held.set(true)
            true
        } catch (error: SecurityException) {
            false
        } catch (error: UnsupportedOperationException) {
            false
        }
    }

    private fun release() {
        if (!held.getAndSet(false)) {
            return
        }
        val current = lock
        lock = null
        try {
            current?.release()
        } catch (error: RuntimeException) {
            // 锁已失效（WiFi 被关闭）时部分 ROM 会抛，忽略即可。
        }
    }

    companion object {
        private const val LOCK_TAG = "lan-simple-file-multicast"
    }
}
