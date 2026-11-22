package br.com.julio.pace

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import io.flutter.plugin.common.MethodChannel

/** Notificação ao vivo da corrida (barra de notificações e tela de bloqueio). */
object RunNotification {
    const val CHANNEL = "pace/run_notification"
    const val ACTION_TOGGLE = "br.com.julio.pace.action.TOGGLE"
    private const val ID = 7301
    // Canal novo com importância padrão: canais "silenciosos" não aparecem na
    // tela de bloqueio na maioria dos celulares. Som e vibração seguem desligados.
    private const val CHANNEL_ID = "pace_run_live_v2"
    private const val OLD_CHANNEL_ID = "pace_run_live"

    var channel: MethodChannel? = null

    private fun manager(ctx: Context) = ctx.getSystemService(NotificationManager::class.java)

    private fun ensureChannel(ctx: Context) {
        val nm = manager(ctx)
        if (nm.getNotificationChannel(OLD_CHANNEL_ID) != null) nm.deleteNotificationChannel(OLD_CHANNEL_ID)
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val c = NotificationChannel(CHANNEL_ID, "Corrida ao vivo", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Tempo, distância e pace durante a corrida, também na tela de bloqueio"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        nm.createNotificationChannel(c)
    }

    fun show(ctx: Context, a: Map<String, Any?>) {
        try {
            ensureChannel(ctx)
            val title = a["title"] as? String ?: "Corrida em andamento"
            val text = a["text"] as? String ?: ""
            val chip = a["chip"] as? String ?: ""
            val paused = a["paused"] as? Boolean ?: false
            val movingMs = (a["movingMs"] as? Number)?.toLong() ?: 0L
            val progress = (a["progress"] as? Number)?.toInt() ?: -1

            val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val contentPi = PendingIntent.getActivity(ctx, 0, open, flags)
            val togglePi = PendingIntent.getBroadcast(
                ctx, 1, Intent(ctx, RunActionReceiver::class.java).setAction(ACTION_TOGGLE), flags
            )
            val action = Notification.Action.Builder(
                Icon.createWithResource(ctx, if (paused) R.drawable.ic_stat_play else R.drawable.ic_stat_pause),
                if (paused) "Retomar" else "Pausar",
                togglePi
            ).build()

            val b = Notification.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_pace)
                .setContentTitle(title)
                .setContentText(text.substringBefore('\n'))
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setCategory("workout")
                .setColor(0xFF14B887.toInt())
                .setContentIntent(contentPi)
                .addAction(action)
            if (paused) {
                b.setShowWhen(false)
            } else {
                // O próprio Android conta o tempo, segundo a segundo, mesmo com a tela apagada.
                b.setUsesChronometer(true)
                    .setWhen(System.currentTimeMillis() - movingMs)
                    .setShowWhen(true)
            }
            if (progress in 0..1000) b.setProgress(1000, progress, false)

            // Android 16: pede para virar "Live Update" (chip na barra e destaque na tela de bloqueio).
            if (Build.VERSION.SDK_INT >= 36) {
                try {
                    b.javaClass.getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType).invoke(b, true)
                    if (chip.isNotEmpty()) {
                        b.javaClass.getMethod("setShortCriticalText", String::class.java).invoke(b, chip)
                    }
                } catch (_: Throwable) {
                }
            }
            manager(ctx).notify(ID, b.build())
        } catch (_: Throwable) {
        }
    }

    /** Se as notificações do app e do canal estão liberadas. */
    fun status(ctx: Context): Map<String, Any> {
        val nm = manager(ctx)
        ensureChannel(ctx)
        val ch = nm.getNotificationChannel(CHANNEL_ID)
        return mapOf(
            "enabled" to nm.areNotificationsEnabled(),
            "channelOn" to (ch == null || ch.importance != NotificationManager.IMPORTANCE_NONE),
            "lockScreenPublic" to (ch == null || ch.lockscreenVisibility != Notification.VISIBILITY_SECRET),
        )
    }

    fun openSettings(ctx: Context) {
        try {
            val i = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, ctx.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(i)
        } catch (_: Throwable) {
        }
    }

    fun cancel(ctx: Context) {
        try {
            manager(ctx).cancel(ID)
        } catch (_: Throwable) {
        }
    }
}

/** Recebe o toque em "Pausar/Retomar" e repassa para o app. */
class RunActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == RunNotification.ACTION_TOGGLE) {
            RunNotification.channel?.invokeMethod("action", "toggle")
        }
    }
}
