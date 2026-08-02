package com.openagent.openagent.automation

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Optional notification listener (L1.5). User must grant access via
 * Settings → Notification access → OpenAgent.
 *
 * When enabled, [android_get_notifications] in AutomationChannel can serve
 * real notifications from this cache instead of shell dumpsys fallbacks.
 * When disabled the manifest keeps it registered but it is never started;
 * the Dart layer falls back to dumpsys gracefully.
 *
 * NOTE: 不做任何业务判断，只是把当前活动通知缓存最近 N 条。分析/归纳全给 VLM+LLM。
 */
class OpenAgentNotificationListener : NotificationListenerService() {

    companion object {
        private val connected = AtomicBoolean(false)
        // Ring buffer: keep up to ~200 active notifications with snapshots
        private val recent = ConcurrentLinkedQueue<NotificationSnapshot>()
        private const val MAX_RECENT = 200

        fun isListenerConnected(): Boolean = connected.get()

        fun dumpRecent(limit: Int): List<NotificationSnapshot> {
            val list = recent.toList()
            val take = limit.coerceAtMost(list.size).coerceAtLeast(0)
            // newest first
            return list.takeLast(take).reversed()
        }
    }

    data class NotificationSnapshot(
        val pkg: String,
        val tag: String?,
        val id: Int,
        val whenMs: Long,
        val title: String,
        val text: String,
        val ongoing: Boolean,
        val clearable: Boolean,
        val channelId: String?,
        val removed: Boolean,
    ) {
        fun renderLine(i: Int): String = buildString {
            append("[$i] pkg=$pkg  time=${android.text.format.DateFormat.format("MM-dd HH:mm:ss", whenMs)}")
            if (tag != null) append("  tag=$tag")
            append("  id=$id")
            appendLine()
            if (title.isNotBlank()) appendLine("    title: $title")
            if (text.isNotBlank()) appendLine("    text:  $text")
            appendLine("    ongoing=$ongoing  clearable=$clearable  channel=${channelId ?: ""}  removed=$removed")
        }
    }

    override fun onListenerConnected() {
        connected.set(true)
        runCatching {
            // Take a snapshot of currently active posts at the moment we're bound.
            val act = runCatching { activeNotifications }.getOrNull().orEmpty()
            for (sbn in act) remember(sbn, removed = false)
        }
    }

    override fun onListenerDisconnected() {
        connected.set(false)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn != null) remember(sbn, removed = false)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        if (sbn != null) remember(sbn, removed = true)
    }

    private fun remember(sbn: StatusBarNotification, removed: Boolean) {
        val n = sbn.notification
        val extras: android.os.Bundle? = n.extras
        val title = extras?.getCharSequence(android.app.Notification.EXTRA_TITLE)
            ?: extras?.get(android.app.Notification.EXTRA_TITLE_BIG)
            ?: ""
        val text = extras?.getCharSequence(android.app.Notification.EXTRA_TEXT)
            ?: extras?.getCharSequence("android.textLines")
                ?.let { if (it is Array<*>) it.joinToString("\n") else it.toString() }
            ?: ""
        val snap = NotificationSnapshot(
            pkg = sbn.packageName,
            tag = sbn.tag,
            id = sbn.id,
            whenMs = sbn.postTime,
            title = title.toString(),
            text = text.toString(),
            ongoing = n.flags and android.app.Notification.FLAG_ONGOING_EVENT != 0,
            clearable = sbn.isClearable,
            channelId = n.channelId,
            removed = removed,
        )
        recent.add(snap)
        while (recent.size > MAX_RECENT) recent.poll()
    }
}
