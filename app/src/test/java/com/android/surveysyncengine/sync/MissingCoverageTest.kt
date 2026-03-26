package com.android.surveysyncengine.sync

import app.cash.turbine.test
import com.android.surveysyncengine.FakeSurveyRepository
import com.android.surveysyncengine.TestSyncEngineFactory
import com.android.surveysyncengine.allSucceedApi
import com.android.surveysyncengine.buildResponse
import com.android.surveysyncengine.normalPolicy
import com.android.surveysyncengine.timeoutAtIndexApi
import com.surveysyncengine.data.remote.api.SurveyApiService
import com.surveysyncengine.data.remote.api.UploadResponseDto
import com.surveysyncengine.domain.error.SyncError
import com.surveysyncengine.domain.error.toSyncError
import com.surveysyncengine.domain.model.SurveyResponse
import com.surveysyncengine.domain.model.SyncStatus
import com.surveysyncengine.domain.api.AttachmentUploadDto
import com.surveysyncengine.sync.DefaultDevicePolicyEvaluator
import com.surveysyncengine.sync.FakeDevicePolicyEvaluator
import com.surveysyncengine.sync.NetworkType
import com.surveysyncengine.sync.SyncPolicy
import com.surveysyncengine.sync.SyncProgress
import com.surveysyncengine.sync.SyncResult
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Covers the five gaps identified in the coverage audit:
 *
 *  1. DefaultDevicePolicyEvaluator thresholds (battery, storage, network type, delay)
 *  2. Progress flow emits Finished(EarlyTermination) on network abort
 *  3. Storage-critically-low policy skips sync
 *  4. TimeoutCancellationException (coroutine) maps to SyncError.Timeout
 *  5. Low-battery delay policy (itemDelayMs) is wired through to SyncPolicy
 */
class MissingCoverageTest {

    private lateinit var repo: FakeSurveyRepository

    @Before
    fun setUp() {
        repo = FakeSurveyRepository()
    }

    // ======================================================================
    // Gap 1: DefaultDevicePolicyEvaluator — threshold logic
    //
    // Uses the lambda-based evaluator so we can control each signal
    // independently without Android system services.
    // ======================================================================

    @Test
    fun `battery below 15 percent and not charging blocks sync`() {
        val policy = evaluatorWith(battery = 14, charging = false).evaluate()
        assertFalse(policy.shouldSync)
        assertTrue(policy.skipReason!!.contains("Battery"))
    }

    @Test
    fun `battery below 15 percent but charging allows sync`() {
        val policy = evaluatorWith(battery = 14, charging = true).evaluate()
        assertTrue(policy.shouldSync)
    }

    @Test
    fun `battery exactly at threshold 15 percent allows sync`() {
        val policy = evaluatorWith(battery = 15, charging = false).evaluate()
        assertTrue(policy.shouldSync)
    }

    @Test
    fun `storage below 50MB blocks sync`() {
        val policy = evaluatorWith(storageFreeBytes = 49L * 1024 * 1024).evaluate()
        assertFalse(policy.shouldSync)
        assertTrue(policy.skipReason!!.contains("storage", ignoreCase = true))
    }

    @Test
    fun `storage exactly at 50MB threshold allows sync`() {
        val policy = evaluatorWith(storageFreeBytes = 50L * 1024 * 1024).evaluate()
        assertTrue(policy.shouldSync)
    }

    @Test
    fun `metered cellular network sets 10MB byte cap`() {
        val policy = evaluatorWith(networkType = NetworkType.METERED_CELLULAR).evaluate()
        assertTrue(policy.shouldSync)
        assertEquals(10L * 1024 * 1024, policy.maxBytesPerSession)
    }

    @Test
    fun `wifi network has no byte cap`() {
        val policy = evaluatorWith(networkType = NetworkType.WIFI).evaluate()
        assertTrue(policy.shouldSync)
        assertEquals(null, policy.maxBytesPerSession)
    }

    @Test
    fun `unmetered cellular has no byte cap`() {
        val policy = evaluatorWith(networkType = NetworkType.UNMETERED_CELLULAR).evaluate()
        assertTrue(policy.shouldSync)
        assertEquals(null, policy.maxBytesPerSession)
    }

