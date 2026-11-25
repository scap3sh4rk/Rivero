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
    override fun onListenerConnected() {
        super.onListenerConnected()
        Diagnostics.listener(this, true)
    }

    // Android dropped the connection (it can after an app update, or under
    // memory pressure): ask for it back instead of going deaf until reboot.
    override fun onListenerDisconnected() {
        Diagnostics.listener(this, false)
        if (android.os.Build.VERSION.SDK_INT >= 24) {
            requestRebind(android.content.ComponentName(this, RiveroNotificationListener::class.java))
        }
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val extras = sbn.notification.extras
        // Rivero's own "test capture" notification exercises this exact path.
        val isTest = sbn.packageName == packageName && extras.getBoolean(EXTRA_TEST, false)
        if (!isTest && (sbn.packageName == packageName || isPrivate(sbn.packageName))) return
        val known = isTest || isFinancialSource(this, sbn.packageName)
        val title = extras.getCharSequence("android.title")?.toString()
        // A conversation (SMS apps): Android folds several quick messages
        // into one notification and its text shows only the latest, so each
        // message in it is taken, once.
        val messages = if (isTest) null else conversation(sbn)
        if (messages != null) {
            for (m in messages) {
                capture(sbn, known, isTest, m.sender ?: title, m.text, m.time, "${sbn.packageName}:${sbn.key}:${m.time}")
            }
            return
        }
        val body = (extras.getCharSequence("android.bigText")
            ?: extras.getCharSequence("android.text"))?.toString()
        capture(sbn, known, isTest, title, body, sbn.postTime, "${sbn.packageName}:${sbn.key}:${sbn.postTime}")
    }

    private class Message(val sender: String?, val text: String?, val time: Long)

    /** The messages of a conversation notification not taken before, or
     *  null when it is not a conversation. */
    private fun conversation(sbn: StatusBarNotification): List<Message>? {
        @Suppress("DEPRECATION")
        val raw = sbn.notification.extras.getParcelableArray("android.messages") ?: return null
        val all = raw.mapNotNull { p ->
            val b = p as? android.os.Bundle ?: return@mapNotNull null
            @Suppress("DEPRECATION")
            val person = if (android.os.Build.VERSION.SDK_INT >= 28) {
                (b.getParcelable("sender_person") as? android.app.Person)?.name?.toString()
            } else {
                null
            }
            Message(b.getCharSequence("sender")?.toString() ?: person, b.getCharSequence("text")?.toString(), b.getLong("time"))
        }
        if (all.isEmpty()) return null
        // Older messages still in the conversation were seen when they came
        // (or are history from before Rivero listened): only recent ones.
        val since = sbn.postTime - RECENT_MS
        return synchronized(LOCK) {
            all.filter { it.time >= since && Seen.add(this, "${sbn.packageName}:${sbn.key}:${it.time}") }
        }
    }

    private fun capture(
        sbn: StatusBarNotification,
        known: Boolean,
        isTest: Boolean,
        title: String?,
        body: String?,
        time: Long,
        captureId: String,
    ) {
        // Titles often carry the amount in payment apps ("Paid ₹500 to X").
        val searchable = "${title ?: ""} ${body ?: ""}"
        // Android 15+ hides messages it thinks are sensitive (bank SMS among
        // them) from apps like Rivero: only a fixed "content hidden" text
        // arrives. From a bank or payment app it is still a payment that
        // happened, so it waits under "bank messages to check" to be added.
        val hidden = known && body != null && isHiddenByAndroid(body)
        // Any other app (a bank's own app, a wallet, a card app Rivero does
        // not list): kept only when it reads like a real transaction, and
        // nothing about it is recorded otherwise.
        if (!known && (body == null || !looksLikeTransaction(searchable))) return
        if (body == null || (!hidden && !MONEY.containsMatchIn(searchable))) {
            // Seen from an allowed app but not about money (chat, OTP-only,
            // or text the phone hid): counted so the user can see it.
            Diagnostics.note(this, sbn.packageName, if (body.isNullOrBlank()) "no text" else "no money")
            return
        }
        Diagnostics.note(this, sbn.packageName, if (hidden) "hidden" else "queued")

        synchronized(LOCK) {
            val queue = CaptureQueue.read(this)
            queue.put(JSONObject().apply {
                put("id", captureId)
                put("package", sbn.packageName)
                put("title", title)
                put("body", body)
                put("time", time)
            })
            // Encrypted, and capped so a never-opened app can't grow it.
            CaptureQueue.write(this, queue)
        }
        // If the app is open, tell it to process the queue now.
        Handler(Looper.getMainLooper()).post { onQueued?.invoke() }
        // A notification to add it in two taps, when Rivero is not on screen.
        // The capture test always gets one (it is sent from inside Rivero),
        // replacing the fake bank alert, so the whole flow can be tried.
        if (isTest) {
            cancelNotification(sbn.key)
            CaptureNotifier.notify(this, captureId, title, body, force = true)
        } else if (!MainActivity.isForeground) {
            // From an app Rivero does not list, a pop-up only when the text
            // names an account, card, UPI ID or reference (not a shop's
            // "order paid" update); it still waits in To review either way.
            if (known || ACCOUNTISH.containsMatchIn(searchable)) {
                CaptureNotifier.notify(this, captureId, title, body)
            } else {
                Diagnostics.popup(this, "other app")
            }
        } else {
            // Rivero is on screen: the payment shows in To review instead.
            Diagnostics.popup(this, "rivero open")
        }
    }

    /** Android's own "Sensitive notification content hidden" (in the
     *  phone's language), which replaces a hidden notification's text. */
    private fun isHiddenByAndroid(body: String): Boolean {
        val id = resources.getIdentifier("redacted_notification_message", "string", "android")
        val placeholder = if (id != 0) android.content.res.Resources.getSystem().getString(id) else REDACTED_EN
        return body.trim() == placeholder.trim() || body.trim() == REDACTED_EN
    }

    companion object {
        const val EXTRA_TEST = "rivero_test"
        private const val REDACTED_EN = "Sensitive notification content hidden"
        /** Messages in a conversation older than this are not new. */
        private const val RECENT_MS = 2 * 60 * 60 * 1000L

        /** Set by MainActivity while the Flutter UI is alive. */
        @Volatile
        var onQueued: (() -> Unit)? = null

        val LOCK = Any()

        /** Asks Android to (re)connect the listener when access is on. Cheap,
         *  and harmless when it is already connected. */
        fun reconnect(context: android.content.Context) {
            if (android.os.Build.VERSION.SDK_INT < 24) return
            val me = android.content.ComponentName(context, RiveroNotificationListener::class.java)
            val enabled = android.provider.Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            )
            if (enabled?.contains(me.flattenToString()) == true) {
                try {
                    requestRebind(me)
                } catch (_: Exception) {
                    // Not allowed right now; the next start tries again.
                }
            }
        }
        /** Chats, social and email: never read, whatever they say. */
        private val PRIVATE = setOf(
            "com.whatsapp", "com.whatsapp.w4b", "org.telegram.messenger",
            "org.thoughtcrime.securesms", "com.instagram.android",
            "com.facebook.orca", "com.facebook.katana", "com.snapchat.android",
            "com.discord", "com.Slack", "com.google.android.gm",
            "com.microsoft.office.outlook", "com.twitter.android",
            "com.linkedin.android", "com.google.android.apps.dynamite",
            "com.microsoft.teams", "us.zoom.videomeetings", "jp.naver.line.android",
            "com.viber.voip", "com.skype.raider", "com.google.android.apps.tachyon",
        )

        private fun isPrivate(pkg: String) =
            pkg in PRIVATE || pkg == "android" || pkg.startsWith("com.android.systemui")

        /** An amount and a transaction word ("₹500 debited", "paid Rs 200"). */
        private val TXN_WORD = Regex(
            "(?i)\\b(debited|credited|paid|sent|received|spent|withdrawn|transferred|deducted|charged)\\b",
        )
        private val AMOUNT = Regex("(?i)(rs\\.?|inr|₹)\\s?\\d")
        private val OFFER = Regex(
            "(?i)\\b(cashback offer|get (up ?to )?(rs\\.?|inr|₹)|win (up ?to )?|coupon|voucher|apply now|offer)\\b",
        )

        /** Bank shorthand: "Dr Rs25.00" / "Cr Rs500". */
        private val DR_CR = Regex("(?i)\\b(dr|cr)\\.?\\s*(rs\\.?|inr|₹)\\s*\\d")

        fun looksLikeTransaction(text: String) =
            AMOUNT.containsMatchIn(text) &&
                (TXN_WORD.containsMatchIn(text) || DR_CR.containsMatchIn(text)) &&
                !OFFER.containsMatchIn(text)

        /** Names where the money moved: an account, card, UPI ID or reference. */
        private val ACCOUNTISH = Regex(
            "(?i)\\b(a/?c|acct|account|card|upi|vpa|ref|utr|imps|neft)\\b|@[a-z]{2,}",
        )

        private val MONEY = Regex("(?i)(rs\\.?|inr|₹)\\s?\\d|debited|credited|spent|mandate|autopay")
        // SMS apps + major UPI/bank apps; extend as needed.
        private val SOURCES = setOf(
            "com.google.android.apps.messaging", "com.samsung.android.messaging", "com.android.mms",
            "com.google.android.apps.nbu.paisa.user", "com.phonepe.app", "net.one97.paytm",
            "com.snapwork.hdfc", "com.csam.icici.bank.imobile", "com.sbi.SBIFreedomPlus",
            "com.axis.mobile", "com.dreamplug.androidapp", "in.org.npci.upiapp",
            "in.amazon.mShop.android.shopping", "com.sbi.lotusintouch", "com.naviapp",
            "com.mobikwik_new", "com.freecharge.android", "com.msf.kopl",
            // Other SMS apps, and banks that only notify from their own app.
            "com.truecaller", "com.microsoft.android.smsorganizer",
            "indwin.c3.shareapp", "money.jupiter", "com.epifi.paisa",
            "com.idfcfirstbank.optimus",
        )
        private const val CONFIG = "rivero_capture_config"
        private const val PRIMARY = "primary_upi_package"

        /** The UPI app the user chose as their main one (any app, even one not listed above). */
        fun primaryApp(context: android.content.Context): String? =
            context.getSharedPreferences(CONFIG, android.content.Context.MODE_PRIVATE)
                .getString(PRIMARY, null)?.takeIf { it.isNotBlank() }

        fun setPrimaryApp(context: android.content.Context, pkg: String?) {
            context.getSharedPreferences(CONFIG, android.content.Context.MODE_PRIVATE).edit()
                .putString(PRIMARY, pkg ?: "").apply()
        }

        fun isFinancialSource(context: android.content.Context, pkg: String) =
            pkg in SOURCES || pkg == primaryApp(context)
    }
}
