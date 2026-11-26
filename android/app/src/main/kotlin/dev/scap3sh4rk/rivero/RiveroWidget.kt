package dev.scap3sh4rk.rivero

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Home-screen widget: Safe to spend per day and a Log button. The app sends
 * the text whenever the number changes (see [update]); the widget shows the
 * last one it got. Amounts are hidden ("₹••••") when the app hides amounts
 * or App lock is on: the app sends that text instead.
 */
class RiveroWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        render(context, manager, ids)
    }

    companion object {
        private const val PREFS = "rivero_widget"
        const val ACTION_LOG = "dev.scap3sh4rk.rivero.action.LOG"

        /** Saves what to show and redraws every Rivero widget. */
        fun update(context: Context, amount: String, caption: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("amount", amount)
                .putString("caption", caption)
                .apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, RiveroWidget::class.java))
            if (ids.isNotEmpty()) render(context, manager, ids)
        }

        /** Forgets the number (Delete all data). */
        fun clear(context: Context) = update(context, "—", "Open Rivero once")

        private fun render(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val open = PendingIntent.getActivity(
                context, 0, Intent(context, MainActivity::class.java), flags,
            )
            val log = PendingIntent.getActivity(
                context, 1,
                Intent(context, MainActivity::class.java).setAction(ACTION_LOG),
                flags,
            )
            val views = RemoteViews(context.packageName, R.layout.widget_sts).apply {
                setTextViewText(R.id.widget_amount, p.getString("amount", "—"))
                setTextViewText(R.id.widget_caption, p.getString("caption", "Open Rivero once"))
                setOnClickPendingIntent(R.id.widget_root, open)
                setOnClickPendingIntent(R.id.widget_log, log)
            }
            manager.updateAppWidget(ids, views)
        }
    }
}
