package dev.scap3sh4rk.rivero

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray

/**
 * Reminders (card bills, autopay tomorrow, money owed) worked out by the app
 * and shown by Android at the right time, even when Rivero is closed. The
 * app re-plans them each time it opens; after a reboot they are re-armed.
 * Only titles and short texts are kept here, never balances history.
 */
object Reminders {
    private const val PREFS = "rivero_reminders"
    private const val KEY = "planned"
    private const val CHANNEL = "rivero_reminders"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_ID = "rid"

    private fun requestCode(id: String) = (id.hashCode() and 0x3fffffff) or 0x40000000

    private fun pendingFor(context: Context, id: String, title: String, body: String): PendingIntent {
        val i = Intent(context, ReminderReceiver::class.java)
            .putExtra(EXTRA_ID, id).putExtra(EXTRA_TITLE, title).putExtra(EXTRA_BODY, body)
        return PendingIntent.getBroadcast(
            context, requestCode(id), i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Replaces all planned reminders with [json] ([{id, at, title, body}]). */
    @Synchronized
    fun schedule(context: Context, json: String) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        // Cancel what was planned before.
        val old = JSONArray(prefs.getString(KEY, "[]"))
        for (i in 0 until old.length()) {
            val r = old.getJSONObject(i)
            alarms.cancel(pendingFor(context, r.getString("id"), r.getString("title"), r.getString("body")))
        }
        val next = JSONArray(json)
        val now = System.currentTimeMillis()
        for (i in 0 until next.length()) {
            val r = next.getJSONObject(i)
            val at = r.getLong("at")
            if (at <= now) continue
            // Inexact is fine for a 9 am nudge and needs no special permission.
            alarms.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                at,
                pendingFor(context, r.getString("id"), r.getString("title"), r.getString("body")),
            )
        }
        prefs.edit().putString(KEY, json).apply()
    }

    /** After a reboot: arm again whatever is still in the future. */
    fun rearm(context: Context) {
        val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return
        schedule(context, json)
    }

    fun clear(context: Context) = schedule(context, "[]")

    fun show(context: Context, id: String, title: String, body: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Reminders", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Card bills, autopay tomorrow, money owed"
                },
            )
        }
        val open = PendingIntent.getActivity(
            context, requestCode(id),
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context)
        manager.notify(
            requestCode(id),
            builder.setSmallIcon(context.applicationInfo.icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setContentIntent(open)
                .setAutoCancel(true)
                // Amounts and names only once unlocked (if the phone hides
                // sensitive content on the lock screen).
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setPublicVersion(
                    (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(context))
                        .setSmallIcon(context.applicationInfo.icon)
                        .setContentTitle("Rivero reminder")
                        .setContentIntent(open)
                        .setAutoCancel(true)
                        .build(),
                )
                .build(),
        )
    }
}

/** Fires at a reminder's time and shows it. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Reminders.show(
            context,
            intent.getStringExtra(Reminders.EXTRA_ID) ?: return,
            intent.getStringExtra(Reminders.EXTRA_TITLE) ?: return,
            intent.getStringExtra(Reminders.EXTRA_BODY) ?: "",
        )
    }
}

/** Alarms do not survive a reboot: arm the planned reminders again. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.MY_PACKAGE_REPLACED"
        ) {
            Reminders.rearm(context)
        }
    }
}
