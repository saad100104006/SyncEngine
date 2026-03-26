package com.surveysyncengine.data.platform

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Environment
import android.os.StatFs
import com.surveysyncengine.sync.DevicePolicyEvaluator
import com.surveysyncengine.sync.NetworkType
import com.surveysyncengine.sync.SyncPolicy

// ---------------------------------------------------------------------------
// AndroidDevicePolicyEvaluator — lives in data/platform because it imports
// Android framework classes. The sync layer depends only on the
// DevicePolicyEvaluator interface (pure Kotlin, in sync/).
//
// Inject this via Context in Application.onCreate() or your DI graph.
//
// Policy decisions:
//   Battery < 15% and not charging  → skip sync entirely
//   Storage < 50 MB free            → skip sync
//   Metered network (2G/3G)         → cap uploads at 10 MB per session
//   Battery 15–30%, not charging    → add 200 ms delay between items
// ---------------------------------------------------------------------------
class AndroidDevicePolicyEvaluator(private val context: Context) : DevicePolicyEvaluator {

    companion object {
        private const val MIN_BATTERY_PERCENT  = 15
        private const val LOW_BATTERY_PERCENT  = 30
        private const val MIN_STORAGE_BYTES    = 50L * 1024 * 1024
        private const val METERED_MAX_BYTES    = 10L * 1024 * 1024
        private const val LOW_BATTERY_DELAY_MS = 200L
    }

    override fun evaluate(): SyncPolicy {
        val battery     = getBatteryPercent()
        val charging    = isCharging()
        val freeStorage = getFreeStorageBytes()
        val networkType = getNetworkType()

        if (battery < MIN_BATTERY_PERCENT && !charging) {
            return SyncPolicy(
                shouldSync = false,
                skipReason = "Battery critically low ($battery%). Sync deferred until charged.",
            )
        }

        if (freeStorage < MIN_STORAGE_BYTES) {
            return SyncPolicy(
                shouldSync = false,
                skipReason = "Storage critically low (${freeStorage / (1024 * 1024)}MB free).",
            )
        }

        return SyncPolicy(
            shouldSync = true,
            maxBytesPerSession = if (networkType == NetworkType.METERED_CELLULAR) METERED_MAX_BYTES else null,
            itemDelayMs = if (battery < LOW_BATTERY_PERCENT && !charging) LOW_BATTERY_DELAY_MS else 0L,
            networkType = networkType,
        )
    }

    private fun getBatteryPercent(): Int {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        return bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY).coerceIn(0, 100)
    }

    private fun isCharging(): Boolean {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        return bm.isCharging
    }

    private fun getFreeStorageBytes(): Long {
        val stat = StatFs(Environment.getDataDirectory().path)
        return stat.availableBlocksLong * stat.blockSizeLong
    }

    private fun getNetworkType(): NetworkType {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: return NetworkType.UNKNOWN
        val caps    = cm.getNetworkCapabilities(network) ?: return NetworkType.UNKNOWN
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> NetworkType.WIFI
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ->
                if (cm.isActiveNetworkMetered) NetworkType.METERED_CELLULAR
                else NetworkType.UNMETERED_CELLULAR
            else -> NetworkType.UNKNOWN
        }
    }
}
