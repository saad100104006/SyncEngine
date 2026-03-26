package com.android.surveysyncengine

import com.surveysyncengine.domain.repository.SurveyRepository
import com.surveysyncengine.domain.model.StorageStats
import com.surveysyncengine.domain.model.SurveyResponse
import com.surveysyncengine.domain.model.SyncStatus
import com.surveysyncengine.domain.api.SurveyApiService
import com.surveysyncengine.domain.model.DiagnosticsSnapshot
import com.surveysyncengine.sync.DevicePolicyEvaluator
import com.surveysyncengine.sync.FakeDevicePolicyEvaluator
import com.surveysyncengine.sync.NetworkErrorClassifier
import com.surveysyncengine.sync.SyncEngine
import com.surveysyncengine.sync.SyncPolicy
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.sync.Mutex

/**
 * Creates a [SyncEngine] backed entirely by fakes.
 * Uses a fresh [Mutex] per call so tests are fully isolated.
 */
object TestSyncEngineFactory {

    fun create(
        repo: FakeSurveyRepository,
        api: SurveyApiService,
        devicePolicy: DevicePolicyEvaluator = FakeDevicePolicyEvaluator(SyncPolicy(shouldSync = true)),
        classifier: NetworkErrorClassifier = NetworkErrorClassifier(consecutiveFailureThreshold = 2),
    ): SyncEngine = SyncEngine(
        repository      = FakeRepositoryAdapter(repo),
        apiService      = api,
        devicePolicy    = devicePolicy,
        errorClassifier = classifier,
        mutex           = Mutex(),
    )
}

// ---------------------------------------------------------------------------
// FakeRepositoryAdapter
//
// Implements SurveyRepository (domain interface) directly and delegates to
// FakeSurveyRepository. No concrete class extension, no TODO() DAOs.
//
// This was only possible after fixing V1: SyncEngine now depends on
// SurveyRepository (interface) not SurveyRepositoryImpl (concrete class).
// ---------------------------------------------------------------------------
class FakeRepositoryAdapter(
    private val fake: FakeSurveyRepository,
) : SurveyRepository {

    override suspend fun saveResponse(response: SurveyResponse) =
        fake.saveResponse(response)

    override suspend fun markInProgress(responseId: String) =
        fake.markInProgress(responseId)

    override suspend fun markSynced(responseId: String, syncedAt: Long) =
        fake.markSynced(responseId, syncedAt)

    override suspend fun markFailed(responseId: String, reason: String, retryCount: Int) =
        fake.markFailed(responseId, reason, retryCount)

    override suspend fun markDead(responseId: String, reason: String) =
        fake.markDead(responseId, reason)

    override suspend fun resetStuckInProgress() =
        fake.resetStuckInProgress()

    override suspend fun markAttachmentUploaded(attachmentId: String, serverUrl: String) =
        fake.markAttachmentUploaded(attachmentId, serverUrl)

    override suspend fun markAttachmentFailed(attachmentId: String) =
        fake.markAttachmentFailed(attachmentId)

    override suspend fun getPendingResponses() =
        fake.getPendingResponses()

    override suspend fun getResponseById(id: String) =
        fake.getResponseById(id)

    override fun observeAllResponses(): Flow<List<SurveyResponse>> =
        fake.observeAllResponses()

    override fun observeByStatus(status: SyncStatus): Flow<List<SurveyResponse>> =
        fake.observeByStatus(status)

    override suspend fun getStorageStats(): StorageStats =
        fake.getStorageStats()

    override suspend fun pruneUploadedMedia(olderThanMs: Long) =
        fake.pruneUploadedMedia(olderThanMs)

    override suspend fun pruneSyncedResponses(olderThanMs: Long) =
        fake.pruneSyncedResponses(olderThanMs)

    override suspend fun getDiagnosticsSnapshot(): DiagnosticsSnapshot =
        fake.getDiagnosticsSnapshot()

    override suspend fun logSyncEvent(
        sessionId: String,
        responseId: String?,
        event: String,
        detail: String?,
    ) = fake.logSyncEvent(sessionId, responseId, event, detail)
}
