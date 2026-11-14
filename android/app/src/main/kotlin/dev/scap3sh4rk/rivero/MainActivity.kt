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
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FragmentActivity is required by the biometric prompt (local_auth).
class MainActivity : FlutterFragmentActivity() {
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
                    val json = CaptureQueue.read(this).toString()
                    CaptureQueue.clear(this)
                    result.success(json)
                }
                // The UPI app the user pays with most: its notifications are always read.
                "setPrimaryApp" -> {
                    RiveroNotificationListener.setPrimaryApp(this, call.argument<String>("package"))
                    result.success(null)
                }
                "diagnostics" -> result.success(Diagnostics.read(this))
                // UPI apps installed on this phone: apps that can open upi://pay.
                "upiApps" -> result.success(installedUpiApps())
                // "Delete all data": nothing captured may survive it.
                "clearQueue" -> synchronized(RiveroNotificationListener.LOCK) {
                    CaptureQueue.clear(this)
                    Diagnostics.clear(this)
                    result.success(null)
                }
                // Blocks screenshots and blanks the recent-apps preview.
                "setSecure" -> {
                    val on = call.argument<Boolean>("on") == true
                    if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
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

    /** UPI and wallet apps commonly used in India: found by package even when they
     *  do not answer a plain upi://pay request. */
    private val knownUpiPackages = listOf(
        "com.google.android.apps.nbu.paisa.user",
        "com.phonepe.app",
        "net.one97.paytm",
        "in.org.npci.upiapp",
        "com.dreamplug.androidapp",
        "in.amazon.mShop.android.shopping",
        "com.sbi.lotusintouch",
        "com.sbi.SBIFreedomPlus",
        "indwin.c3.shareapp",
        "com.samsung.android.spay",
        "com.samsung.android.spaylite",
        "com.csam.icici.bank.imobile",
        "com.snapwork.hdfc",
        "com.enstage.wibmo.hdfc",
        "com.axis.mobile",
        "com.msf.kopl",
        "com.naviapp",
        "com.mobikwik_new",
        "com.freecharge.android",
        "com.epifi.paisa",
        "money.jupiter",
        "com.myairtelapp",
        "com.google.android.apps.walletnfcrel",
    )

    /** [{package, label}] for every installed UPI-capable app: apps that can open
     *  upi://pay, plus well-known UPI and wallet apps that are installed. */
    private fun installedUpiApps(): List<Map<String, String>> {
        val found = linkedMapOf<String, String>()
        val probe = Intent(Intent.ACTION_VIEW, android.net.Uri.parse("upi://pay?pa=test@upi&pn=Test&cu=INR"))
        val infos = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.queryIntentActivities(
                probe,
                PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_ALL.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(probe, PackageManager.MATCH_ALL)
        }
        for (info in infos) {
            found[info.activityInfo.packageName] = info.loadLabel(packageManager).toString()
        }
        for (pkg in knownUpiPackages) {
            if (found.containsKey(pkg)) continue
            try {
                val app = packageManager.getApplicationInfo(pkg, 0)
                found[pkg] = packageManager.getApplicationLabel(app).toString()
            } catch (_: PackageManager.NameNotFoundException) {
                // not installed
            }
        }
        return found
            .filterKeys { it != packageName }
            .map { mapOf("package" to it.key, "label" to it.value) }
            .sortedBy { (it["label"] ?: "").lowercase() }
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
