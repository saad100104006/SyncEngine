//
//  FakeSurveyApiService.swift
//  SurveySyncEngineIOS
//

import Foundation

// MARK: - Failure Plan DSL & Models

/// Defines the specific types of network or server failures to simulate during testing.
public enum FailureType {
    case timeout
    case noNetwork
    case serverError500
    case serverError503
    case clientError400
    case clientError422
    case unknown
}

/// A specific instruction telling the fake service which call index should trigger a specific failure.
public struct FailureInstruction {
    public let callIndex: Int
    public let failureType: FailureType
    
    public init(_ callIndex: Int, _ failureType: FailureType) {
        self.callIndex = callIndex
        self.failureType = failureType
    }
}

/// A Domain-Specific Language (DSL) helper that mimics Kotlin's vararg syntax
/// to easily create a list of failure instructions for unit tests.
public func buildFailurePlan(_ pairs: (Int, FailureType)...) -> [FailureInstruction] {
    return pairs.map { FailureInstruction($0.0, $0.1) }
}

/// A custom error used specifically to test how the system handles unrecognized or unexpected errors.
public struct UnknownTestError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { return message }
}

// MARK: - Fake Survey API Service

/// A mock implementation of SurveyApiService used for unit testing synchronization and retry logic.
public class FakeSurveyApiService: SurveyApiService {
    
    // Configurable delay to simulate different network speeds
    private var delayNanoseconds: UInt64 = 0
    private let failurePlan: [FailureInstruction]
    private let simulatedNetworkDelayMs: UInt64
    
    // Internal counter for calls, using NSLock to ensure thread-safety across concurrent Tasks
    private var _callIndex: Int = 0
    private let lock = NSLock()
    
    /// Initializes the fake service with an optional plan of failures and a simulated delay.
    public init(failurePlan: [FailureInstruction] = [], simulatedNetworkDelayMs: UInt64 = 10) {
        self.failurePlan = failurePlan
        self.simulatedNetworkDelayMs = simulatedNetworkDelayMs
    }
    
    // MARK: - Upload Survey
    /// Simulates uploading a survey response, applying any scheduled failures based on the current call index.
    public func uploadSurveyResponse(response: SurveyResponse) async throws -> UploadResponseDto {
        // Simulate network latency (1 millisecond = 1,000,000 nanoseconds)
        try await Task.sleep(nanoseconds: simulatedNetworkDelayMs * 1_000_000)
        
        // Get the current call count and increment it safely
        let index = getAndIncrementCallIndex()
        
        // Check if the current call is scheduled to fail according to the test plan
        try applyFailurePlan(at: index)
        
        // Return a successful response DTO if no error was thrown
        return UploadResponseDto(
            serverId: "srv-\(UUID().uuidString)",
            receivedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }
    
    // MARK: - Upload Attachment
    /// Simulates the upload of a media file.
    /// Follows the behavior where failures are not applied to individual attachment uploads.
    public func uploadAttachment(
        surveyResponseId: String,
        attachmentId: String,
        localFilePath: String,
        mimeType: String
    ) async throws -> AttachmentUploadDto {
        try await Task.sleep(nanoseconds: simulatedNetworkDelayMs * 1_000_000)
        
        return AttachmentUploadDto(
            attachmentId: attachmentId,
            serverUrl: "https://fake-storage.example.com/\(attachmentId)"
        )
    }
    
    // MARK: - Internals
    /// Logic to determine if a specific network error or HTTP exception should be thrown.
    private func applyFailurePlan(at index: Int) throws {
        guard let instruction = failurePlan.first(where: { $0.callIndex == index }) else { return }
        
        switch instruction.failureType {
        case .timeout:
            // Simulates a connection timeout (SocketTimeout)
            throw URLError(.timedOut)
        case .noNetwork:
            // Simulates total lack of internet connection
            throw URLError(.notConnectedToInternet)
        case .serverError500:
            throw SurveyHttpException(httpCode: 500, message: "Internal Server Error")
        case .serverError503:
            throw SurveyHttpException(httpCode: 503, message: "Service Unavailable")
        case .clientError400:
            throw SurveyHttpException(httpCode: 400, message: "Bad Request")
        case .clientError422:
            throw SurveyHttpException(httpCode: 422, message: "Unprocessable Entity")
        case .unknown:
            throw UnknownTestError(message: "Simulated unknown error at call \(index)")
        }
    }
    
    // MARK: - Atomic Thread-Safe Helpers
    
    /// Safely retrieves and increments the call counter.
    private func getAndIncrementCallIndex() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let currentIndex = _callIndex
        _callIndex += 1
        return currentIndex
    }
    
    /// Resets the internal call counter to zero for fresh test runs.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _callIndex = 0
    }
    
    /// Returns the current number of times uploadSurveyResponse has been called.
    public func callCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return _callIndex
    }

    /// Dynamically adjusts the simulated response delay.
    public func setDelay(_ nanoseconds: UInt64) {
        self.delayNanoseconds = nanoseconds
    }
}
