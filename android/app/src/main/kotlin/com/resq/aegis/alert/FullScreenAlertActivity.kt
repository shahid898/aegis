package com.resq.aegis.alert

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import android.widget.TextView
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
 *
 * **Auto-open behaviour.** A [Handler] schedules an automatic transition into
 * [MainActivity] after [AUTO_OPEN_DELAY_MS]. The user no longer needs to tap
 * an "Open app" button — the takeover is held just long enough for the siren
 * to register, then the rich Flutter UI takes over with the briefing already
 * surfaced (via [AlertBriefingSink] inside the assistant cubit). A live
 * countdown is rendered above the dismiss button so the user knows what's
 * coming. The dismiss button still works as a kill-switch for false alarms.
 */
class FullScreenAlertActivity : Activity() {

    companion object {
        /** How long to hold the takeover screen before auto-opening Flutter. */
        const val AUTO_OPEN_DELAY_MS = 4000L

        /** Tick interval for the countdown label. */
        private const val COUNTDOWN_TICK_MS = 1000L
    }

    private var alert: AlertEvent? = null
    private val handler = Handler(Looper.getMainLooper())
    private var autoOpenScheduled = false

    private val autoOpenRunnable = Runnable {
        autoOpenScheduled = false
        launchFlutterUi()
    }

    private var countdownRemainingMs: Long = AUTO_OPEN_DELAY_MS
    private val countdownTick: Runnable = object : Runnable {
        override fun run() {
            countdownRemainingMs -= COUNTDOWN_TICK_MS
            renderCountdown()
            if (countdownRemainingMs > 0) {
                handler.postDelayed(this, COUNTDOWN_TICK_MS)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyLockScreenFlags()
        setContentView(R.layout.activity_full_screen_alert)

        alert = intent?.toAlertEvent()

        findViewById<TextView>(R.id.alert_body)?.text =
            alert?.body ?: getString(R.string.alert_default_body)
        findViewById<TextView>(R.id.alert_sender)?.text =
            alert?.sender ?: getString(R.string.alert_default_sender)
        findViewById<android.widget.Button>(R.id.alert_dismiss)?.setOnClickListener {
            cancelAutoOpen()
            AlertForegroundService.dismiss(this)
            finishAndRemoveTask()
        }

        scheduleAutoOpen()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        alert = intent.toAlertEvent() ?: alert
        recreate()
    }

    override fun onDestroy() {
        cancelAutoOpen()
        super.onDestroy()
    }

    private fun scheduleAutoOpen() {
        if (autoOpenScheduled) return
        autoOpenScheduled = true
        countdownRemainingMs = AUTO_OPEN_DELAY_MS
        renderCountdown()
        handler.postDelayed(autoOpenRunnable, AUTO_OPEN_DELAY_MS)
        handler.postDelayed(countdownTick, COUNTDOWN_TICK_MS)
    }

    private fun cancelAutoOpen() {
        if (!autoOpenScheduled) return
        handler.removeCallbacks(autoOpenRunnable)
        handler.removeCallbacks(countdownTick)
        autoOpenScheduled = false
    }

    private fun renderCountdown() {
        val seconds = (countdownRemainingMs / 1000L).coerceAtLeast(0L).toInt()
        val label = findViewById<TextView>(R.id.alert_auto_open_label) ?: return
        label.text = if (seconds > 0) {
            getString(R.string.alert_auto_open_in, seconds)
        } else {
            getString(R.string.alert_auto_open_now)
        }
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
