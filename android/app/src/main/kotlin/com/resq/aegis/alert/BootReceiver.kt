package com.resq.aegis.alert

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * No-op on the surface — by simply being registered we keep the SMS receiver
 * alive after a reboot on devices that aggressively kill stopped components.
 *
 * Sprint 6 will extend this to schedule the model warm-up worker and to
 * verify that the foreground service can still post a special-use notification.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.i(TAG, "Boot completed action=${intent.action}, alert pipeline armed")
    }

    companion object {
        private const val TAG = "AegisBootReceiver"
    }
}
