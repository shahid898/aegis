package com.resq.aegis

import android.app.Application
import android.util.Log
import com.resq.aegis.alert.AegisAlertPlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Eagerly boots a cached [FlutterEngine] at process start so the Dart-side
 * AlertRouter + FunctionRouter are alive even when no Activity is on screen.
 *
 * **Why this is required.** The wake-app pipeline depends on Dart running
 * Gemma 4 IT for the verdict that promotes a PENDING alert to CONFIRMED.
 * Without a cached engine, the only way Dart sees an alert is if the user
 * already has the app open — `AegisAlertPlugin` only attaches when an
 * Activity instantiates a `FlutterEngine`. With the app killed, the Dart
 * side never runs, the native watchdog fires its always-dismiss policy, and
 * the silent PENDING heads-up tears itself down without ever waking the
 * user.
 *
 * **Lifecycle.** When the OS reaps our process for memory pressure, this
 * `Application.onCreate` re-runs the moment any of our manifest receivers
 * fires (`SmsAlertReceiver`, `BootReceiver`). The engine is rebuilt, Dart
 * `main()` runs, `configureDependencies()` registers `AlertRouter`, and
 * the router subscribes to `AlertBridge.alerts` — all before the
 * `AlertForegroundService` calls `notifyDelivered()`.
 *
 * **Single engine.** [MainActivity] reuses this cached engine via
 * `getCachedEngineId()` so we never run two Gemma instances in the same
 * process. The cost is ~50 MB of always-on RAM for the engine plus
 * whatever Dart isolate state DI holds — small relative to the 2 GB Gemma
 * pack itself, which only loads on first inference call.
 */
class AegisApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "AegisApplication.onCreate — booting cached FlutterEngine")
        try {
            val engine = FlutterEngine(this)
            // Plugin registration must precede Dart entrypoint so the
            // MethodChannel is wired before `configureDependencies()`
            // tries to read the pending alert handshake.
            engine.plugins.add(AegisAlertPlugin())
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
            Log.i(TAG, "Cached FlutterEngine ready id=$ENGINE_ID")
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to boot cached FlutterEngine", t)
        }
    }

    companion object {
        private const val TAG = "AegisApplication"
        const val ENGINE_ID = "aegis_main_engine"
    }
}
