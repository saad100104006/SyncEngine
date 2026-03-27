//
//  FakeSurveyApiService.swift
//  SurveySyncEngineIOS
//
import Foundation

public enum FailureType {
    case timeout, noNetwork
    case serverError500, serverError503
    case clientError400, clientError422
    case unknown
}

public struct FailureInstruction {
    public let callIndex: Int
    public let failureType: FailureType
    public init(_ callIndex: Int, _ failureType: FailureType) {
        self.callIndex = callIndex
        self.failureType = failureType
    }
}

public func buildFailurePlan(_ pairs: (Int, FailureType)...) -> [FailureInstruction] {
    pairs.map { FailureInstruction($0.0, $0.1) }
}

public struct UnknownTestError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

public class FakeSurveyApiService: SurveyApiService {
    private let failurePlan: [FailureInstruction]

    // FIX Bug 1: previously two fields existed — `simulatedNetworkDelayMs` (read
    // by Task.sleep) and `delayNanoseconds` (written by setDelay but never read).
    // setDelay updated the wrong field so the concurrent sync test's 200ms delay
    // was silently ignored, making the test non-deterministic.
    // Fix: one field `delayNanoseconds`. setDelay writes it; Task.sleep reads it.
    private var delayNanoseconds: UInt64

    private var _callIndex = 0
    private let lock = NSLock()

    public init(failurePlan: [FailureInstruction] = [], simulatedNetworkDelayMs: UInt64 = 10) {
        self.failurePlan = failurePlan
        self.delayNanoseconds = simulatedNetworkDelayMs * 1_000_000
    }

    public func uploadSurveyResponse(response: SurveyResponse) async throws -> UploadResponseDto {
        try await Task.sleep(nanoseconds: delayNanoseconds)   // reads the single field
        let index = getAndIncrementCallIndex()
        try applyFailurePlan(at: index)
        return UploadResponseDto(serverId: "srv-\(UUID().uuidString)",
                                 receivedAt: Int64(Date().timeIntervalSince1970 * 1000))
    }

    public func uploadAttachment(surveyResponseId: String, attachmentId: String,
                                  localFilePath: String, mimeType: String) async throws -> AttachmentUploadDto {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return AttachmentUploadDto(attachmentId: attachmentId,
                                   serverUrl: "https://fake-storage.example.com/\(attachmentId)")
    }

    /// Updates the per-call delay at runtime.
    /// FIX: now writes to the same field Task.sleep reads.
    public func setDelay(_ nanoseconds: UInt64) { self.delayNanoseconds = nanoseconds }
    public func reset()        { lock.withLock { _callIndex = 0 } }
    public func callCount() -> Int { lock.withLock { _callIndex } }

    private func applyFailurePlan(at index: Int) throws {
        guard let i = failurePlan.first(where: { $0.callIndex == index }) else { return }
        switch i.failureType {
        case .timeout:        throw URLError(.timedOut)
        case .noNetwork:      throw URLError(.notConnectedToInternet)
        case .serverError500: throw SurveyHttpException(httpCode: 500, message: "Internal Server Error")
        case .serverError503: throw SurveyHttpException(httpCode: 503, message: "Service Unavailable")
        case .clientError400: throw SurveyHttpException(httpCode: 400, message: "Bad Request")
        case .clientError422: throw SurveyHttpException(httpCode: 422, message: "Unprocessable Entity")
        case .unknown:        throw UnknownTestError(message: "Simulated unknown error at call \(index)")
        }
    }

    private func getAndIncrementCallIndex() -> Int {
        lock.lock(); defer { lock.unlock() }
        let c = _callIndex; _callIndex += 1; return c
    }
}

extension NSLocking {
    @discardableResult
    func withLock<T>(_ block: () -> T) -> T { lock(); defer { unlock() }; return block() }
}
