package com.resq.aegis.alert

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Persistent foreground service that owns the alert lifecycle and the
 * PENDING → CONFIRMED state machine that the FunctionGemma router drives.
 *
 * **Why a state machine?** Android requires a foreground service to start
 * within ~5 s of a [SmsAlertReceiver.onReceive] callback. We can't block
 * the receiver waiting for an on-device LLM verdict (FunctionGemma takes
 * 1–3 s on a warm engine, longer on cold start). Instead the receiver
 * starts the service in PENDING state — silent heads-up, no siren, no
 * full-screen-intent — which satisfies the foreground-service contract
 * but doesn't actually wake the user. Flutter then runs FunctionGemma on
 * the alert body and either:
 *
 *  - calls [escalate] (`dispatch_local_alarm`) → upgrade to CONFIRMED →
 *    full siren + vibration + full-screen-intent + lock-screen takeover
 *  - calls [dismissPending] (`request_clarification` only) → tear it all
 *    down silently
 *
 * **Watchdog.** A native [LLM_VERDICT_TIMEOUT_MS] timer guards against a
 * crashed / killed Flutter engine: if the service is still PENDING after
 * the deadline, the alert is **always dismissed**. There is no regex
 * severity to fall back on any more — FunctionGemma is the sole arbiter
 * of escalation, so the absence of a verdict means we keep the silent
 * PENDING heads-up out of the user's way. The Dart-side watchdog
 * fires earlier and drives almost every verdict; this native timer
 * exists purely as a last-resort safety net.
 */
