package com.resq.aegis.alert

import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * MethodChannel bridge that lets Dart drive the alert pipeline:
 *  - `simulate(payload)` enqueues a synthetic alert (debug + onboarding QA)
 *  - `dismiss()` tears down the active alarm + notification
 *  - `getPendingAlert()` lets Flutter recover the alert that was active when
 *    the app got cold-launched from the lock-screen takeover
 *
 * Calls from Kotlin → Dart go through [deliverAlert]; the [MainActivity]
 * forwards inbound intents into here while the engine is attached.
 */
class AegisAlertPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, AlertConstants.METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        active = this
        AlertForegroundService.pendingAlert()?.let {
            deliverAlert(it, AlertForegroundService.pendingState())
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
        if (active === this) active = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("no_context", "Plugin detached", null)
            return
        }
        when (call.method) {
            AlertConstants.METHOD_SIMULATE -> handleSimulate(ctx, call, result)
            AlertConstants.METHOD_DISMISS -> {
                AlertForegroundService.dismiss(ctx)
                result.success(true)
            }
            AlertConstants.METHOD_GET_PENDING -> {
                result.success(
                    AlertForegroundService.pendingAlert()
                        ?.toMap(AlertForegroundService.pendingState()),
                )
            }
            AlertConstants.METHOD_ESCALATE -> {
                val id = idArgument(call)
                if (id == null) {
                    result.error("missing_id", "escalate requires an alert id", null)
                    return
                }
                AlertForegroundService.escalate(ctx, id)
                result.success(true)
            }
            AlertConstants.METHOD_DISMISS_PENDING -> {
                val id = idArgument(call)
                if (id == null) {
                    result.error("missing_id", "dismissPending requires an alert id", null)
                    return
                }
                AlertForegroundService.dismissPending(ctx, id)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun idArgument(call: MethodCall): String? {
        val args = call.arguments
        return when (args) {
            is String -> args.takeIf { it.isNotBlank() }
            is Map<*, *> -> (args["id"] as? String)?.takeIf { it.isNotBlank() }
            else -> null
        }
    }

    private fun handleSimulate(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
        val event = AlertEvent(
            id = (args["id"] as? String) ?: UUID.randomUUID().toString(),
            source = (args["source"] as? String) ?: AlertEvent.SOURCE_SIMULATION,
            sender = args["sender"] as? String,
            body = (args["body"] as? String) ?: "Simulated alert",
            receivedAtEpochMs = (args["receivedAtEpochMs"] as? Number)?.toLong()
                ?: System.currentTimeMillis(),
            severity = (args["severity"] as? String) ?: AlertEvent.SEVERITY_CRITICAL,
        )

        // Route through the receiver path so Sprint 1 exercises the same code
        // that real SMS will hit in production.
        val intent = Intent(AlertConstants.ACTION_SIMULATE).apply {
            setPackage(ctx.packageName)
            putAlertExtras(event)
        }
        try {
            ctx.sendBroadcast(intent)
            result.success(event.toMap())
        } catch (t: Throwable) {
            Log.e(TAG, "Simulate broadcast failed", t)
            result.error("simulate_failed", t.message, null)
        }
    }

    fun deliverAlert(
        event: AlertEvent,
        state: String = AlertConstants.STATE_PENDING,
    ) {
        val ch = channel ?: return
        ch.invokeMethod(AlertConstants.METHOD_DELIVER_ALERT, event.toMap(state))
    }

    companion object {
        private const val TAG = "AegisAlertPlugin"

        @Volatile
        private var active: AegisAlertPlugin? = null

        /** Forward an intent extra carrying an alert payload up into Flutter. */
        fun deliverFromIntent(intent: Intent?): Boolean {
            val event = intent?.toAlertEvent() ?: return false
            val state = intent.getStringExtra(AlertConstants.EXTRA_ALERT_STATE)
                ?: AlertConstants.STATE_PENDING
            active?.deliverAlert(event, state) ?: return false
            return true
        }

        /**
         * Service → Flutter: re-publish the alert when the foreground service
         * transitions PENDING → CONFIRMED so the Dart cubit can swap the
         * triage UI for the full siren takeover. No-op if no plugin is
         * attached (e.g. cold boot before the engine spins up — the next
         * `getPendingAlert` handshake will recover state).
         */
        fun notifyDelivered(event: AlertEvent, state: String) {
            active?.deliverAlert(event, state)
        }
    }
}
