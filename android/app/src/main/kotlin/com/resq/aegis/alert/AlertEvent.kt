package com.resq.aegis.alert

/**
 * Wire-format for an emergency alert flowing through the native plumbing.
 *
 * The receiver, the foreground service and the MethodChannel all serialise
 * the same shape, so we keep a single immutable carrier here. Flutter side
 * mirrors this in `lib/core/alert/alert_event.dart`.
 */
data class AlertEvent(
    val id: String,
    val source: String,
    val sender: String?,
    val body: String,
    val receivedAtEpochMs: Long,
    val severity: String,
) {
    fun toMap(state: String = AlertConstants.STATE_PENDING): Map<String, Any?> = mapOf(
        "id" to id,
        "source" to source,
        "sender" to sender,
        "body" to body,
        "receivedAtEpochMs" to receivedAtEpochMs,
        "severity" to severity,
        "state" to state,
    )

    companion object {
        const val SEVERITY_CRITICAL = "critical"
        const val SEVERITY_HIGH = "high"
        const val SEVERITY_MEDIUM = "medium"
        const val SEVERITY_LOW = "low"

        /**
         * Carried on every inbound alert until the FunctionGemma router
         * has had a chance to look at it. The classifier no longer
         * stamps a regex severity, so this is the default — and the
         * native watchdog now defaults to dismiss when the LLM verdict
         * never arrives, so an "unknown" severity never escalates.
         */
        const val SEVERITY_UNKNOWN = "unknown"

        const val SOURCE_SMS = "sms"
        const val SOURCE_CELL_BROADCAST = "cell_broadcast"
        const val SOURCE_SIMULATION = "simulation"
        const val SOURCE_MESH = "mesh"
    }
}
