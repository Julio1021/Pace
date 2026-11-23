package br.com.julio.pace

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RunNotification.CHANNEL)
        RunNotification.channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    @Suppress("UNCHECKED_CAST")
                    RunNotification.show(applicationContext, (call.arguments as? Map<String, Any?>) ?: emptyMap())
                    result.success(null)
                }
                "schedule" -> {
                    @Suppress("UNCHECKED_CAST")
                    val items = (call.arguments as? List<Map<String, Any?>>) ?: emptyList()
                    Reminders.schedule(applicationContext, items)
                    result.success(null)
                }
                "status" -> result.success(RunNotification.status(applicationContext))
                "settings" -> {
                    RunNotification.openSettings(this)
                    result.success(null)
                }
                "cancel" -> {
                    RunNotification.cancel(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        RunNotification.channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