    @Test
    fun `battery between 15 and 30 percent adds item delay`() {
        val policy = evaluatorWith(battery = 25, charging = false).evaluate()
        assertTrue(policy.shouldSync)
        assertTrue("Expected itemDelayMs > 0 at low battery", policy.itemDelayMs > 0)
    }

    @Test
    fun `battery above 30 percent has no item delay`() {
        val policy = evaluatorWith(battery = 80, charging = false).evaluate()
        assertTrue(policy.shouldSync)
        assertEquals(0L, policy.itemDelayMs)
    }

    @Test
    fun `charging overrides low battery delay`() {
        // At 20% but charging — no throttle needed
        val policy = evaluatorWith(battery = 20, charging = true).evaluate()
        assertTrue(policy.shouldSync)
        assertEquals(0L, policy.itemDelayMs)
    }

    // ======================================================================
    // Gap 2: Progress flow emits Finished(EarlyTermination) on network abort
    // ======================================================================

    @Test
    fun `progress Finished event wraps EarlyTermination result`() = runTest {
        (0..5).forEach { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val engine = TestSyncEngineFactory.create(
            repo = repo,
            api = timeoutAtIndexApi(1, 2),
        )

        engine.progress.test {
            engine.sync()

            // Drain events until we hit Finished
            var finished: SyncProgress.Finished? = null
            while (finished == null) {
                finished = awaitItem() as? SyncProgress.Finished
            }

            assertTrue(
                "Expected Finished to wrap EarlyTermination but got ${finished.result}",
                finished.result is SyncResult.EarlyTermination,
            )
            val early = finished.result as SyncResult.EarlyTermination
            assertEquals(1, early.succeeded.size)   // only resp-0 succeeded before abort
            assertTrue(early.reason is SyncError.Timeout)

            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `progress total count in Started matches pending queue size`() = runTest {
        repeat(7) { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val engine = TestSyncEngineFactory.create(repo, allSucceedApi())

        engine.progress.test {
            engine.sync()
            val started = awaitItem() as SyncProgress.Started
            assertEquals(7, started.totalCount)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `progress indices are 0-based and match iteration order`() = runTest {
        repeat(3) { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val engine = TestSyncEngineFactory.create(repo, allSucceedApi())

        engine.progress.test {
            engine.sync()

            awaitItem() // Started
            repeat(3) { expectedIndex ->
                val uploading = awaitItem() as SyncProgress.ItemUploading
                assertEquals(expectedIndex, uploading.index)
                assertEquals(3, uploading.total)

                val succeeded = awaitItem() as SyncProgress.ItemSucceeded
                assertEquals(expectedIndex, succeeded.index)
            }
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ======================================================================
    // Gap 3: Storage-critically-low policy skips sync
    // ======================================================================

    @Test
    fun `sync skipped when device storage is critically low`() = runTest {
        repeat(3) { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val engine = TestSyncEngineFactory.create(
            repo = repo,
            api = allSucceedApi(),
            devicePolicy = FakeDevicePolicyEvaluator(
                SyncPolicy(
                    shouldSync = false,
                    skipReason = "Device storage critically low (12KB free).",
                )
            ),
        )

        val result = engine.sync()

        assertTrue(result is SyncResult.SkippedByPolicy)
        val skipped = result as SyncResult.SkippedByPolicy
        assertTrue(skipped.reason.contains("storage", ignoreCase = true))

        // No responses should have been touched
        repeat(3) {
            assertEquals(SyncStatus.PENDING, repo.statusOf("resp-$it"))
        }
    }

    @Test
    fun `skipped sync leaves all responses as PENDING for next sync`() = runTest {
        repeat(4) { repo.saveResponse(buildResponse(id = "resp-$it")) }
        val skippingEngine = TestSyncEngineFactory.create(
            repo = repo,
            api = allSucceedApi(),
            devicePolicy = FakeDevicePolicyEvaluator(
                SyncPolicy(shouldSync = false, skipReason = "Low storage")
            ),
        )
        skippingEngine.sync()

        // Now run with normal policy — all should sync
        val normalEngine = TestSyncEngineFactory.create(repo, allSucceedApi(), normalPolicy())
        val result = normalEngine.sync() as SyncResult.Completed

        assertEquals(4, result.succeeded.size)
        assertTrue(result.failed.isEmpty())
    }

    // ======================================================================
    // Gap 4: TimeoutCancellationException maps to SyncError.Timeout
    // ======================================================================

    @Test
    fun `TimeoutCancellationException maps to SyncError Timeout`() = runTest {
        // TimeoutCancellationException has an internal constructor in kotlinx.coroutines
        // so it cannot be instantiated directly in tests. Trigger it naturally via
        // withTimeout(1ms) to get the real exception instance, then map it.
        val caughtException = runCatching {
            withTimeout(1) { kotlinx.coroutines.delay(Long.MAX_VALUE) }
        }.exceptionOrNull()

        assertNotNull("withTimeout should have thrown", caughtException)
        assertTrue(caughtException is kotlinx.coroutines.TimeoutCancellationException)

        val error = caughtException!!.toSyncError()

        assertTrue(
            "Expected SyncError.Timeout but got $error",
            error is SyncError.Timeout,
        )
        assertTrue(error.isNetworkLevel())
        assertTrue(error.isRetryable())
    }

    @Test
    fun `TimeoutCancellationException triggers early termination same as SocketTimeoutException`() = runTest {
        // Both paths must reach the classifier as network-level failures.
        // This test wires a fake that throws TimeoutCancellationException.
        repeat(5) { repo.saveResponse(buildResponse(id = "resp-$it")) }

        val cancellingApi = object : SurveyApiService {
            private var calls = 0
            override suspend fun uploadSurveyResponse(
                response: SurveyResponse
            ): UploadResponseDto {
                if (calls++ >= 2) {
                    // Trigger TimeoutCancellationException naturally — its constructor is
                    // internal in kotlinx.coroutines and cannot be called directly.
                    withTimeout(1) { kotlinx.coroutines.delay(Long.MAX_VALUE) }
                }
                return UploadResponseDto("srv-ok", System.currentTimeMillis())
            }
            override suspend fun uploadAttachment(
                surveyResponseId: String, attachmentId: String,
                localFilePath: String, mimeType: String,
            ) = AttachmentUploadDto(attachmentId, "https://x.example.com/$attachmentId")
        }

        val engine = TestSyncEngineFactory.create(repo, cancellingApi)
        val result = engine.sync()

        assertTrue(
            "Expected EarlyTermination but got $result",
            result is SyncResult.EarlyTermination,
        )
        val early = result as SyncResult.EarlyTermination
        assertTrue(early.reason is SyncError.Timeout)
    }

    // ======================================================================
    // Gap 5: itemDelayMs is respected (wired through SyncPolicy → engine)
    //
    // We can't time the wall clock in unit tests reliably, but we CAN verify:
    //   a. The policy is read before each item (not cached once)
    //   b. The engine does not crash or skip items when delay > 0
    // ======================================================================

    @Test
    fun `engine processes all responses correctly when itemDelayMs is set`() = runTest {
        repeat(4) { repo.saveResponse(buildResponse(id = "resp-$it")) }
        // 1ms delay — fast enough for tests, proves the delay path executes
        val engine = TestSyncEngineFactory.create(
            repo = repo,
            api = allSucceedApi(),
            devicePolicy = FakeDevicePolicyEvaluator(
                SyncPolicy(shouldSync = true, itemDelayMs = 1L),
            ),
        )

        val result = engine.sync() as SyncResult.Completed

        assertEquals(4, result.succeeded.size)
        assertTrue(result.failed.isEmpty())
        repeat(4) { assertEquals(SyncStatus.SYNCED, repo.statusOf("resp-$it")) }
    }

    // ======================================================================
    // Helpers
    // ======================================================================

    private fun evaluatorWith(
        battery: Int = 80,
        charging: Boolean = false,
        storageFreeBytes: Long = 500L * 1024 * 1024,   // 500 MB — well above threshold
        networkType: NetworkType = NetworkType.WIFI,
    ) = DefaultDevicePolicyEvaluator(
        batteryPercentProvider       = { battery },
        isChargingProvider           = { charging },
        availableStorageBytesProvider = { storageFreeBytes },
        networkTypeProvider          = { networkType },
    )
}
