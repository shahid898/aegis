package com.resq.aegis.alert

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.telephony.SmsMessage
import android.util.Log
import java.util.UUID

/**
 * Listens for inbound SMS / WEA messages and pushes every one into
 * [AlertForegroundService] in the PENDING state.
 *
 * **No keyword regex, no trusted-sender allow-list.** FunctionGemma is
 * the sole arbiter of "is this a real emergency". The previous
 * `looksLikeEmergency` keyword filter and `TRUSTED_ALPHA_SENDERS`
 * allow-list both let promo SMS sneak past while also gating the
 * pipeline on hardcoded English keywords — exactly the failure modes
 * we now want the on-device LLM to handle.
 *
 * What this receiver still does:
 *   1. Extract the SMS body and sender from the broadcast intent.
 *   2. Hand it to [AlertForegroundService.start] in PENDING state
 *      (silent heads-up, no siren, no full-screen-intent).
 *   3. The service arms its watchdog and waits for the Dart side to
 *      either escalate (FunctionGemma said "real emergency") or
 *      dismiss (LLM said no, or watchdog fired with no verdict).
 *
 * A debug `SIMULATE_ALERT` action lets us exercise the whole wake path
 * without a real telco.
 */
class SmsAlertReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d(TAG, "SMS receiver onReceive action=$action")

        when (action) {
            Telephony.Sms.Intents.SMS_RECEIVED_ACTION -> handleSms(context, intent)
            AlertConstants.ACTION_SIMULATE -> handleSimulation(context, intent)
            else -> Log.d(TAG, "Ignoring action=$action")
        }
    }

    private fun handleSms(context: Context, intent: Intent) {
        val messages = extractMessages(intent)
        if (messages.isEmpty()) {
            Log.w(TAG, "No SMS PDUs found in intent")
            return
        }

        val sender = messages.firstOrNull()?.displayOriginatingAddress
        val body = messages.joinToString(separator = "") { it.displayMessageBody.orEmpty() }
        if (body.isBlank()) {
            Log.w(TAG, "Empty SMS body, skipping")
            return
        }

        // Every non-empty SMS becomes a PENDING alert. Severity is set
        // to UNKNOWN so the native watchdog never has a regex-derived
        // signal to fall back on — only FunctionGemma can promote this
        // to CONFIRMED.
        dispatch(
            context = context,
            event = AlertEvent(
                id = UUID.randomUUID().toString(),
                source = AlertEvent.SOURCE_SMS,
                sender = sender,
                body = body,
                receivedAtEpochMs = System.currentTimeMillis(),
                severity = AlertEvent.SEVERITY_UNKNOWN,
            ),
        )
    }

    private fun handleSimulation(context: Context, intent: Intent) {
        val body = intent.getStringExtra(AlertConstants.EXTRA_ALERT_BODY)
            ?: "Simulated emergency alert from Aegis."
        val sender = intent.getStringExtra(AlertConstants.EXTRA_ALERT_SENDER) ?: "Aegis-Sim"
        val severity = intent.getStringExtra(AlertConstants.EXTRA_ALERT_SEVERITY)
            ?: AlertEvent.SEVERITY_UNKNOWN

        val event = AlertEvent(
            id = intent.getStringExtra(AlertConstants.EXTRA_ALERT_ID)
                ?: UUID.randomUUID().toString(),
            source = AlertEvent.SOURCE_SIMULATION,
            sender = sender,
            body = body,
            receivedAtEpochMs = System.currentTimeMillis(),
            severity = severity,
        )
        dispatch(context, event)
        // Simulations skip LLM routing — escalate immediately so the CONFIRMED
        // notification (loud, persistent) is posted before the user kills the app.
        // The intents are serialized by the service so SHOW_ALERT always arrives
        // before ESCALATE_ALERT.
        AlertForegroundService.escalate(context, event.id)
    }

    private fun dispatch(context: Context, event: AlertEvent) {
        Log.i(TAG, "Dispatching alert id=${event.id} source=${event.source}")
        AlertForegroundService.start(context, event)
    }

    private fun extractMessages(intent: Intent): List<SmsMessage> {
        return try {
            Telephony.Sms.Intents.getMessagesFromIntent(intent)?.toList().orEmpty()
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to extract SMS PDUs", t)
            emptyList()
        }
    }

    companion object {
        private const val TAG = "SmsAlertReceiver"
    }
}
