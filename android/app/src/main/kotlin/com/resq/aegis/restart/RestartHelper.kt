package com.resq.aegis.restart

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Process
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.system.exitProcess

/**
 * MethodChannel handler that lets Dart kill the current process and
 * schedule an immediate relaunch. Used by [LlmService] when the Mali
 * GPU OpenCL context wedges after a chat→vision flow on certain
 * Samsung Exynos devices (Note 10 / S10 with Mali-G76 driver). The
 * fragmented OpenCL buffer pool only releases when the process is
 * killed — `litert_lm_engine_delete` alone is insufficient because
 * the OpenCL context is process-level.
 *
 * Sequence:
 *   1. Dart catches `EngineWedgedException`, persists pending intake
 *      (image, audio, transcript, GPS) to local disk.
 *   2. Dart invokes `restartApp` over this channel.
 *   3. We schedule an [AlarmManager] alarm for `now + 200ms` that
 *      relaunches MainActivity.
 *   4. We call `Process.killProcess(myPid())` + `exitProcess(0)` to
 *      tear down the current process (clears OpenCL context).
 *   5. AlarmManager fires → Activity relaunches → Flutter cold-starts
 *      with a fresh OpenCL context → reads the persisted intake →
 *      replays triage.
 */
class RestartHelper(private val context: Context) {

    companion object {
        private const val TAG = "RestartHelper"
        private const val CHANNEL = "com.resq.aegis/restart"
        private const val RESTART_DELAY_MS = 200L
        private const val PENDING_REQUEST_CODE = 0xAE615
    }

    fun attach(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "restartApp" -> {
                    result.success(null)
                    restartProcess(call)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun restartProcess(call: MethodCall) {
        val reason = call.argument<String>("reason") ?: "(unspecified)"
        Log.i(TAG, "restartProcess requested reason=$reason — scheduling relaunch in ${RESTART_DELAY_MS}ms")

        val packageManager = context.packageManager
        val launchIntent = packageManager.getLaunchIntentForPackage(context.packageName)
            ?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                putExtra(EXTRA_RESTARTED_AFTER_WEDGE, true)
            } ?: run {
            Log.e(TAG, "Could not obtain launch intent — cannot restart")
            return
        }

        val pendingFlags = if (android.os.Build.VERSION.SDK_INT >= 23) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            PENDING_REQUEST_CODE,
            launchIntent,
            pendingFlags,
        )

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        if (alarmManager == null) {
            Log.e(TAG, "AlarmManager unavailable — cannot restart")
            return
        }
        val triggerAt = System.currentTimeMillis() + RESTART_DELAY_MS
        alarmManager.set(AlarmManager.RTC, triggerAt, pendingIntent)

        // Kill the process AFTER scheduling the alarm so the new
        // launch fires reliably. `exitProcess` follows to make sure
        // we tear down even if the JVM tries to linger.
        Log.i(TAG, "alarm scheduled — killing pid=${Process.myPid()} now")
        Process.killProcess(Process.myPid())
        exitProcess(0)
    }
}

const val EXTRA_RESTARTED_AFTER_WEDGE = "com.resq.aegis.restarted_after_wedge"
