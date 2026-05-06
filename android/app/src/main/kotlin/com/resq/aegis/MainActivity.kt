package com.resq.aegis

import android.content.Intent
import android.os.Bundle
import com.resq.aegis.alert.AegisAlertPlugin
import com.resq.aegis.alert.AlertConstants
import com.resq.aegis.alert.AlertForegroundService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private val alertPlugin = AegisAlertPlugin()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(alertPlugin)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The alert plugin attaches asynchronously; deliver any payload that
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
        // running). The service tears down siren + vibrator + wake-lock
        // and removes itself from the foreground notification slot.
        AlertForegroundService.dismiss(this)
    }
}
