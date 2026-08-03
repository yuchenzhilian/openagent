package com.openagent.openagent.automation

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * 前台服务（Foreground Service）—— 保活核心。
 *
 * Android 8+ 后台 App 容易被系统杀死，前台服务是最高优先级的保活手段。
 * 本服务创建了一个低优先级通知，用户几乎感知不到。
 *
 * 启动方式：am start-foreground-service -n com.openagent.openagent/.automation.OpenAgentForegroundService
 * 停止方式：am stopservice -n com.openagent.openagent/.automation.OpenAgentForegroundService
 */
class OpenAgentForegroundService : Service() {

    companion object {
        private const val TAG = "OpenAgentFG"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "openagent_keepalive"

        /** 是否正在运行。供保活工具检查。 */
        @Volatile
        var isRunning = false
            private set
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "ForegroundService onCreate")
        createNotificationChannel()
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "ForegroundService onStartCommand")
        // 如果服务被系统杀死，自动重启
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        Log.i(TAG, "ForegroundService onDestroy")
        isRunning = false
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "OpenAgent 保活",
                NotificationManager.IMPORTANCE_MIN, // 最低优先级，不弹窗、无声音
            ).apply {
                description = "用于保持 OpenAgent 后台运行"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("OpenAgent")
            .setContentText("正在运行")
            .setSmallIcon(android.R.drawable.ic_menu_compass) // 使用系统图标，无需自定义资源
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_MIN)
            .build()
    }
}