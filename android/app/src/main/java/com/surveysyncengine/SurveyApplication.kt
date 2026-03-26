package com.surveysyncengine

import android.app.Application
import androidx.room.Room
import androidx.work.Configuration
import androidx.work.WorkManager
import com.surveysyncengine.data.local.db.SurveyDatabase
import com.surveysyncengine.data.platform.AndroidDevicePolicyEvaluator
import com.surveysyncengine.data.remote.api.FakeSurveyApiService
import com.surveysyncengine.data.repository.SurveyRepositoryImpl
import com.surveysyncengine.sync.SyncEngine
import com.surveysyncengine.worker.SyncWorker
import com.surveysyncengine.worker.SyncWorkerFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Application entry point and manual composition root.
 *
 * Constructs and wires every major dependency in the correct order:
 *   1. Room database
 *   2. DAOs (from database)
 *   3. [SurveyRepositoryImpl] (from DAOs)
 *   4. [SyncEngine] (from repository + API service + device policy)
 *   5. [SyncWorkerFactory] (from SyncEngine) → handed to WorkManager
 *   6. [WorkManager.initialize] (must happen before any work is enqueued)
 *   7. [SyncWorker.enqueue] (schedules the periodic background sync)
 *   8. Crash recovery: [SurveyRepositoryImpl.resetStuckInProgress]
 *
 * Register in AndroidManifest.xml:
 * ```xml
 * <application android:name=".SurveyApplication" ... />
 * ```
 *
 * WorkManager's default auto-initializer must also be disabled in the manifest
 * so that [WorkManager.initialize] called here is not rejected as a duplicate:
 * ```xml
 * <provider
 *     android:name="androidx.startup.InitializationProvider"
 *     android:authorities="${applicationId}.androidx-startup"
 *     android:exported="false"
 *     tools:node="remove" />
 * ```
 *
 * If Hilt is added in the future, this class becomes [@HiltAndroidApp] and the
 * construction logic moves to [com.surveysyncengine.di.SyncModule].
 * See di/SyncModule.kt for the equivalent Hilt wiring.
 */
class SurveyApplication : Application() {

    /**
     * Application-scoped coroutine scope for one-off startup work (crash recovery).
     * [SupervisorJob] ensures a failed child coroutine does not cancel the scope.
     * [Dispatchers.IO] keeps database work off the main thread.
     */
    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // ------------------------------------------------------------------
    // Public surface
    //
    // Exposed so Activities, ViewModels, or other entry points can
    // trigger a foreground sync or cancel background work without
    // needing a separate service locator.
    // ------------------------------------------------------------------

    /**
     * The singleton sync engine. Exposed so UI components can call
     * [SyncEngine.sync] directly for a foreground-triggered sync and
     * collect [SyncEngine.progress] for progress reporting.
     *
     * Must remain a singleton — [SyncEngine] owns the [Mutex] that enforces
     * Scenario 4 (concurrent sync prevention). Two instances would each have
     * their own independent mutex, silently breaking the guard.
     */
    lateinit var syncEngine: SyncEngine
        private set

    /**
     * WorkManager instance for cancelling or querying background work.
     * Exposed so callers do not need to call [WorkManager.getInstance] directly,
     * which would bypass the custom [SyncWorkerFactory] if called before init.
     */
    lateinit var workManager: WorkManager
        private set

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    override fun onCreate() {
        super.onCreate()

        // 1. Build the Room database.
        //    fallbackToDestructiveMigration() is intentionally omitted —
        //    losing unsynced survey data during a migration would be unacceptable.
        //    Add explicit Migration objects when the schema changes.
        val database = Room.databaseBuilder(
            applicationContext,
            SurveyDatabase::class.java,
            "survey_db",
        ).build()

        // 2. Construct the repository.
        //    availableStorageProvider reads the data partition's free space —
        //    used by getStorageStats() and getDiagnosticsSnapshot().
        val repository = SurveyRepositoryImpl(
            responseDao              = database.surveyResponseDao(),
            attachmentDao            = database.mediaAttachmentDao(),
            syncLogDao               = database.syncLogDao(),
            availableStorageProvider = { applicationContext.filesDir.freeSpace },
        )

        // 3. Construct the sync engine.
        //    FakeSurveyApiService is used here because the spec requires no real
        //    network calls. Swap for a Retrofit implementation in production.
        syncEngine = SyncEngine(
            repository   = repository,
            apiService   = FakeSurveyApiService(),
            devicePolicy = AndroidDevicePolicyEvaluator(applicationContext),
        )

        // 4. Build SyncWorkerFactory and initialise WorkManager with it.
        //    WorkManager must be initialised BEFORE any WorkRequest is enqueued.
        //    The custom factory is required so WorkManager can inject [SyncEngine]
        //    into [SyncWorker] — without it, WorkManager would try to construct
        //    SyncWorker with a no-arg constructor and crash at runtime.
        val syncWorkerFactory = SyncWorkerFactory(syncEngine)

        WorkManager.initialize(
            applicationContext,
            Configuration.Builder()
                .setWorkerFactory(syncWorkerFactory)
                .build(),
        )

        workManager = WorkManager.getInstance(applicationContext)

        // 5. Schedule the periodic background sync.
        //    enqueue() uses ExistingPeriodicWorkPolicy.KEEP, so calling this on
        //    every app start is safe — it no-ops if the job is already scheduled.
        SyncWorker.enqueue(workManager)

        // 6. Crash recovery.
        //    If the process was killed while a sync was in flight, some responses
        //    will be stuck with status IN_PROGRESS. They would never be picked up
        //    by getPendingResponses() (which only returns PENDING and FAILED).
        //    Resetting them here ensures they are retried on the next sync.
        //    This must run before the first sync attempt fires.
        applicationScope.launch {
            repository.resetStuckInProgress()
        }
    }

    // ------------------------------------------------------------------
    // Public actions
    // ------------------------------------------------------------------

    /**
     * Cancels the scheduled background sync job.
     *
     * Call on user logout, during a data migration, or when background
     * sync should be paused. Safe to call multiple times.
     * Re-schedule with [SyncWorker.enqueue] when ready to resume.
     */
    fun cancelBackgroundSync() {
        SyncWorker.cancel(workManager)
    }
}
