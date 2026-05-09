package com.resq.aegis

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.util.Log
import com.resq.aegis.alert.AegisAlertPlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import java.lang.ref.WeakReference

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
 *
 * **Activity tracking.** We track the foreground [Activity] via
 * [registerActivityLifecycleCallbacks] so [AegisAlertPlugin] can call
 * `finishAndRemoveTask()` on it without needing an `ActivityAware`
 * binding (which the cached-engine pattern doesn't deliver). That lets
 * the Dart side ask Kotlin to remove the app from recents after firing
 * a simulate so the GPU is freed for Gemma.
 */
class AegisApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "AegisApplication.onCreate — booting cached FlutterEngine")
        registerActivityLifecycleCallbacks(ActivityTracker())
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

    /**
     * Updates [foregroundActivity] on every Activity lifecycle event so the
     * latest visible Activity is always reachable from anywhere in the
     * process. We deliberately store a [WeakReference] so we don't pin
     * destroyed Activities and leak their View tree.
     */
    private class ActivityTracker : ActivityLifecycleCallbacks {
        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
        override fun onActivityStarted(activity: Activity) {
            foregroundActivity = WeakReference(activity)
        }
        override fun onActivityResumed(activity: Activity) {
            foregroundActivity = WeakReference(activity)
        }
        override fun onActivityPaused(activity: Activity) = Unit
        override fun onActivityStopped(activity: Activity) {
            if (foregroundActivity?.get() === activity) foregroundActivity = null
        }
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
        override fun onActivityDestroyed(activity: Activity) {
            if (foregroundActivity?.get() === activity) foregroundActivity = null
        }
    }

    companion object {
        private const val TAG = "AegisApplication"
        const val ENGINE_ID = "aegis_main_engine"

        /**
         * Latest started/resumed [Activity] in the app's process, or null
         * if no Activity is currently in the foreground. Read from
         * [AegisAlertPlugin] when Dart asks for `finishAndRemoveTask`.
         */
        @Volatile
        var foregroundActivity: WeakReference<Activity>? = null
    }
}
