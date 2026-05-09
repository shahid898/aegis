package com.resq.aegis.alert

/**
 * Single source of truth for action names, intent extras and notification
 * channel ids used by the wake-app pipeline. Keeping these together makes
 * the receiver/service/activity/plugin trio easy to audit.
 */
object AlertConstants {
    const val ACTION_SIMULATE = "com.resq.aegis.action.SIMULATE_ALERT"
    const val ACTION_SHOW_ALERT = "com.resq.aegis.action.SHOW_ALERT"
    const val ACTION_DISMISS_ALERT = "com.resq.aegis.action.DISMISS_ALERT"

    /**
     * FunctionGemma → service: escalate the currently-PENDING alert to the
     * full siren / lock-screen takeover. The intent's [EXTRA_ALERT_ID] must
     * match [AlertForegroundService.pendingAlert]'s id, otherwise the call
     * is ignored (defends against stale Dart-side decisions racing a fresh
     * SMS).
     */
    const val ACTION_ESCALATE_ALERT = "com.resq.aegis.action.ESCALATE_ALERT"

    /**
     * FunctionGemma → service: tear down a PENDING alert that the LLM
     * decided was not actually an emergency. Distinct from
     * [ACTION_DISMISS_ALERT] only for log clarity — the cleanup path is
     * shared.
     */
    const val ACTION_DISMISS_PENDING = "com.resq.aegis.action.DISMISS_PENDING"

    const val EXTRA_ALERT_ID = "extra_alert_id"
    const val EXTRA_ALERT_SOURCE = "extra_alert_source"
    const val EXTRA_ALERT_SENDER = "extra_alert_sender"
    const val EXTRA_ALERT_BODY = "extra_alert_body"
    const val EXTRA_ALERT_RECEIVED_AT = "extra_alert_received_at"
    const val EXTRA_ALERT_SEVERITY = "extra_alert_severity"

    /**
     * Carried on every alert payload that crosses the MethodChannel so the
     * Flutter UI knows whether to render the full lock-screen takeover
     * ("confirmed") or just a silent badge ("pending").
     *
     * Values: [STATE_PENDING] | [STATE_CONFIRMED].
     */
    const val EXTRA_ALERT_STATE = "extra_alert_state"

    const val STATE_PENDING = "pending"
    const val STATE_CONFIRMED = "confirmed"

    const val NOTIFICATION_CHANNEL_ID = "aegis_emergency_alert"
    const val NOTIFICATION_CHANNEL_NAME = "Emergency alert"
    /** Silent companion channel used while an alert is PENDING — same
     *  visibility / DnD bypass as the loud channel, but no sound + low
     *  importance so we don't ring/full-screen until the LLM confirms. */
    const val NOTIFICATION_CHANNEL_PENDING_ID = "aegis_emergency_pending"
    const val NOTIFICATION_CHANNEL_PENDING_NAME = "Emergency triage"
    const val NOTIFICATION_ID = 4242
    const val FULL_SCREEN_REQUEST_CODE = 7001
    const val DISMISS_REQUEST_CODE = 7002

    /**
     * Hard ceiling on how long the foreground service waits for Flutter +
     * FunctionGemma to make a verdict. Dimensioned to comfortably cover
     * a cold-start FunctionGemma 270M decode (~25–40 s with shader
     * compile + KV-cache prefill) and to stay strictly larger than the
     * Dart-side watchdog so that — under normal conditions — the Dart
     * router always lands the verdict first and this native watchdog
     * never fires.
     *
     * If it does fire, the policy is **always dismiss**. There is no
     * regex severity to fall back on (the receiver no longer stamps
     * one) and FunctionGemma is the sole arbiter of escalation, so the
     * absence of an LLM verdict means the silent PENDING heads-up just
     * tears itself down. We never go from silence to siren without an
     * explicit `dispatch_local_alarm` from the model.
     */
    const val LLM_VERDICT_TIMEOUT_MS = 60_000L

    /** MethodChannel name shared with `lib/core/alert/alert_bridge.dart`. */
    const val METHOD_CHANNEL = "com.resq.aegis/alert"

    /** Method names exchanged with Flutter. */
    const val METHOD_DELIVER_ALERT = "deliverAlert"
    const val METHOD_DISMISS = "dismiss"
    const val METHOD_SIMULATE = "simulate"
    const val METHOD_GET_PENDING = "getPendingAlert"
    /** Dart → Kotlin: upgrade PENDING → CONFIRMED. Argument is the alert id. */
    const val METHOD_ESCALATE = "escalate"
    /** Dart → Kotlin: tear down a PENDING alert. Argument is the alert id. */
    const val METHOD_DISMISS_PENDING = "dismissPending"
}
