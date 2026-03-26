package com.surveysyncengine.worker

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ListenableWorker
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.surveysyncengine.sync.SyncEngine
import com.surveysyncengine.sync.SyncResult
import java.util.concurrent.TimeUnit

// ---------------------------------------------------------------------------
// SyncWorker — WorkManager integration for background sync.
//
// Constraints:
//   • Requires any network connection (WorkManager handles connectivity gate)
//   • Does NOT require charging — field agents rarely have access to power
//   • Periodic: every 15 minutes (WorkManager minimum)
//
// The worker itself is intentionally thin — all sync logic lives in SyncEngine.
// ---------------------------------------------------------------------------
class SyncWorker(
    context: Context,
    params: WorkerParameters,
    private val syncEngine: SyncEngine,     // injected via SyncWorkerFactory
) : CoroutineWorker(context, params) {

    companion object {
        const val WORK_NAME             = "survey_background_sync"
        const val KEY_RESULT_TYPE       = "result_type"
        const val KEY_SUCCEEDED_COUNT   = "succeeded_count"
        const val KEY_FAILED_COUNT      = "failed_count"
        const val KEY_SKIP_REASON       = "skip_reason"

        /**
         * Enqueue a periodic background sync.
         * Safe to call multiple times — KEEP policy leaves existing work untouched.
         */
        fun enqueue(workManager: WorkManager) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val request = PeriodicWorkRequestBuilder<SyncWorker>(
                repeatInterval = 15,
                repeatIntervalTimeUnit = TimeUnit.MINUTES,
            )
                .setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()

            workManager.enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }

        /** Cancel the periodic sync (e.g., on user logout). */
        fun cancel(workManager: WorkManager) {
            workManager.cancelUniqueWork(WORK_NAME)
        }
    }

    override suspend fun doWork(): Result {
        return when (val result = syncEngine.sync()) {
            is SyncResult.Completed -> Result.success(
                workDataOf(
                    KEY_RESULT_TYPE     to "COMPLETED",
                    KEY_SUCCEEDED_COUNT to result.succeeded.size,
                    KEY_FAILED_COUNT    to result.failed.size,
                )
            )

            is SyncResult.EarlyTermination ->
                // Network likely down — let WorkManager retry with backoff
                Result.retry()

            is SyncResult.AlreadyRunning ->
                // Foreground sync is running — exit cleanly, no duplication
                Result.success(workDataOf(KEY_RESULT_TYPE to "ALREADY_RUNNING"))

            is SyncResult.NothingToSync ->
                Result.success(workDataOf(KEY_RESULT_TYPE to "NOTHING_TO_SYNC"))

            is SyncResult.SkippedByPolicy -> Result.success(
                workDataOf(
                    KEY_RESULT_TYPE to "SKIPPED",
                    KEY_SKIP_REASON to result.reason,
                )
            )
        }
    }
}

// ---------------------------------------------------------------------------
// SyncWorkerFactory — injects SyncEngine into SyncWorker.
//
// Register in Application.onCreate():
//
//   val config = Configuration.Builder()
//       .setWorkerFactory(SyncWorkerFactory(syncEngine))
//       .build()
//   WorkManager.initialize(this, config)
//
// Also add to AndroidManifest.xml to disable default initializer:
//   <provider
//       android:name="androidx.startup.InitializationProvider"
//       tools:node="remove" />
// ---------------------------------------------------------------------------

class SyncWorkerFactory(
    private val syncEngine: SyncEngine,
) : WorkerFactory() {

    override fun createWorker(
        appContext: Context,
        workerClassName: String,
        workerParameters: WorkerParameters,
    ): ListenableWorker? {
        return if (workerClassName == SyncWorker::class.java.name) {
            SyncWorker(appContext, workerParameters, syncEngine)
        } else {
            // Return null to fall back to the default factory for other workers
            null
        }
    }
}