class AlertForegroundService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private var vibrator: Vibrator? = null
    private var pending: AlertEvent? = null
    private var state: String = AlertConstants.STATE_PENDING

    private val watchdog = Handler(Looper.getMainLooper())
    private val watchdogRunnable = Runnable { onWatchdogFired() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        Log.d(TAG, "onStartCommand action=$action state=$state")

        when (action) {
            AlertConstants.ACTION_DISMISS_ALERT,
            AlertConstants.ACTION_DISMISS_PENDING -> {
                if (action == AlertConstants.ACTION_DISMISS_PENDING) {
                    val targetId = intent.getStringExtra(AlertConstants.EXTRA_ALERT_ID)
                    if (targetId != null && pending?.id != targetId) {
                        Log.d(TAG, "dismissPending id=$targetId mismatch (current=${pending?.id}); ignoring")
                        return START_NOT_STICKY
                    }
                    if (state == AlertConstants.STATE_CONFIRMED) {
                        Log.d(TAG, "dismissPending ignored: already CONFIRMED")
                        return START_NOT_STICKY
                    }
                }
                stopAlert()
                return START_NOT_STICKY
            }
            AlertConstants.ACTION_ESCALATE_ALERT -> {
                val targetId = intent.getStringExtra(AlertConstants.EXTRA_ALERT_ID)
                val current = pending
                if (current == null) {
                    Log.w(TAG, "Escalate received with no pending alert; ignoring")
                    return START_NOT_STICKY
                }
                if (targetId != null && targetId != current.id) {
                    Log.w(TAG, "Escalate id=$targetId does not match pending=${current.id}; ignoring")
                    return START_NOT_STICKY
                }
                escalateInternal(current)
                return START_STICKY
            }
            AlertConstants.ACTION_SHOW_ALERT, null -> {
                val event = intent?.toAlertEvent()
                if (event == null) {
                    Log.w(TAG, "Service started without an alert payload, stopping")
                    stopSelf(startId)
                    return START_NOT_STICKY
                }
                pending = event
                latestEvent = event
                state = AlertConstants.STATE_PENDING
                latestState = state
                startForegroundWithAlert(event)
                armWatchdog()
                // Push the PENDING event up to Flutter so AlertRouter can
                // hand it to FunctionGemma for a verdict. Without this the
                // Dart side never sees the alert and the only thing that
                // ever fires is the native watchdog (always-dismiss). If
                // the engine isn't attached yet (cold boot from
                // lock-screen takeover) this no-ops and the next
                // `getPendingAlert` handshake recovers state.
                AegisAlertPlugin.notifyDelivered(event, state)
                // No wake-lock, no vibration, no full-screen-intent yet — those
                // are reserved for CONFIRMED so we never wake the user on a
                // false positive. The notification is silent (low-importance
                // channel) so Android shows it as a heads-up badge at most.
            }
            else -> {
                Log.w(TAG, "Unknown action=$action")
            }
        }
        return START_STICKY
    }

    private fun escalateInternal(event: AlertEvent) {
        if (state == AlertConstants.STATE_CONFIRMED) {
            Log.d(TAG, "escalate ignored: already CONFIRMED")
            return
        }
        Log.i(TAG, "Escalating alert ${event.id} → CONFIRMED (full siren)")
        state = AlertConstants.STATE_CONFIRMED
        latestState = state
        cancelWatchdog()
        // Re-post the notification with the loud channel + full-screen-intent.
        startForegroundWithAlert(event)
        acquireWakeLock()
        vibrate()
        launchFullScreenActivity(event)
        // Push the new state up to Flutter so the Dart-side cubit can
        // transition the takeover screen from "triage" UI → "siren" UI.
        AegisAlertPlugin.notifyDelivered(event, state)
    }

    private fun startForegroundWithAlert(event: AlertEvent) {
        val notification = buildNotification(event, state)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                AlertConstants.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(AlertConstants.NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(event: AlertEvent, state: String): Notification {
        val confirmed = state == AlertConstants.STATE_CONFIRMED
        val channelId = if (confirmed) {
            AlertConstants.NOTIFICATION_CHANNEL_ID
        } else {
            AlertConstants.NOTIFICATION_CHANNEL_PENDING_ID
        }
        val fullScreenIntent = Intent(this, FullScreenAlertActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_HISTORY
            putAlertExtras(event)
            putExtra(AlertConstants.EXTRA_ALERT_STATE, state)
        }
        val fullScreenPending = PendingIntent.getActivity(
            this,
            AlertConstants.FULL_SCREEN_REQUEST_CODE,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val dismissIntent = Intent(this, AlertForegroundService::class.java).apply {
            action = AlertConstants.ACTION_DISMISS_ALERT
        }
        val dismissPending = PendingIntent.getService(
            this,
            AlertConstants.DISMISS_REQUEST_CODE,
            dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val title = if (confirmed) "Emergency alert" else "Checking incoming alert…"
        val priority = if (confirmed) {
            NotificationCompat.PRIORITY_MAX
        } else {
            NotificationCompat.PRIORITY_LOW
        }
        val icon = applicationInfo.icon
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(if (icon != 0) icon else android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(event.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(event.body))
            .setPriority(priority)
            .setCategory(
                if (confirmed) NotificationCompat.CATEGORY_ALARM
                else NotificationCompat.CATEGORY_STATUS
            )
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(fullScreenPending)
            .addAction(0, "Dismiss", dismissPending)
        if (confirmed) {
            builder.setFullScreenIntent(fullScreenPending, true)
        }
        return builder.build()
    }

    private fun launchFullScreenActivity(event: AlertEvent) {
        val intent = Intent(this, FullScreenAlertActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            putAlertExtras(event)
            putExtra(AlertConstants.EXTRA_ALERT_STATE, AlertConstants.STATE_CONFIRMED)
        }
        try {
            startActivity(intent)
        } catch (t: Throwable) {
            // Background activity start may be blocked; the full-screen-intent
            // notification we already posted will handle that fallback path.
            Log.w(TAG, "Direct activity launch denied, relying on full-screen-intent", t)
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "Aegis::AlertWakeLock",
        ).apply { setReferenceCounted(false) }
        try {
            wakeLock?.acquire(WAKE_LOCK_TIMEOUT_MS)
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to acquire wake-lock", t)
        }
    }

    private fun vibrate() {
        val vib = currentVibrator() ?: return
        vibrator = vib
        val pattern = longArrayOf(0, 600, 250, 600, 250, 600)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val effect = VibrationEffect.createWaveform(pattern, /*repeat=*/0)
            try {
                vib.vibrate(effect)
            } catch (t: Throwable) {
                Log.w(TAG, "Vibration failed", t)
            }
        } else {
            @Suppress("DEPRECATION")
            vib.vibrate(pattern, 0)
        }
    }

    private fun currentVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun armWatchdog() {
        cancelWatchdog()
        watchdog.postDelayed(watchdogRunnable, AlertConstants.LLM_VERDICT_TIMEOUT_MS)
    }

    private fun cancelWatchdog() {
        watchdog.removeCallbacks(watchdogRunnable)
    }

    /**
     * Last-resort decision when no Dart-side verdict arrived in time.
     *
     * **Policy: escalate on timeout.** The cached [FlutterEngine] in
     * [AegisApplication] guarantees Dart is alive even on cold-start, so
     * a missed verdict means either (a) Gemma cold-load exceeded the
     * already-generous [LLM_VERDICT_TIMEOUT_MS] budget, or (b) the engine
     * itself crashed mid-bootstrap. Both situations are recoverable: if
     * an SMS arrived through the manifest receiver, the telco already
     * vouched for it as a real message — a stuck verdict is no reason to
     * silently drop a possible emergency. We escalate to the loud channel
     * + full-screen-intent so the user is never left thinking the app
     * silently swallowed an alert.
     *
     * **Tradeoff.** This biases toward false positives (a promo SMS that
     * outlasts the watchdog will siren). The previous "always dismiss"
     * policy biased toward false negatives, which is a strictly worse
     * failure mode for an emergency app. Once the Dart engine is reliably
     * fast on cold-start (post-warmup), this watchdog should never fire
     * in practice.
     */
    private fun onWatchdogFired() {
        val current = pending ?: return
        if (state == AlertConstants.STATE_CONFIRMED) return
        Log.w(
            TAG,
            "Watchdog fired (id=${current.id}) sev=${current.severity} → ESCALATE " +
                "(no LLM verdict received within ${AlertConstants.LLM_VERDICT_TIMEOUT_MS}ms)"
        )
        escalateInternal(current)
    }

    private fun stopAlert() {
        cancelWatchdog()
        try {
            vibrator?.cancel()
        } catch (_: Throwable) {
            // ignore
        }
        vibrator = null

        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (_: Throwable) {
            // ignore
        }
        wakeLock = null
        pending = null
        latestEvent = null
        state = AlertConstants.STATE_PENDING
        latestState = state

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun ensureNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        if (nm.getNotificationChannel(AlertConstants.NOTIFICATION_CHANNEL_ID) == null) {
            val audioAttrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val sound: Uri = Settings.System.DEFAULT_ALARM_ALERT_URI
                ?: Settings.System.DEFAULT_NOTIFICATION_URI
            val channel = NotificationChannel(
                AlertConstants.NOTIFICATION_CHANNEL_ID,
                AlertConstants.NOTIFICATION_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Aegis emergency alerts that bypass do-not-disturb."
                enableLights(true)
                enableVibration(true)
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setSound(sound, audioAttrs)
            }
            nm.createNotificationChannel(channel)
        }

        if (nm.getNotificationChannel(AlertConstants.NOTIFICATION_CHANNEL_PENDING_ID) == null) {
            val pendingChannel = NotificationChannel(
                AlertConstants.NOTIFICATION_CHANNEL_PENDING_ID,
                AlertConstants.NOTIFICATION_CHANNEL_PENDING_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Silent placeholder while Aegis verifies an inbound alert."
                enableLights(false)
                enableVibration(false)
                setBypassDnd(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setSound(null, null)
            }
            nm.createNotificationChannel(pendingChannel)
        }
    }

    override fun onDestroy() {
        cancelWatchdog()
        stopAlert()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "AlertForegroundService"
        private const val WAKE_LOCK_TIMEOUT_MS = 60_000L

        @Volatile
        private var latestEvent: AlertEvent? = null

        @Volatile
        private var latestState: String = AlertConstants.STATE_PENDING

        /** Last alert the service started for. Read by [AegisAlertPlugin]. */
        fun pendingAlert(): AlertEvent? = latestEvent

        /** Current state of the service ("pending" / "confirmed"). */
        fun pendingState(): String = latestState

        fun start(context: Context, event: AlertEvent) {
            val intent = Intent(context, AlertForegroundService::class.java).apply {
                action = AlertConstants.ACTION_SHOW_ALERT
                putAlertExtras(event)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun escalate(context: Context, alertId: String) {
            val intent = Intent(context, AlertForegroundService::class.java).apply {
                action = AlertConstants.ACTION_ESCALATE_ALERT
                putExtra(AlertConstants.EXTRA_ALERT_ID, alertId)
            }
            context.startService(intent)
        }

        fun dismissPending(context: Context, alertId: String) {
            val intent = Intent(context, AlertForegroundService::class.java).apply {
                action = AlertConstants.ACTION_DISMISS_PENDING
                putExtra(AlertConstants.EXTRA_ALERT_ID, alertId)
            }
            context.startService(intent)
        }

        fun dismiss(context: Context) {
            val intent = Intent(context, AlertForegroundService::class.java).apply {
                action = AlertConstants.ACTION_DISMISS_ALERT
            }
            context.startService(intent)
        }
    }
}

internal fun Intent.putAlertExtras(event: AlertEvent): Intent {
    putExtra(AlertConstants.EXTRA_ALERT_ID, event.id)
    putExtra(AlertConstants.EXTRA_ALERT_SOURCE, event.source)
    putExtra(AlertConstants.EXTRA_ALERT_SENDER, event.sender)
    putExtra(AlertConstants.EXTRA_ALERT_BODY, event.body)
    putExtra(AlertConstants.EXTRA_ALERT_RECEIVED_AT, event.receivedAtEpochMs)
    putExtra(AlertConstants.EXTRA_ALERT_SEVERITY, event.severity)
    return this
}

internal fun Intent.toAlertEvent(): AlertEvent? {
    val id = getStringExtra(AlertConstants.EXTRA_ALERT_ID) ?: return null
    val source = getStringExtra(AlertConstants.EXTRA_ALERT_SOURCE) ?: return null
    val body = getStringExtra(AlertConstants.EXTRA_ALERT_BODY) ?: return null
    return AlertEvent(
        id = id,
        source = source,
        sender = getStringExtra(AlertConstants.EXTRA_ALERT_SENDER),
        body = body,
        receivedAtEpochMs = getLongExtra(
            AlertConstants.EXTRA_ALERT_RECEIVED_AT,
            System.currentTimeMillis(),
        ),
        severity = getStringExtra(AlertConstants.EXTRA_ALERT_SEVERITY)
            ?: AlertEvent.SEVERITY_HIGH,
    )
}
