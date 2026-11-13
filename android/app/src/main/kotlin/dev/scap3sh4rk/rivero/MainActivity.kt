package dev.scap3sh4rk.rivero

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rivero/notifications")
        channel = ch
        RiveroNotificationListener.onQueued = { ch.invokeMethod("queued", null) }
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(listenerEnabled())
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "drain" -> synchronized(RiveroNotificationListener.LOCK) {
                    val prefs = getSharedPreferences(RiveroNotificationListener.PREFS, Context.MODE_PRIVATE)
                    val json = prefs.getString(RiveroNotificationListener.KEY, "[]")
                    prefs.edit().remove(RiveroNotificationListener.KEY).apply()
                    result.success(json)
                }
                "postTest" -> result.success(
                    postTestNotification(
                        call.argument<String>("title") ?: "Bank",
                        call.argument<String>("body") ?: "",
                    ),
                )
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        RiveroNotificationListener.onQueued = null
        channel = null
        super.onDestroy()
    }

    private fun listenerEnabled(): Boolean {
        val me = ComponentName(this, RiveroNotificationListener::class.java).flattenToString()
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return enabled?.contains(me) == true
    }

    /** Posts a bank-style notification that the listener will capture.
     *  Returns "posted", "no_access" or "no_permission". */
    private fun postTestNotification(title: String, body: String): String {
        if (!listenerEnabled()) return "no_access"
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
            return "no_permission"
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "rivero_test"
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(channelId, "Capture test", NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
        val extras = Bundle().apply { putBoolean(RiveroNotificationListener.EXTRA_TEST, true) }
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId) else Notification.Builder(this)
        val notification = builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .addExtras(extras)
            .build()
        manager.notify((System.currentTimeMillis() % 100000).toInt(), notification)
        return "posted"
    }
}
