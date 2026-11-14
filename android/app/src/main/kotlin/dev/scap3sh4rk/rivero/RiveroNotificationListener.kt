package dev.scap3sh4rk.rivero

import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

/**
 * Captures bank / UPI / SMS-app notifications and queues them in SharedPreferences.
 * No Flutter engine needed here: Dart drains the queue when the app opens (see MainActivity).
 * No READ_SMS: only notifications the user has granted listener access to.
 */
class RiveroNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val extras = sbn.notification.extras
        // Rivero's own "test capture" notification exercises this exact path.
        val isTest = sbn.packageName == packageName && extras.getBoolean(EXTRA_TEST, false)
        if (!isTest && !isFinancialSource(sbn.packageName)) return
        val title = extras.getCharSequence("android.title")?.toString()
        val body = (extras.getCharSequence("android.bigText")
            ?: extras.getCharSequence("android.text"))?.toString() ?: return
        if (!MONEY.containsMatchIn(body)) return // ignore chats, OTP-only etc.

        synchronized(LOCK) {
            val queue = CaptureQueue.read(this)
            queue.put(JSONObject().apply {
                put("id", "${sbn.packageName}:${sbn.key}:${sbn.postTime}")
                put("package", sbn.packageName)
                put("title", title)
                put("body", body)
                put("time", sbn.postTime)
            })
            // Encrypted, and capped so a never-opened app can't grow it.
            CaptureQueue.write(this, queue)
        }
        // If the app is open, tell it to process the queue now.
        Handler(Looper.getMainLooper()).post { onQueued?.invoke() }
    }

    companion object {
        const val EXTRA_TEST = "rivero_test"

        /** Set by MainActivity while the Flutter UI is alive. */
        @Volatile
        var onQueued: (() -> Unit)? = null

        val LOCK = Any()
        private val MONEY = Regex("(?i)(rs\\.?|inr|₹)\\s?\\d|debited|credited|spent|mandate|autopay")
        // SMS apps + major UPI/bank apps; extend as needed.
        private val SOURCES = setOf(
            "com.google.android.apps.messaging", "com.samsung.android.messaging", "com.android.mms",
            "com.google.android.apps.nbu.paisa.user", "com.phonepe.app", "net.one97.paytm",
            "com.snapwork.hdfc", "com.csam.icici.bank.imobile", "com.sbi.SBIFreedomPlus",
            "com.axis.mobile", "com.dreamplug.androidapp", "in.org.npci.upiapp",
        )
        fun isFinancialSource(pkg: String) = pkg in SOURCES
    }
}
