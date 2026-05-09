package com.resq.aegis

import android.content.Intent
import android.os.Bundle
import com.resq.aegis.alert.AegisAlertPlugin
import com.resq.aegis.alert.AlertConstants
import com.resq.aegis.alert.AlertForegroundService
import io.flutter.embedding.android.FlutterActivity

/**
 * Hosts the cached [FlutterEngine] created in [AegisApplication]. Reusing the
 * cached engine means:
 *
 *  * The Dart isolate (and DI graph: AlertRouter, FunctionRouter, LlmService)
 *    survives Activity destruction — no re-bootstrapping every time the user
 *    relaunches.
 *  * The `AegisAlertPlugin` is already registered against the engine before
 *    this Activity even exists, so cold-start alerts arriving while the app
 *    is killed get a verdict pipeline waiting for them.
 *
 * `getCachedEngineId()` flips `FlutterActivity` into "attach" mode — it does
 * NOT execute `main()` again, just binds the engine's surface to this
 * Activity's window.
 */
class MainActivity : FlutterActivity() {

    override fun getCachedEngineId(): String? = AegisApplication.ENGINE_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The plugin attaches via Application; deliver any payload that
        // launched us once Flutter is ready by posting onto the main looper.
        forwardAlertIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        forwardAlertIntent(intent)
    }

    private fun forwardAlertIntent(intent: Intent?) {
        if (intent?.action != AlertConstants.ACTION_SHOW_ALERT) return
        // Fire-and-forget: the plugin is responsible for caching until the
        // engine is attached, and AlertForegroundService.pendingAlert()
        // gives Flutter a second recovery path on cold start.
        AegisAlertPlugin.deliverFromIntent(intent)
        // Auto-dismiss the foreground service the moment Flutter takes
        // over: the user is now staring at the in-app briefing, so the
        // siren, vibration, wake-lock, and high-priority notification
        // are no longer needed (and feel like a stuck loop if left
        // running).
        AlertForegroundService.dismiss(this)
    }
}
