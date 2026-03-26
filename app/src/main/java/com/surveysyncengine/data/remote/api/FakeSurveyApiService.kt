package com.surveysyncengine.data.remote.api

import com.surveysyncengine.domain.error.SurveyHttpException
import com.surveysyncengine.domain.model.SurveyResponse
import kotlinx.coroutines.delay
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger

// ---------------------------------------------------------------------------
// FakeSurveyApiService
//
// Fully configurable mock that covers every scenario in the spec:
//
//  Scenario 2 (partial failure):
//    FakeSurveyApiService(serverErrorOnCallIndices = setOf(5))
//
//  Scenario 3 (network degradation at call 4):
//    FakeSurveyApiService(timeoutOnCallIndices = setOf(3, 4))
//
//  Scenario 5 (all error types):
//    Use FailurePlan with mixed entries.
//
// Call indices are 0-based and global across the service lifetime.
// Call reset() between test cases.
// ---------------------------------------------------------------------------
class FakeSurveyApiService(
    private val failurePlan: List<FailureInstruction> = emptyList(),
    private val simulatedNetworkDelayMs: Long = 10L,
) : SurveyApiService {

    private val callIndex = AtomicInteger(0)

    // Runtime-adjustable delay — lets tests slow the API after construction
    // without rebuilding the failure plan. Used in concurrent sync tests.
    private var runtimeDelayMs: Long? = null
    fun setDelay(ms: Long) { runtimeDelayMs = ms }

    override suspend fun uploadSurveyResponse(response: SurveyResponse): UploadResponseDto {
        delay(runtimeDelayMs ?: simulatedNetworkDelayMs)
        val index = callIndex.getAndIncrement()
        applyFailurePlan(index)
        return UploadResponseDto(
            serverId = "srv-${UUID.randomUUID()}",
            receivedAt = System.currentTimeMillis(),
        )
    }

    override suspend fun uploadAttachment(
        surveyResponseId: String,
        attachmentId: String,
        localFilePath: String,
        mimeType: String,
    ): AttachmentUploadDto {
        delay(simulatedNetworkDelayMs)
        return AttachmentUploadDto(
            attachmentId = attachmentId,
            serverUrl = "https://fake-storage.example.com/$attachmentId",
        )
    }

    private fun applyFailurePlan(index: Int) {
        val instruction = failurePlan.firstOrNull { it.callIndex == index } ?: return
        when (instruction.failureType) {
            FailureType.TIMEOUT -> throw SocketTimeoutException("Simulated timeout at call $index")
            FailureType.NO_NETWORK -> throw UnknownHostException("Simulated no network at call $index")
            FailureType.SERVER_ERROR_500 -> throw SurveyHttpException(500, "Internal Server Error")
            FailureType.SERVER_ERROR_503 -> throw SurveyHttpException(503, "Service Unavailable")
            FailureType.CLIENT_ERROR_400 -> throw SurveyHttpException(400, "Bad Request")
            FailureType.CLIENT_ERROR_422 -> throw SurveyHttpException(422, "Unprocessable Entity")
            FailureType.UNKNOWN -> throw RuntimeException("Simulated unknown error at call $index")
        }
    }

    fun reset() = callIndex.set(0)

    fun callCount(): Int = callIndex.get()
}

// ---------------------------------------------------------------------------
// DSL helpers for building failure plans clearly in tests
// ---------------------------------------------------------------------------
data class FailureInstruction(
    val callIndex: Int,
    val failureType: FailureType,
)

enum class FailureType {
    TIMEOUT,
    NO_NETWORK,
    SERVER_ERROR_500,
    SERVER_ERROR_503,
    CLIENT_ERROR_400,
    CLIENT_ERROR_422,
    UNKNOWN,
}

/** Convenience builder. */
fun failurePlan(vararg pairs: Pair<Int, FailureType>): List<FailureInstruction> =
    pairs.map { (index, type) -> FailureInstruction(index, type) }
