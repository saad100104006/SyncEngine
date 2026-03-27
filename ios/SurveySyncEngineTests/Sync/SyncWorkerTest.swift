//
//  SyncWorkerTests.swift
//  SurveySyncEngineIOS
//
import XCTest
import Combine

final class SyncWorkerTests: XCTestCase {
    private var repo: FakeSurveyRepository!
    override func setUp() { super.setUp(); repo = FakeSurveyRepository() }

    func test_worker_returnsSuccess_whenAllResponsesSync() async throws {
        for i in 0..<3 { try await repo.saveResponse(buildResponse(id: "resp-\(i)")) }
        let result = await SyncWorker(engine: TestSyncEngineFactory.create(repo: repo, api: allSucceedApi())).doWork()
        assertOutputData(result, expectedType: "COMPLETED", expectedSucceeded: 3, expectedFailed: 0)
    }

    func test_worker_returnsSuccessWithPartialFailure_whenSomeResponsesFail() async throws {
        for i in 0..<4 { try await repo.saveResponse(buildResponse(id: "resp-\(i)")) }
        let result = await SyncWorker(engine: TestSyncEngineFactory.create(
            repo: repo, api: failAtIndexApi(indices: 1, type: .serverError500))).doWork()
        assertOutputData(result, expectedType: "COMPLETED", expectedSucceeded: 3, expectedFailed: 1)
    }

    func test_worker_returnsRetry_onEarlyNetworkTermination() async throws {
        for i in 0..<5 { try await repo.saveResponse(buildResponse(id: "resp-\(i)")) }
        let result = await SyncWorker(engine: TestSyncEngineFactory.create(
            repo: repo, api: timeoutAtIndexApi(indices: 0, 1))).doWork()
        XCTAssertEqual(result, .retry)
    }

    func test_worker_returnsSuccess_withNothingToSync() async {
        let result = await SyncWorker(engine: TestSyncEngineFactory.create(repo: repo, api: allSucceedApi())).doWork()
        assertOutputType(result, "NOTHING_TO_SYNC")
    }

    func test_worker_returnsSuccess_withAlreadyRunning() async {
        // ACTOR FIX: AlreadyRunningEngine previously used `class AlreadyRunningEngine: SyncEngine`
        // with `override func sync()`. Actors cannot be subclassed in Swift — the compiler
        // rejects inheritance from an actor. Fix: AlreadyRunningStub is a plain class that
        // conforms directly to SyncEngineProtocol. SyncWorker now accepts the protocol.
        let result = await SyncWorker(engine: AlreadyRunningStub()).doWork()
        assertOutputType(result, "ALREADY_RUNNING")
    }

    func test_worker_returnsSuccess_withSkipped() async throws {
        try await repo.saveResponse(buildResponse(id: "resp-1"))
        let result = await SyncWorker(engine: TestSyncEngineFactory.create(
            repo: repo, api: allSucceedApi(), devicePolicy: lowBatteryPolicy())).doWork()
        assertOutputType(result, "SKIPPED")
    }

    private func assertOutputData(_ result: WorkerResult, expectedType: String,
                                   expectedSucceeded: Int, expectedFailed: Int) {
        guard case .success(let o) = result else { return XCTFail("Expected .success got \(result)") }
        XCTAssertEqual(o[SyncWorker.KEY_RESULT_TYPE] as? String, expectedType)
        XCTAssertEqual(o[SyncWorker.KEY_SUCCEEDED_COUNT] as? Int, expectedSucceeded)
        XCTAssertEqual(o[SyncWorker.KEY_FAILED_COUNT] as? Int, expectedFailed)
    }

    private func assertOutputType(_ result: WorkerResult, _ expectedType: String) {
        guard case .success(let o) = result else { return XCTFail("Expected .success got \(result)") }
        XCTAssertEqual(o[SyncWorker.KEY_RESULT_TYPE] as? String, expectedType)
    }
}

// Conforms to the protocol — no subclassing needed.
private class AlreadyRunningStub: SyncEngineProtocol {
    func sync() async -> SyncResult { .alreadyRunning }
    var progressPublisher: AnyPublisher<SyncProgress, Never> {
        PassthroughSubject<SyncProgress, Never>().eraseToAnyPublisher()
    }
}
