package com.resq.aegis.alert

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import com.resq.aegis.MainActivity
import com.resq.aegis.R

/**
 * Lock-screen takeover activity. Launched directly via [Intent.FLAG_ACTIVITY_NEW_TASK]
 * from the foreground service or via the notification's full-screen-intent
 * fallback. Its only job is to hold the user's attention long enough for
 * Flutter to come up and route them into the rich alert UI.
 *
 * The Flutter UI itself runs inside [MainActivity]; this activity is intentionally
 * minimal so it can launch in <100ms even when the engine is cold.
 */
class FullScreenAlertActivity : Activity() {

    private var alert: AlertEvent? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyLockScreenFlags()
        setContentView(R.layout.activity_full_screen_alert)

        alert = intent?.toAlertEvent()

        findViewById<android.widget.TextView>(R.id.alert_body)?.text =
            alert?.body ?: getString(R.string.alert_default_body)
        findViewById<android.widget.TextView>(R.id.alert_sender)?.text =
            alert?.sender ?: getString(R.string.alert_default_sender)
        findViewById<android.widget.Button>(R.id.alert_open_app)?.setOnClickListener {
            launchFlutterUi()
        }
        findViewById<android.widget.Button>(R.id.alert_dismiss)?.setOnClickListener {
            AlertForegroundService.dismiss(this)
            finishAndRemoveTask()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        alert = intent.toAlertEvent() ?: alert
        recreate()
    }

    private fun applyLockScreenFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            km?.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun launchFlutterUi() {
        val event = alert
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            action = AlertConstants.ACTION_SHOW_ALERT
            event?.let { putAlertExtras(it) }
        }
        startActivity(intent)
        finishAndRemoveTask()
    }
}
