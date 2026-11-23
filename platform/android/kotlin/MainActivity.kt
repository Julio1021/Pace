package br.com.julio.pace

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /** Último retorno de login (pCloud) ainda não lido pelo app. */
    private var oauthResult: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        keepOAuth(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        keepOAuth(intent)
    }

    private fun keepOAuth(i: Intent?) {
        val d = i?.data ?: return
        if (d.scheme == "pace-pcloud") oauthResult = d.toString()
    }

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
                "openUrl" -> {
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.arguments as String)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: Throwable) {
                        result.success(false)
                    }
                }
                "takeOAuthResult" -> {
                    val r = oauthResult
                    oauthResult = null
                    result.success(r)
                }
                "network" -> {
                    // "wifi" (rede sem cobrança por uso), "mobile" ou "none".
                    val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    val caps = cm.getNetworkCapabilities(cm.activeNetwork)
                    result.success(
                        when {
                            caps == null || !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) -> "none"
                            cm.isActiveNetworkMetered -> "mobile"
                            else -> "wifi"
                        }
                    )
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
