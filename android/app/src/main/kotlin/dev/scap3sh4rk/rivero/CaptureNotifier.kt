package dev.scap3sh4rk.rivero

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/**
 * A phone notification for each payment Rivero captures, so it can be added
 * the moment it happens: tapping it opens a small "add" popup (category and an
 * optional note) without opening the app; "Open Rivero" opens the app on it.
 * The choice is stored here and applied when the app next processes captures.
 */
object CaptureNotifier {
    private const val CHANNEL = "rivero_captures"
    private const val PREFS = "rivero_capture_ui"
    private const val KEY_DECISIONS = "decisions"
    private const val KEY_CATEGORIES = "categories"
    private const val KEY_OPEN = "open_request"
    private const val KEY_ACCOUNTS = "accounts"
    private const val KEY_TAB = "open_tab"

    const val EXTRA_ID = "capture_id"
    const val EXTRA_TITLE = "capture_title"
    const val EXTRA_TEXT = "capture_text"
    const val EXTRA_INCOMING = "capture_incoming"

    private val AMOUNT = Regex(
        "(?i)(?:rs\\.?|inr|₹)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)" +
            "|(?:debited|credited|paid|sent|received)\\s+(?:by|for|with|of)?\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)",
    )
    /** Offers, not payments ("Get Rs 500 cashback", "Win up to ₹1000"). */
    private val PROMOTION = Regex(
        "(?i)\\b(cashback offer|get (up ?to )?(rs\\.?|inr|₹)|win (up ?to )?|up ?to (rs\\.?|inr|₹)|" +
            "coupon|voucher|pre[\\s-]?approved|apply now|eligible for|offer ends|limited time)",
    )
    private val NOT_A_PAYMENT = Regex(
        "(?i)\\b(otp|one[\\s-]?time password|verification code|will be debited|to be debited|" +
            "pre[\\s-]?debit|statement (is )?(generated|ready)|minimum (amount )?due|total (amount )?due)\\b",
    )
    private val INCOME = Regex("(?i)\\b(credited|received|deposited|refund)")
    private val DEBIT = Regex("(?i)\\bdebited|\\bpaid|\\bsent|\\bspent|\\bwithdrawn|\\btransferred|\\bpurchase")

    /** Amount -> when a popup was last shown for it. */
    private val recent = HashMap<String, Long>()
    private const val SAME_PAYMENT_MS = 3 * 60 * 1000L

    fun notificationId(captureId: String) = captureId.hashCode() and 0x7fffffff

