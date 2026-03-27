//
//  SurveyBuilders.swift (Test Fixtures)
//  SurveySyncEngineIOS
//
// .
//

import Foundation

// MARK: - 1. Survey Response Builder
/// A factory function that creates a `SurveyResponse` with sensible defaults.
/// Used extensively in Unit Tests to avoid verbose boilerplate initialization.
func buildResponse(
    id: String = UUID().uuidString,
    farmerId: String = "farmer-1",
    surveyId: String = "survey-1",
    status: SyncStatus = .pending,
    sections: [ResponseSection] = [],
    attachments: [MediaAttachment] = [],
    retryCount: Int = 0,
    localStorageBytes: Int64 = 1024
) -> SurveyResponse {
    return SurveyResponse(
        id: id,
        farmerId: farmerId,
        surveyId: surveyId,
        status: status,
        sections: sections,
        attachments: attachments,
        retryCount: retryCount,
        createdAt: Int64(Date().timeIntervalSince1970 * 1000), // Current timestamp in ms
        localStorageBytes: localStorageBytes
    )
}

// MARK: - 2. Section Builders
/// Creates a `ResponseSection` for a specific survey response.
/// Defaults to the "farm" section key using the agricultural data structure.
func buildSection(
    responseId: String,
    sectionKey: String = FarmSectionKeys.sectionKey,
    repetitionIndex: Int = 0,
    answers: [String: AnswerValue] = buildFarmAnswers()
) -> ResponseSection {
    return ResponseSection(
        surveyResponseId: responseId,
        sectionKey: sectionKey,
        repetitionIndex: repetitionIndex,
        answers: answers
    )
}

/// Generates a dictionary of mock agricultural answers (Crop, Area, Yield, GPS).
/// Simulates a real-world farm survey data point.
func buildFarmAnswers(
    cropType: String = "maize",
    areaHectares: Double = 2.5,
    yieldEstimateKg: Double = 1800.0,
    boundaryVertices: [GpsPoint] = [
        GpsPoint(lat: -1.2860, lng: 36.8168, accuracyMeters: 4.0),
        GpsPoint(lat: -1.2855, lng: 36.8175, accuracyMeters: 4.5),
        GpsPoint(lat: -1.2862, lng: 36.8180, accuracyMeters: 3.8),
        GpsPoint(lat: -1.2867, lng: 36.8172, accuracyMeters: 4.2)
    ]
) -> [String: AnswerValue] {
    return [
        FarmSectionKeys.cropType: .text(cropType),
        FarmSectionKeys.areaHectares: .number(areaHectares),
        FarmSectionKeys.yieldEstimate: .number(yieldEstimateKg),
        FarmSectionKeys.gpsBoundary: .gpsBoundary(boundaryVertices)
    ]
}

/// Convenience helper to build a response containing multiple repeating "farm" sections.
/// Useful for testing hierarchical or list-based data persistence.
func buildResponseWithFarms(farmCount: Int, responseId: String = "resp-farms") -> SurveyResponse {
    let sections = (0..<farmCount).map { i in
        buildSection(responseId: responseId, repetitionIndex: i)
    }
    return buildResponse(id: responseId, sections: sections)
}

// MARK: - 3. Attachment Builder
/// Creates a mock `MediaAttachment` (photo/video) associated with a survey.
func buildAttachment(
    responseId: String,
    id: String = "att-\(UUID().uuidString)",
    sizeBytes: Int64 = 512_000,
    uploadStatus: UploadStatus = .pending
) -> MediaAttachment {
    return MediaAttachment(
        id: id,
        surveyResponseId: responseId,
        localFilePath: "/data/survey/photos/\(id).jpg",
        mimeType: "image/jpeg",
        sizeBytes: sizeBytes,
        uploadStatus: uploadStatus
    )
}

// MARK: - 4. API & Policy Helpers (Fakes)

/// Returns an API service that successfully processes every upload.
func allSucceedApi() -> FakeSurveyApiService {
    return FakeSurveyApiService()
}

/// Returns an API service that fails with a Server Error (500) at the specified indices in the sync queue.
func failAtIndexApi(indices: Int..., type: FailureType = .serverError500) -> FakeSurveyApiService {
    let instructions = indices.map { FailureInstruction($0, type) }
    return FakeSurveyApiService(failurePlan: instructions)
}

/// Returns an API service that simulates a Network Timeout at specific positions.
func timeoutAtIndexApi(indices: Int...) -> FakeSurveyApiService {
    let instructions = indices.map { FailureInstruction($0, .timeout) }
    return FakeSurveyApiService(failurePlan: instructions)
}

/// Returns an API service that simulates a 'No Network/Host Not Found' error at specific positions.
func noNetworkAtIndexApi(indices: Int...) -> FakeSurveyApiService {
    let instructions = indices.map { FailureInstruction($0, .noNetwork) }
    return FakeSurveyApiService(failurePlan: instructions)
}

/// Returns a policy evaluator that always allows syncing (standard conditions).
func normalPolicy() -> FakeDevicePolicyEvaluator {
    return FakeDevicePolicyEvaluator(policy: SyncPolicy(shouldSync: true))
}

/// Returns a policy evaluator that blocks sync due to low battery.
func lowBatteryPolicy() -> FakeDevicePolicyEvaluator {
    return FakeDevicePolicyEvaluator(
        policy: SyncPolicy(shouldSync: false, skipReason: "Battery critically low (10%).")
    )
}

/// Returns a policy evaluator that simulates a metered connection with a data cap.
func meteredPolicy(capBytes: Int64 = 10 * 1024 * 1024) -> FakeDevicePolicyEvaluator {
    return FakeDevicePolicyEvaluator(
        policy: SyncPolicy(
            shouldSync: true,
            maxBytesPerSession: capBytes,
            networkType: .meteredCellular
        )
    )
}
