package com.android.surveysyncengine.sync

import app.cash.turbine.test
import com.android.surveysyncengine.FakeSurveyRepository
import com.android.surveysyncengine.FakeRepositoryAdapter
import com.android.surveysyncengine.TestSyncEngineFactory
import com.android.surveysyncengine.allSucceedApi
import com.android.surveysyncengine.buildResponse
import com.android.surveysyncengine.buildResponseWithFarms
import com.android.surveysyncengine.failAtIndexApi
import com.android.surveysyncengine.lowBatteryPolicy
import com.android.surveysyncengine.noNetworkAtIndexApi
import com.android.surveysyncengine.normalPolicy
import com.android.surveysyncengine.timeoutAtIndexApi
import com.surveysyncengine.data.remote.api.FailureType
import com.surveysyncengine.data.remote.api.FakeSurveyApiService
import com.surveysyncengine.data.remote.api.SurveyApiService
import com.surveysyncengine.data.remote.api.failurePlan
import com.surveysyncengine.domain.error.SyncError
import com.surveysyncengine.domain.model.SyncStatus
import com.surveysyncengine.sync.DevicePolicyEvaluator
import com.surveysyncengine.sync.NetworkErrorClassifier
import com.surveysyncengine.sync.SyncEngine
import com.surveysyncengine.sync.SyncProgress
import com.surveysyncengine.sync.SyncResult
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class SyncEngineTest {

    private lateinit var repo: FakeSurveyRepository

    @Before
    fun setUp() {
        repo = FakeSurveyRepository()
    }

    // ======================================================================
    // Scenario 1: Offline Storage / Empty Queue
    // ======================================================================

    @Test
    fun `sync with empty queue returns NothingToSync`() = runTest {
        val engine = makeEngine(allSucceedApi())

        val result = engine.sync()

        assertTrue(result is SyncResult.NothingToSync)
    }

    @Test
    fun `responses saved offline are retrievable after restart`() = runTest {
        repeat(10) { i ->
            repo.saveResponse(buildResponse(id = "resp-$i"))
        }

        val pending = repo.getPendingResponses()

        assertEquals(10, pending.size)
        pending.forEach { assertEquals(SyncStatus.PENDING, it.status) }
    }

    @Test
    fun `response with repeating farm sections persists all repetitions`() = runTest {
        val response = buildResponseWithFarms(farmCount = 3, responseId = "multi-farm")
        repo.saveResponse(response)

        val loaded = repo.getResponseById("multi-farm")

        assertNotNull(loaded)
        assertEquals(3, loaded!!.sections.size)
        assertEquals(0, loaded.sections[0].repetitionIndex)
        assertEquals(1, loaded.sections[1].repetitionIndex)
        assertEquals(2, loaded.sections[2].repetitionIndex)
        loaded.sections.forEach { assertEquals("farm", it.sectionKey) }
    }

    @Test
    fun `all 10 responses sync successfully`() = runTest {
        repeat(10) { i -> repo.saveResponse(buildResponse(id = "resp-$i")) }
        val engine = makeEngine(allSucceedApi())

        val result = engine.sync()

        assertTrue(result is SyncResult.Completed)
        val completed = result as SyncResult.Completed
        assertEquals(10, completed.succeeded.size)
        assertTrue(completed.failed.isEmpty())
        assertFalse(completed.hasPartialFailure)
    }

    @Test
    fun `all responses are marked SYNCED after successful upload`() = runTest {
        val ids = (0 until 5).map { "resp-$it" }
        ids.forEach { repo.saveResponse(buildResponse(id = it)) }
        val engine = makeEngine(allSucceedApi())

        engine.sync()

        ids.forEach { id ->
            assertEquals(SyncStatus.SYNCED, repo.statusOf(id))
        }
    }

    // ======================================================================
    // Scenario 2: Partial Failure
    // ======================================================================

    @Test
    fun `responses 1-5 succeed and response 6 fails - correct status tracking`() = runTest {
        val ids = (0..7).map { "resp-$it" }
        ids.forEach { repo.saveResponse(buildResponse(id = it)) }
        // Call index 5 (0-based) = response 6 (1-based) fails with server error
        val engine = makeEngine(failAtIndexApi(5, type = FailureType.SERVER_ERROR_500))

        val result = engine.sync() as SyncResult.Completed

        // Responses 0-4 (calls 0-4) succeeded
        (0..4).forEach { i ->
            assertEquals(SyncStatus.SYNCED, repo.statusOf("resp-$i"))
            assertTrue("resp-$i should be in succeeded list", result.succeeded.contains("resp-$i"))
        }

        // Response 5 (call index 5) failed
        assertEquals(SyncStatus.FAILED, repo.statusOf("resp-5"))
        assertEquals(1, result.failed.size)
        assertEquals("resp-5", result.failed[0].responseId)
        assertTrue(result.failed[0].error is SyncError.ServerError)

        // Responses 6-7 (calls 6-7) were attempted and succeeded
        assertEquals(SyncStatus.SYNCED, repo.statusOf("resp-6"))
        assertEquals(SyncStatus.SYNCED, repo.statusOf("resp-7"))
    }

    @Test
    fun `failed responses are not re-uploaded on next sync`() = runTest {
        val ids = (0..4).map { "resp-$it" }
        ids.forEach { repo.saveResponse(buildResponse(id = it)) }
        // First sync: response at index 2 fails
        val firstEngine = makeEngine(failAtIndexApi(2))
        firstEngine.sync()

        // Second sync: all succeed
        val secondEngine = makeEngine(allSucceedApi())
        val result = secondEngine.sync() as SyncResult.Completed

        // Only the 1 failed response should be re-uploaded, not the 4 that succeeded
        assertEquals(1, result.succeeded.size)
        assertEquals("resp-2", result.succeeded[0])
    }

    @Test
    fun `partial failure result reports exactly which responses failed`() = runTest {
        // Responses at call indices 1 and 3 fail
        (0..4).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val engine = makeEngine(failAtIndexApi(1, 3))

        val result = engine.sync() as SyncResult.Completed

        val failedIds = result.failed.map { it.responseId }
        assertEquals(2, failedIds.size)
        assertTrue(failedIds.contains("resp-1"))
        assertTrue(failedIds.contains("resp-3"))

        val succeededIds = result.succeeded
        assertEquals(3, succeededIds.size)
        assertTrue(succeededIds.contains("resp-0"))
        assertTrue(succeededIds.contains("resp-2"))
        assertTrue(succeededIds.contains("resp-4"))
    }

    @Test
    fun `retry count increments on each failed attempt`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-0"))
        val engine1 = makeEngine(failAtIndexApi(0))
        engine1.sync()
        assertEquals(1, repo.retryCountOf("resp-0"))

        val engine2 = makeEngine(failAtIndexApi(0))
        engine2.sync()
        assertEquals(2, repo.retryCountOf("resp-0"))
    }

    @Test
    fun `failure reason is persisted and readable`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-0"))
        val engine = makeEngine(failAtIndexApi(0, type = FailureType.SERVER_ERROR_500))
        engine.sync()

        val reason = repo.failureReasonOf("resp-0")
        assertNotNull(reason)
        assertTrue(reason!!.isNotBlank())
    }

    @Test
    fun `successful upload resets consecutive network failure counter`() = runTest {
        (0..5).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        // Timeout at 1, success at 2, timeout at 3 — not consecutive → should NOT abort
        val engine = makeEngine(
            api = timeoutAtIndexApi(1, 3),
            classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 2),
        )

        val result = engine.sync()

        // Should complete, not terminate early (timeouts were not consecutive)
        assertTrue("Expected Completed but got $result", result is SyncResult.Completed)
    }

    @Test
    fun `early termination preserves remaining responses as PENDING`() = runTest {
        (0..7).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val engine = makeEngine(noNetworkAtIndexApi(2, 3))

        engine.sync()

        // Responses that were never attempted should still be PENDING (not IN_PROGRESS)
        (4..7).forEach { i ->
            assertEquals(
                "resp-$i should remain PENDING after early stop",
                SyncStatus.PENDING,
                repo.statusOf("resp-$i"),
            )
        }
    }

    @Test
    fun `single network failure triggers early termination with default threshold`() = runTest {
        // Spec scenario 3: "the 4th fails with a connection timeout — there are
        // still 6 more responses in the queue." The engine must stop immediately.
        // Default threshold=1 matches this: one timeout → EarlyTermination.
        (0..4).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val engine = makeEngine(timeoutAtIndexApi(2))  // timeout at index 2

        val result = engine.sync()

        assertTrue("Expected EarlyTermination but got $result", result is SyncResult.EarlyTermination)
        val early = result as SyncResult.EarlyTermination
        assertEquals(2, early.succeeded.size)    // resp-0 and resp-1 succeeded
        assertEquals(1, early.failedBeforeStop.size)  // resp-2 timed out
        assertEquals(2, early.remainingCount)    // resp-3 and resp-4 untouched
    }

    @Test
    fun `single network failure does NOT abort when threshold is explicitly raised`() = runTest {
        // Tests that the threshold is configurable — callers can opt in to more
        // resilient behaviour for environments with intermittent but recoverable failures.
        (0..4).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val engine = makeEngine(
            api = timeoutAtIndexApi(2),
            classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 2),
        )

        val result = engine.sync()

        // With threshold=2, one timeout is not enough to abort
        assertTrue("Expected Completed but got $result", result is SyncResult.Completed)
        val completed = result as SyncResult.Completed
        assertEquals(4, completed.succeeded.size)
        assertEquals(1, completed.failed.size)
    }

    // ======================================================================
    // Scenario 4: Concurrent Sync Prevention
    // ======================================================================

    @Test
    fun `second sync returns AlreadyRunning while first is in flight`() = runTest {
        (0..4).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        // Use a slow API so first sync is still in progress when second starts
        val slowApi = allSucceedApi().also { it.setDelay(200L) }
        val engine = makeEngine(slowApi)

        var secondResult: SyncResult? = null
        val job = launch { engine.sync() }  // first sync — runs in background

        // Give it a moment to acquire the lock
        kotlinx.coroutines.delay(50)
        secondResult = engine.sync()        // second sync — should be rejected

        job.join()

        assertEquals(SyncResult.AlreadyRunning, secondResult)
    }

    @Test
    fun `concurrent sync does not duplicate uploads`() = runTest {
        (0..2).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val api = allSucceedApi()
        val engine = makeEngine(api)

        // Launch two syncs simultaneously
        val job1 = launch { engine.sync() }
        val job2 = launch { engine.sync() }
        job1.join()
        job2.join()

        // Each response should be synced exactly once
        assertEquals(3, api.callCount())
        (0..2).forEach { assertEquals(SyncStatus.SYNCED, repo.statusOf("resp-$it")) }
    }

    @Test
    fun `timeout maps to Timeout error`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-0"))
        // Disable threshold so this test observes the error type, not early termination
        val engine = makeEngine(
            api = timeoutAtIndexApi(0),
            classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 99),
        )

        val result = engine.sync() as SyncResult.Completed
        assertTrue(result.failed[0].error is SyncError.Timeout)
    }

    @Test
    fun `server 500 maps to ServerError and is marked retryable`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-0"))
        val engine = makeEngine(failAtIndexApi(0, type = FailureType.SERVER_ERROR_500))

        val result = engine.sync() as SyncResult.Completed
        val error = result.failed[0].error
        assertTrue(error is SyncError.ServerError)
        assertTrue(error.isRetryable())
    }

    @Test
    fun `client 400 maps to ClientError and is NOT retryable`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-0"))
        val engine = makeEngine(failAtIndexApi(0, type = FailureType.CLIENT_ERROR_400))

        val result = engine.sync() as SyncResult.Completed
        val error = result.failed[0].error
        assertTrue(error is SyncError.ClientError)
        assertFalse(error.isRetryable())
    }

    @Test
    fun `client 422 maps to ClientError and is NOT retryable`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-0"))
        val engine = makeEngine(failAtIndexApi(0, type = FailureType.CLIENT_ERROR_422))

        val result = engine.sync() as SyncResult.Completed
        val error = result.failed[0].error
        assertTrue(error is SyncError.ClientError)
        assertFalse(error.isRetryable())
    }

    @Test
    fun `unknown exception maps to Unknown error`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-0"))
        val engine = makeEngine(failAtIndexApi(0, type = FailureType.UNKNOWN))

        val result = engine.sync() as SyncResult.Completed
        assertTrue(result.failed[0].error is SyncError.Unknown)
    }

    @Test
    fun `mixed error types in one sync session are all correctly classified`() = runTest {
        (0..4).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val api = FakeSurveyApiService(
            failurePlan = failurePlan(
                0 to FailureType.NO_NETWORK,
                2 to FailureType.SERVER_ERROR_500,
                4 to FailureType.CLIENT_ERROR_400,
            )
        )
        val engine = makeEngine(
            api = api,
            classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 99), // disable abort
        )

        val result = engine.sync() as SyncResult.Completed

        assertEquals(2, result.succeeded.size)         // resp-1 and resp-3
        assertEquals(3, result.failed.size)

        val errorMap = result.failed.associate { it.responseId to it.error }
        assertTrue(errorMap["resp-0"] is SyncError.NetworkUnavailable)
        assertTrue(errorMap["resp-2"] is SyncError.ServerError)
        assertTrue(errorMap["resp-4"] is SyncError.ClientError)
    }

    // ======================================================================
    // Scenario 5 — retryable vs non-retryable distinction
    // ======================================================================

    @Test
    fun `ClientError 400 marks response DEAD and it is never retried`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-0"))
        val engine = makeEngine(failAtIndexApi(0, type = FailureType.CLIENT_ERROR_400))

        engine.sync()

        // DEAD — not FAILED — so it will not be picked up next sync
        assertEquals(SyncStatus.DEAD, repo.statusOf("resp-0"))

        // Second sync: queue should be empty (DEAD is excluded from getPendingResponses)
        val result = makeEngine(allSucceedApi()).sync()
        assertTrue(result is SyncResult.NothingToSync)
    }

    @Test
    fun `ClientError 422 marks response DEAD`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-0"))
        val engine = makeEngine(failAtIndexApi(0, type = FailureType.CLIENT_ERROR_422))
        engine.sync()
        assertEquals(SyncStatus.DEAD, repo.statusOf("resp-0"))
    }

    @Test
    fun `ServerError 500 marks response FAILED and it IS retried next sync`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-0"))

        // First sync — 500
        val engine1 = makeEngine(failAtIndexApi(0, type = FailureType.SERVER_ERROR_500))
        engine1.sync()
        assertEquals(SyncStatus.FAILED, repo.statusOf("resp-0"))

        // Second sync — server recovers, now succeeds
        val engine2 = makeEngine(allSucceedApi())
        val result = engine2.sync() as SyncResult.Completed
        assertEquals(SyncStatus.SYNCED, repo.statusOf("resp-0"))
        assertEquals(1, result.succeeded.size)
    }

    @Test
    fun `NetworkUnavailable marks response FAILED and it IS retried`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-0"))
        // Disable threshold so this test observes the error type, not early termination
        val engine1 = makeEngine(
            api = noNetworkAtIndexApi(0),
            classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 99),
        )
        engine1.sync()
        assertEquals(SyncStatus.FAILED, repo.statusOf("resp-0"))

        val engine2 = makeEngine(allSucceedApi())
        val result = engine2.sync() as SyncResult.Completed
        assertEquals(1, result.succeeded.size)
    }

    @Test
    fun `DEAD response is excluded from SyncResult failed list on next sync`() = runTest {
        // Mix of dead and retryable failures
        (0..3).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val api = FakeSurveyApiService(
            failurePlan = failurePlan(
                1 to FailureType.CLIENT_ERROR_400,   // will become DEAD
                2 to FailureType.SERVER_ERROR_500,   // will become FAILED — retried next sync
            )
        )
        makeEngine(api).sync()

        assertEquals(SyncStatus.DEAD,   repo.statusOf("resp-1"))
        assertEquals(SyncStatus.FAILED, repo.statusOf("resp-2"))

        // Next sync: only resp-2 (FAILED) should be retried — resp-1 (DEAD) stays dead
        val result = makeEngine(allSucceedApi()).sync() as SyncResult.Completed
        assertEquals(1, result.succeeded.size)
        assertEquals("resp-2", result.succeeded[0])
        assertEquals(SyncStatus.DEAD, repo.statusOf("resp-1")) // still dead
    }

    @Test
    fun `DEAD responses appear in FailedItem list so callers know what happened`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-0"))
        val engine = makeEngine(failAtIndexApi(0, type = FailureType.CLIENT_ERROR_400))

        val result = engine.sync() as SyncResult.Completed

        // Caller can see the failure in the result even though it won't be retried
        assertEquals(1, result.failed.size)
        assertEquals("resp-0", result.failed[0].responseId)
        assertTrue(result.failed[0].error is SyncError.ClientError)
        assertFalse(result.failed[0].error.isRetryable())
    }

    // ======================================================================
    // Bonus: Progress Reporting
    // ======================================================================

    @Test
    fun `progress flow emits Started then per-item events then Finished`() = runTest {
        (0..2).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val engine = makeEngine(allSucceedApi())

        engine.progress.test {
            engine.sync()

            val started = awaitItem() as SyncProgress.Started
            assertEquals(3, started.totalCount)

            repeat(3) { i ->
                val uploading = awaitItem() as SyncProgress.ItemUploading
                assertEquals(i, uploading.index)
                val succeeded = awaitItem() as SyncProgress.ItemSucceeded
                assertEquals(i, succeeded.index)
            }

            val finished = awaitItem() as SyncProgress.Finished
            assertTrue(finished.result is SyncResult.Completed)

            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `progress flow emits ItemFailed for failed uploads`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-0"))
        val engine = makeEngine(failAtIndexApi(0, type = FailureType.SERVER_ERROR_500))

        engine.progress.test {
            engine.sync()

            awaitItem() // Started
            awaitItem() // ItemUploading
            val failed = awaitItem() as SyncProgress.ItemFailed
            assertEquals("resp-0", failed.responseId)
            assertTrue(failed.error is SyncError.ServerError)
            awaitItem() // Finished

            cancelAndIgnoreRemainingEvents()
        }
    }

    // ======================================================================
    // Bonus: Device-aware policy
    // ======================================================================

    @Test
    fun `sync skipped when battery is critically low`() = runTest {
        (0..3).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val engine = makeEngine(allSucceedApi(), devicePolicy = lowBatteryPolicy())

        val result = engine.sync()

        assertTrue(result is SyncResult.SkippedByPolicy)
        val skipped = result as SyncResult.SkippedByPolicy
        assertTrue(skipped.reason.contains("Battery"))
        // No responses should have been touched
        (0..3).forEach { assertEquals(SyncStatus.PENDING, repo.statusOf("resp-$it")) }
    }

    // ======================================================================
    // Scenario 1 — storage growth: pruning is called automatically each sync
    // ======================================================================

    @Test
    fun `pruneUploadedMedia is called before every sync session`() = runTest {
        var pruneMediaCalled = false
        var pruneRecordsCalled = false

        // Use a spy repository that records pruning calls
        val spyRepo = object : FakeSurveyRepository() {
            override suspend fun pruneUploadedMedia(olderThanMs: Long): Long {
                pruneMediaCalled = true
                return 0L
            }
            override suspend fun pruneSyncedResponses(olderThanMs: Long): Int {
                pruneRecordsCalled = true
                return 0
            }
        }
        repo.saveResponse(buildResponse(id = "resp-0"))

        // Replace repo with spy — need to build engine manually
        val engine = SyncEngine(
            repository = FakeRepositoryAdapter(spyRepo),
            apiService = allSucceedApi(),
        )
        engine.sync()

        assertTrue("pruneUploadedMedia should be called on every sync", pruneMediaCalled)
        assertTrue("pruneSyncedResponses should be called on every sync", pruneRecordsCalled)
    }

    @Test
    fun `pruning is called even when sync ends in EarlyTermination`() = runTest {
        var pruneMediaCalled = false

        val spyRepo = object : FakeSurveyRepository() {
            override suspend fun pruneUploadedMedia(olderThanMs: Long): Long {
                pruneMediaCalled = true
                return 0L
            }
        }
        repeat(5) { spyRepo.saveResponse(buildResponse(id = "resp-$it")) }

        val engine = SyncEngine(
            repository = FakeRepositoryAdapter(spyRepo),
            apiService = timeoutAtIndexApi(0),
        )
        val result = engine.sync()

        assertTrue(result is SyncResult.EarlyTermination)
        assertTrue("pruneUploadedMedia must run even when session aborts early", pruneMediaCalled)
    }

    @Test
    fun `pruning failure does not abort the sync session`() = runTest {
        val crashingRepo = object : FakeSurveyRepository() {
            override suspend fun pruneUploadedMedia(olderThanMs: Long): Long =
                throw RuntimeException("Disk I/O error during pruning")
        }
        crashingRepo.saveResponse(buildResponse(id = "resp-0"))

        val engine = SyncEngine(
            repository = FakeRepositoryAdapter(crashingRepo),
            apiService = allSucceedApi(),
        )

        // Should complete successfully despite pruning crash
        val result = engine.sync()
        assertTrue("Sync should complete even when pruning throws", result is SyncResult.Completed)
        assertEquals(SyncStatus.SYNCED, crashingRepo.statusOf("resp-0"))
    }

    // ======================================================================
    // Crash recovery
    // ======================================================================

    @Test
    fun `IN_PROGRESS responses reset to PENDING on recovery`() = runTest {
        // Simulate a crash mid-sync: response stuck in IN_PROGRESS
        repo.saveResponse(buildResponse(id = "resp-stuck", status = SyncStatus.PENDING))
        repo.markInProgress("resp-stuck")
        assertEquals(SyncStatus.IN_PROGRESS, repo.statusOf("resp-stuck"))

        // App restarts — reset
        repo.resetStuckInProgress()

        assertEquals(SyncStatus.PENDING, repo.statusOf("resp-stuck"))
    }

    @Test
    fun `stuck responses are re-synced after recovery`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-stuck"))
        repo.markInProgress("resp-stuck")
        repo.resetStuckInProgress()

        val engine = makeEngine(allSucceedApi())
        val result = engine.sync() as SyncResult.Completed

        assertEquals(1, result.succeeded.size)
        assertEquals("resp-stuck", result.succeeded[0])
    }

    // ======================================================================
    // Helpers
    // ======================================================================

    private fun makeEngine(
        api: SurveyApiService,
        devicePolicy: DevicePolicyEvaluator = normalPolicy(),
        classifier: NetworkErrorClassifier = NetworkErrorClassifier(consecutiveFailureThreshold = 1),
    ) = TestSyncEngineFactory.create(repo, api, devicePolicy, classifier)
}
