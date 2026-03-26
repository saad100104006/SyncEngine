package com.android.surveysyncengine

import com.surveysyncengine.data.remote.api.FailureInstruction
import com.surveysyncengine.data.remote.api.FailureType
import com.surveysyncengine.data.remote.api.FakeSurveyApiService
import com.surveysyncengine.domain.model.AnswerValue
import com.surveysyncengine.domain.model.FarmSectionKeys
import com.surveysyncengine.domain.model.GpsPoint
import com.surveysyncengine.domain.model.MediaAttachment
import com.surveysyncengine.domain.model.ResponseSection
import com.surveysyncengine.domain.model.SurveyResponse
import com.surveysyncengine.domain.model.SyncStatus
import com.surveysyncengine.domain.model.UploadStatus
import com.surveysyncengine.sync.FakeDevicePolicyEvaluator
import com.surveysyncengine.sync.NetworkType
import com.surveysyncengine.sync.SyncPolicy


// ---------------------------------------------------------------------------
// Builders — create test data with sensible defaults, override as needed
// ---------------------------------------------------------------------------

fun buildResponse(
    id: String = "resp-${System.nanoTime()}",
    farmerId: String = "farmer-1",
    surveyId: String = "survey-1",
    status: SyncStatus = SyncStatus.PENDING,
    sections: List<ResponseSection> = emptyList(),
    attachments: List<MediaAttachment> = emptyList(),
    retryCount: Int = 0,
    localStorageBytes: Long = 1024L,
) = SurveyResponse(
    id = id,
    farmerId = farmerId,
    surveyId = surveyId,
    status = status,
    sections = sections,
    attachments = attachments,
    retryCount = retryCount,
    localStorageBytes = localStorageBytes,
)

fun buildSection(
    responseId: String,
    sectionKey: String = FarmSectionKeys.SECTION_KEY,
    repetitionIndex: Int = 0,
    answers: Map<String, AnswerValue> = buildFarmAnswers(),
) = ResponseSection(
    surveyResponseId = responseId,
    sectionKey = sectionKey,
    repetitionIndex = repetitionIndex,
    answers = answers,
)

/**
 * Default answers covering all four spec-mandated farm fields:
 *   crop_type, area_hectares, yield_estimate, gps_boundary.
 *
 * gps_boundary is a GpsBoundary (polygon) not a single GpsCoordinate —
 * a field boundary requires multiple vertices to form a closed shape.
 */
fun buildFarmAnswers(
    cropType: String = "maize",
    areaHectares: Double = 2.5,
    yieldEstimateKg: Double = 1800.0,
    boundaryVertices: List<GpsPoint> = listOf(
        GpsPoint(lat = -1.2860, lng = 36.8168, accuracyMeters = 4.0f),
        GpsPoint(lat = -1.2855, lng = 36.8175, accuracyMeters = 4.5f),
        GpsPoint(lat = -1.2862, lng = 36.8180, accuracyMeters = 3.8f),
        GpsPoint(lat = -1.2867, lng = 36.8172, accuracyMeters = 4.2f),
    ),
): Map<String, AnswerValue> = mapOf(
    FarmSectionKeys.CROP_TYPE      to AnswerValue.Text(cropType),
    FarmSectionKeys.AREA_HECTARES  to AnswerValue.Number(areaHectares),
    FarmSectionKeys.YIELD_ESTIMATE to AnswerValue.Number(yieldEstimateKg),
    FarmSectionKeys.GPS_BOUNDARY   to AnswerValue.GpsBoundary(boundaryVertices),
)

/**
 * Build a response with [farmCount] repeating "farm" sections —
 * the core scenario for dynamic nested structure.
 */
fun buildResponseWithFarms(farmCount: Int, responseId: String = "resp-farms"): SurveyResponse {
    val sections = (0 until farmCount).map { i ->
        buildSection(responseId = responseId, repetitionIndex = i)
    }
    return buildResponse(id = responseId, sections = sections)
}

fun buildAttachment(
    responseId: String,
    id: String = "att-${System.nanoTime()}",
    sizeBytes: Long = 512_000L,
    uploadStatus: UploadStatus = UploadStatus.PENDING,
) = MediaAttachment(
    id = id,
    surveyResponseId = responseId,
    localFilePath = "/data/survey/photos/$id.jpg",
    mimeType = "image/jpeg",
    sizeBytes = sizeBytes,
    uploadStatus = uploadStatus,
)

// ---------------------------------------------------------------------------
// Pre-baked API configurations
// ---------------------------------------------------------------------------

fun allSucceedApi() = FakeSurveyApiService()

fun failAtIndexApi(vararg indices: Int, type: FailureType = FailureType.SERVER_ERROR_500) =
    FakeSurveyApiService(failurePlan = indices.map { FailureInstruction(it, type) })

fun timeoutAtIndexApi(vararg indices: Int) =
    FakeSurveyApiService(failurePlan = indices.map { FailureInstruction(it, FailureType.TIMEOUT) })

fun noNetworkAtIndexApi(vararg indices: Int) =
    FakeSurveyApiService(failurePlan = indices.map { FailureInstruction(it, FailureType.NO_NETWORK) })

// ---------------------------------------------------------------------------
// Pre-baked device policies
// ---------------------------------------------------------------------------

fun normalPolicy() = FakeDevicePolicyEvaluator(SyncPolicy(shouldSync = true))

fun lowBatteryPolicy() = FakeDevicePolicyEvaluator(
    SyncPolicy(shouldSync = false, skipReason = "Battery critically low (10%).")
)

fun meteredPolicy(capBytes: Long = 10L * 1024 * 1024) = FakeDevicePolicyEvaluator(
    SyncPolicy(shouldSync = true, maxBytesPerSession = capBytes, networkType = NetworkType.METERED_CELLULAR)
)
