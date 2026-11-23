package br.com.julio.pace

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

/** Lembretes agendados (lembrete de corrida, meta quase batida, resumo da semana). */
object Reminders {
    private const val PREFS = "pace_reminders"
    private const val KEY = "list"
    private const val CHANNEL_ID = "pace_reminders"
    const val EXTRA_ID = "id"
    const val EXTRA_TITLE = "title"
    const val EXTRA_TEXT = "text"

    private fun pending(ctx: Context, id: Int, title: String = "", text: String = ""): PendingIntent {
        val i = Intent(ctx, ReminderReceiver::class.java)
            .setAction("br.com.julio.pace.REMINDER_$id")
            .putExtra(EXTRA_ID, id)
            .putExtra(EXTRA_TITLE, title)
            .putExtra(EXTRA_TEXT, text)
        return PendingIntent.getBroadcast(ctx, 5000 + id, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    /** Troca todos os lembretes pelos da lista [{id, at, title, text}]. */
    fun schedule(ctx: Context, items: List<Map<String, Any?>>) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        // Cancela os anteriores.
        try {
            val old = JSONArray(prefs.getString(KEY, "[]"))
            for (k in 0 until old.length()) am.cancel(pending(ctx, old.getJSONObject(k).getInt("id")))
        } catch (_: Throwable) {
        }
        val arr = JSONArray()
        val now = System.currentTimeMillis()
        for (m in items) {
            val id = (m["id"] as? Number)?.toInt() ?: continue
            val at = (m["at"] as? Number)?.toLong() ?: continue
            if (at <= now) continue
            val title = m["title"] as? String ?: "PACE"
            val text = m["text"] as? String ?: ""
            set(am, ctx, id, at, title, text)
            arr.put(JSONObject().put("id", id).put("at", at).put("title", title).put("text", text))
        }
        prefs.edit().putString(KEY, arr.toString()).apply()
    }

    private fun set(am: AlarmManager, ctx: Context, id: Int, at: Long, title: String, text: String) {
        // Horário aproximado (o Android pode atrasar alguns minutos para poupar bateria).
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(ctx, id, title, text))
    }

    /** Depois de reiniciar o celular, agenda de novo o que ainda não passou. */
    fun restore(ctx: Context) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val am = ctx.getSystemService(AlarmManager::class.java)
        val now = System.currentTimeMillis()
        try {
            val arr = JSONArray(prefs.getString(KEY, "[]"))
            for (k in 0 until arr.length()) {
                val o = arr.getJSONObject(k)
                if (o.getLong("at") > now) set(am, ctx, o.getInt("id"), o.getLong("at"), o.getString("title"), o.getString("text"))
            }
        } catch (_: Throwable) {
        }
    }

    fun show(ctx: Context, id: Int, title: String, text: String) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Lembretes", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Lembrete para correr, meta da semana e resumo semanal"
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
            )
        }
        val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        val pi = PendingIntent.getActivity(ctx, 9000 + id, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = Notification.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_pace)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setColor(0xFF14B887.toInt())
            .setAutoCancel(true)
            .setContentIntent(pi)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .build()
        try {
            nm.notify(1000 + id, n)
        } catch (_: Throwable) {
        }
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(Reminders.EXTRA_ID, 0)
        val title = intent.getStringExtra(Reminders.EXTRA_TITLE) ?: return
        val text = intent.getStringExtra(Reminders.EXTRA_TEXT) ?: ""
        Reminders.show(context, id, title, text)
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == "android.intent.action.MY_PACKAGE_REPLACED") {
            Reminders.restore(context)
        }
    }
}