    /** Posts the notification for a newly captured message, if it looks like a payment. */
    fun notify(context: Context, captureId: String, title: String?, body: String, force: Boolean = false) {
        val text = listOfNotNull(title, body).joinToString(" · ")
        if (NOT_A_PAYMENT.containsMatchIn(text)) {
            Diagnostics.popup(context, "not a payment")
            return
        }
        // An offer mentions money but nothing moved: no popup (the message
        // is still kept for the app to judge). Payments are worded every
        // which way ("Payment of ₹500 to X successful", "₹500 to X"), so a
        // pop-up never waits for a particular verb.
        if (!force && PROMOTION.containsMatchIn(text) &&
            !DEBIT.containsMatchIn(text) && !INCOME.containsMatchIn(text)
        ) {
            Diagnostics.popup(context, "offer")
            return
        }
        // One payment is announced by the payment app and again by the
        // bank: one popup, not two. The app pairs the two messages itself.
        val seen = AMOUNT.find(text)?.let { it.groupValues[1].ifEmpty { it.groupValues[2] } }
            ?.replace(",", "")?.removeSuffix(".00")?.removeSuffix(".0")
        if (!force && seen != null) {
            val now = System.currentTimeMillis()
            synchronized(recent) {
                recent.values.removeAll { now - it > SAME_PAYMENT_MS }
                if (recent.containsKey(seen)) {
                    Diagnostics.popup(context, "same payment")
                    return
                }
                recent[seen] = now
            }
        }
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            Diagnostics.popup(context, "no permission")
            return
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Payments to add", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "A payment was captured: add it in two taps"
                },
            )
        }
        val m = AMOUNT.find(text)
        val amount = (m?.groupValues?.get(1)?.ifEmpty { null } ?: m?.groupValues?.get(2))
        val incoming = INCOME.containsMatchIn(text) && !DEBIT.containsMatchIn(text)
        val heading = when {
            amount == null -> "New payment message"
            incoming -> "₹$amount received"
            else -> "₹$amount spent"
        }
        val id = notificationId(captureId)

        val quick = Intent(context, QuickAddActivity::class.java).apply {
            putExtra(EXTRA_ID, captureId)
            putExtra(EXTRA_TITLE, heading)
            putExtra(EXTRA_TEXT, body.take(200))
            putExtra(EXTRA_INCOMING, incoming)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        }
        val open = Intent(context, MainActivity::class.java).apply {
            putExtra(EXTRA_ID, captureId)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val quickPi = PendingIntent.getActivity(context, id, quick, flags)
        val openPi = PendingIntent.getActivity(context, id + 1, open, flags)

        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL)
        } else {
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
        val n = builder
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(heading)
            .setContentText("Tap to add it · ${body.take(80)}")
            .setStyle(Notification.BigTextStyle().bigText(body.take(300)))
            .setContentIntent(quickPi)
            .setAutoCancel(true)
            .addAction(Notification.Action.Builder(null, "Add", quickPi).build())
            // On the lock screen: no amount or message, just a way to add it
            // (Android asks to unlock before the pop-up opens).
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(
                builder0(context)
                    .setSmallIcon(context.applicationInfo.icon)
                    .setContentTitle("Payment to add")
                    .setContentText("Tap to pick its category")
                    .setContentIntent(quickPi)
                    .setAutoCancel(true)
                    .build(),
            )
            .addAction(Notification.Action.Builder(null, "Open Rivero", openPi).build())
            .build()
        manager.notify(id, n)
        Diagnostics.popup(context, "shown")
    }

    /** Whether Rivero's pop-ups can appear at all: notifications allowed
     *  for the app, and the "Payments to add" channel not switched off. */
    fun health(context: Context): JSONObject {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val allowed = manager.areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 33 ||
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED)
        val channelOff = Build.VERSION.SDK_INT >= 26 &&
            manager.getNotificationChannel(CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE
        return JSONObject().apply {
            put("allowed", allowed)
            put("channelOff", channelOff)
        }
    }

    @Suppress("DEPRECATION")
    private fun builder0(context: Context) = if (Build.VERSION.SDK_INT >= 26) {
        Notification.Builder(context, CHANNEL)
    } else {
        Notification.Builder(context)
    }

    fun cancel(context: Context, captureId: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notificationId(captureId))
    }

    // ---- decisions made in the popup, applied by the app later ----------

    @Synchronized
    fun saveDecision(
        context: Context,
        captureId: String,
        action: String,
        category: String?,
        note: String?,
        account: String?,
    ) {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val all = JSONObject(p.getString(KEY_DECISIONS, "{}"))
        all.put(captureId, JSONObject().apply {
            put("action", action)
            put("category", category ?: JSONObject.NULL)
            put("note", note ?: JSONObject.NULL)
            put("account", account ?: JSONObject.NULL)
        })
        p.edit().putString(KEY_DECISIONS, all.toString()).apply()
    }

    /** All stored decisions as JSON, removed once read. */
    @Synchronized
    fun takeDecisions(context: Context): String {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val json = p.getString(KEY_DECISIONS, "{}") ?: "{}"
        p.edit().remove(KEY_DECISIONS).apply()
        return json
    }

    // ---- category names for the popup's chips (written by the app) ------

    fun setCategories(context: Context, names: List<String>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_CATEGORIES, JSONArray(names).toString()).apply()
    }

    fun categories(context: Context): List<String> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_CATEGORIES, null) ?: return DEFAULT_CATEGORIES
        val arr = JSONArray(raw)
        return (0 until arr.length()).map { arr.getString(it) }.ifEmpty { DEFAULT_CATEGORIES }
    }

    private val DEFAULT_CATEGORIES =
        listOf("Food", "Transport", "Shopping", "Bills", "Health", "Fun", "Other")

    // ---- accounts for the popup's "Paid from" chips (written by the app) --

    class Account(val id: String, val name: String, val mask: String?)

    fun setAccounts(context: Context, json: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_ACCOUNTS, json).apply()
    }

    fun accounts(context: Context): List<Account> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_ACCOUNTS, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map {
                val o = arr.getJSONObject(it)
                val mask = if (o.isNull("mask")) null else o.optString("mask").ifEmpty { null }
                Account(o.getString("id"), o.getString("name"), mask)
            }
        } catch (e: org.json.JSONException) {
            emptyList()
        }
    }

    /** Same pattern as the app's parser: "A/c XX1234", "card ending 4321". */
    private val MASK = Regex(
        "(?i)(?:(?:a/c|acct|account|card)\\s*(?:no\\.?|number)?\\s*[*x\\s]*|ending\\s+(?:in\\s+)?|ending\\s+[*x\\s]*)([0-9]{3,6})\\b",
    )

    /** The account [text] names by its last digits, if exactly one does. */
    fun accountIn(text: String, accounts: List<Account>): Account? {
        val digits = MASK.find(text)?.groupValues?.get(1) ?: return accounts.singleOrNull()
        val last = if (digits.length > 4) digits.takeLast(4) else digits
        return accounts.filter { it.mask == last }.singleOrNull()
    }

    // ---- "Open Rivero" on a notification ---------------------------------

    fun setOpenRequest(context: Context, captureId: String?) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_OPEN, captureId ?: "").apply()
    }

    fun takeOpenRequest(context: Context): String? {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val id = p.getString(KEY_OPEN, "")
        p.edit().remove(KEY_OPEN).apply()
        return id?.ifEmpty { null }
    }

    /** A tab to open ("log", "scan", "activity"), from a shortcut or the widget. */
    fun setOpenTab(context: Context, tab: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_TAB, tab).apply()
    }

    fun takeOpenTab(context: Context): String? {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val tab = p.getString(KEY_TAB, null)
        p.edit().remove(KEY_TAB).apply()
        return tab
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .remove(KEY_DECISIONS).remove(KEY_OPEN).remove(KEY_ACCOUNTS).apply()
    }
}
