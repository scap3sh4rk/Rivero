package dev.scap3sh4rk.rivero

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rivero/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> {
                        val me = ComponentName(this, RiveroNotificationListener::class.java).flattenToString()
                        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                        result.success(enabled?.contains(me) == true)
                    }
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
                    else -> result.notImplemented()
                }
            }
    }
}
