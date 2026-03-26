package com.surveysyncengine.sync

// ---------------------------------------------------------------------------
// DevicePolicy — pure Kotlin. No Android imports.
//
// SyncEngine depends on DevicePolicyEvaluator (this file).
// The Android implementation (AndroidDevicePolicyEvaluator) lives in
// data/platform/ where Android framework imports are acceptable.
// ---------------------------------------------------------------------------

data class SyncPolicy(
    val shouldSync: Boolean,
    val skipReason: String? = null,
    /** Per-session upload cap (bytes). null = no cap. Applied on metered networks. */
    val maxBytesPerSession: Long? = null,
    /** Delay between item uploads to reduce battery drain at low charge. */
    val itemDelayMs: Long = 0L,
    val networkType: NetworkType = NetworkType.UNKNOWN,
)

enum class NetworkType { WIFI, METERED_CELLULAR, UNMETERED_CELLULAR, UNKNOWN }

interface DevicePolicyEvaluator {
    fun evaluate(): SyncPolicy
}

// ---------------------------------------------------------------------------
// DefaultDevicePolicyEvaluator — lambda-based, pure Kotlin.
// Used in integration tests and anywhere you want to control individual
// signals without a real Android Context.
// ---------------------------------------------------------------------------
class DefaultDevicePolicyEvaluator(
    private val batteryPercentProvider: () -> Int,
    private val isChargingProvider: () -> Boolean,
    private val availableStorageBytesProvider: () -> Long,
    private val networkTypeProvider: () -> NetworkType,
) : DevicePolicyEvaluator {

    companion object {
        const val MIN_BATTERY_PERCENT  = 15
        const val LOW_BATTERY_PERCENT  = 30
        const val MIN_STORAGE_BYTES    = 50L * 1024 * 1024
        const val METERED_MAX_BYTES    = 10L * 1024 * 1024
        const val LOW_BATTERY_DELAY_MS = 200L
    }

    override fun evaluate(): SyncPolicy {
        val battery     = batteryPercentProvider()
        val charging    = isChargingProvider()
        val storage     = availableStorageBytesProvider()
        val networkType = networkTypeProvider()

        if (battery < MIN_BATTERY_PERCENT && !charging) {
            return SyncPolicy(
                shouldSync = false,
                skipReason = "Battery critically low ($battery%). Sync deferred.",
            )
        }
        if (storage < MIN_STORAGE_BYTES) {
            return SyncPolicy(
                shouldSync = false,
                skipReason = "Device storage critically low (${storage / 1024}KB free).",
            )
        }

        return SyncPolicy(
            shouldSync = true,
            maxBytesPerSession = if (networkType == NetworkType.METERED_CELLULAR) METERED_MAX_BYTES else null,
            itemDelayMs = if (battery < LOW_BATTERY_PERCENT && !charging) LOW_BATTERY_DELAY_MS else 0L,
            networkType = networkType,
        )
    }
}

// ---------------------------------------------------------------------------
// FakeDevicePolicyEvaluator — for unit tests only.
// Kept here (not in test sources) so worker and integration code can also
// use it without test-source scoping issues. Clearly named as a test double.
// ---------------------------------------------------------------------------
class FakeDevicePolicyEvaluator(var policy: SyncPolicy = SyncPolicy(shouldSync = true)) :
    DevicePolicyEvaluator {
    override fun evaluate(): SyncPolicy = policy
}


