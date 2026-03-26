package com.android.surveysyncengine.sync

import com.android.surveysyncengine.FakeSurveyRepository
import com.android.surveysyncengine.TestSyncEngineFactory
import com.android.surveysyncengine.allSucceedApi
import com.android.surveysyncengine.buildResponse
import com.android.surveysyncengine.noNetworkAtIndexApi
import com.android.surveysyncengine.timeoutAtIndexApi
import com.surveysyncengine.data.remote.api.FailureType
import com.surveysyncengine.data.remote.api.FakeSurveyApiService
import com.surveysyncengine.data.remote.api.failurePlan
import com.surveysyncengine.domain.model.SyncStatus
import com.surveysyncengine.sync.NetworkErrorClassifier
import com.surveysyncengine.sync.SyncResult
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Fine-grained tests for early-termination logic across various classifier
 * threshold configurations and failure patterns.
 */
class NetworkDegradationTest {

    private lateinit var repo: FakeSurveyRepository

    @Before
    fun setUp() {
        repo = FakeSurveyRepository()
    }

    @Test
    fun `threshold of 1 stops at first network failure`() = runTest {
        (0..4).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val engine = TestSyncEngineFactory.create(
            repo = repo,
            api = timeoutAtIndexApi(2),
            classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 1),
        )

        val result = engine.sync() as SyncResult.EarlyTermination

        assertEquals(2, result.succeeded.size)          // resp-0 and resp-1
        assertEquals(1, result.failedBeforeStop.size)   // resp-2
        assertEquals(2, result.remainingCount)          // resp-3 and resp-4
    }

    @Test
    fun `threshold of 3 allows two consecutive failures before stopping`() = runTest {
        (0..9).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        // Two consecutive timeouts at indices 4 and 5 — should NOT stop (threshold=3)
        // Third timeout at index 6 — should stop
        val engine = TestSyncEngineFactory.create(
            repo = repo,
            api = timeoutAtIndexApi(4, 5, 6),
            classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 3),
        )

        val result = engine.sync() as SyncResult.EarlyTermination

        assertEquals(4, result.succeeded.size)          // resp 0-3
        assertEquals(3, result.failedBeforeStop.size)   // resp 4-6
        assertEquals(3, result.remainingCount)          // resp 7-9
    }

    @Test
    fun `no-network error triggers early stop same as timeout`() = runTest {
        (0..5).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val engine = TestSyncEngineFactory.create(
            repo = repo,
            api = noNetworkAtIndexApi(1, 2),
            classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 2),
        )

        val result = engine.sync()
        assertTrue(result is SyncResult.EarlyTermination)
    }

    @Test
    fun `remaining responses are not touched after early stop`() = runTest {
        (0..7).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val engine = TestSyncEngineFactory.create(
            repo = repo,
            api = timeoutAtIndexApi(2, 3),
        )

        engine.sync()

        // Responses 4-7 should be PENDING — not attempted
        (4..7).forEach { i ->
            assertEquals(SyncStatus.PENDING, repo.statusOf("resp-$i"))
        }
        // Response 2 and 3 should be FAILED
        assertEquals(SyncStatus.FAILED, repo.statusOf("resp-2"))
        assertEquals(SyncStatus.FAILED, repo.statusOf("resp-3"))
        // Responses 0 and 1 should be SYNCED
        assertEquals(SyncStatus.SYNCED, repo.statusOf("resp-0"))
        assertEquals(SyncStatus.SYNCED, repo.statusOf("resp-1"))
    }

    @Test
    fun `early termination on second sync after network recovers processes remaining`() = runTest {
        (0..5).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }

        // First sync: stops after resp-1 and resp-2 timeout
        val engine1 = TestSyncEngineFactory.create(
            repo = repo,
            api = timeoutAtIndexApi(1, 2),
        )
        engine1.sync()

        // Network recovers — second sync should process remaining items
        val engine2 = TestSyncEngineFactory.create(
            repo = repo,
            api = allSucceedApi(),
        )
        val result = engine2.sync() as SyncResult.Completed

        // Should retry resp-1 and resp-2 (FAILED) plus resp-3,4,5 (PENDING)
        assertEquals(5, result.succeeded.size)
        assertTrue(result.failed.isEmpty())
    }

    @Test
    fun `server errors interspersed with network errors do not accelerate abort`() = runTest {
        (0..8).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }

        // Pattern: network, server, network — not 2 consecutive network
        val engine = TestSyncEngineFactory.create(
            repo = repo,
            api = FakeSurveyApiService(
                failurePlan = failurePlan(
                    1 to FailureType.TIMEOUT,
                    2 to FailureType.SERVER_ERROR_500,
                    3 to FailureType.NO_NETWORK,
                )
            ),
            classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 2),
        )

        // Should NOT abort early — the server error broke the consecutive chain
        val result = engine.sync()
        assertTrue("Expected Completed but got $result", result is SyncResult.Completed)
    }
}
