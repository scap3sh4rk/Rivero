package dev.scap3sh4rk.rivero

import android.content.Context
import org.json.JSONObject

/**
 * Counts what the notification listener saw, so "why was my payment not
 * captured?" can be answered on screen. Stores only package names, counters
 * and times, never message text.
 */
object Diagnostics {
    private const val PREFS = "rivero_capture_diag"

    @Synchronized
    fun note(context: Context, pkg: String, result: String) {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        p.edit()
            .putInt("n_$result", p.getInt("n_$result", 0) + 1)
            .putString("last_pkg", pkg)
            .putString("last_result", result)
            .putLong("last_time", System.currentTimeMillis())
            .apply()
    }

    /** What happened to the last pop-up ("shown", or why it was not). */
    @Synchronized
    fun popup(context: Context, result: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("popup_result", result)
            .putLong("popup_time", System.currentTimeMillis())
            .apply()
    }

    /** The listener's connection to Android (lost after some app updates). */
    @Synchronized
    fun listener(context: Context, connected: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean("listener_connected", connected)
            .putLong("listener_time", System.currentTimeMillis())
            .apply()
    }

    fun read(context: Context): String {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return JSONObject().apply {
            put("queued", p.getInt("n_queued", 0))
            put("noMoney", p.getInt("n_no money", 0))
            put("noText", p.getInt("n_no text", 0))
            put("lastPackage", p.getString("last_pkg", null))
            put("lastResult", p.getString("last_result", null))
            put("lastTime", p.getLong("last_time", 0))
            put("popupResult", p.getString("popup_result", null))
            put("popupTime", p.getLong("popup_time", 0))
            if (p.contains("listener_connected")) {
                put("listenerConnected", p.getBoolean("listener_connected", false))
            }
            put("listenerTime", p.getLong("listener_time", 0))
        }.toString()
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }
}
