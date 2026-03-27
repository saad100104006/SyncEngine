//
//  SyncWorkerTests.swift
//  SurveySyncEngineIOS
//
// .
//

import XCTest

/// Unit tests for the SyncWorker class, ensuring that the engine's SyncResult
/// is correctly mapped to the background worker's life-cycle states (success, retry, failure).
final class SyncWorkerTests: XCTestCase {

    private var repo: FakeSurveyRepository!

    override func setUp() {
        super.setUp()
        // Initialize a clean fake repository for state verification
        repo = FakeSurveyRepository()
    }

    /// Verifies that the worker returns a success state when the engine completes a full sync batch.
    func test_worker_returnsSuccess_whenAllResponsesSync() async throws {
        
        // GIVEN: 3 pending survey responses in the local database
        for i in 0..<3 {
            let response = buildResponse(id: "resp-\(i)")
            // Using 'try await' directly; XCTest will catch and report any repository errors
            try await repo.saveResponse(response)
        }
        
        // Create an engine where the API always returns success
        let engine = TestSyncEngineFactory.create(repo: repo, api: allSucceedApi())
        let worker = SyncWorker(engine: engine)

        // WHEN: The worker performs its task
        let result = await worker.doWork()

        // THEN: The output data should indicate a completed session with 3 successes
        assertOutputData(result, expectedType: "COMPLETED", expectedSucceeded: 3, expectedFailed: 0)
    }

    /// Verifies that the worker still returns a success state even if some items in the batch fail.
    func test_worker_returnsSuccessWithPartialFailure_whenSomeResponsesFail() async {
        // GIVEN: 4 pending survey responses
        for i in 0..<4 {
            let response = buildResponse(id: "resp-\(i)")
            do {
                try await repo.saveResponse(response)
            } catch {
                print("Failed to save: \(error.localizedDescription)")
            }
        }
        
        // Configure the engine to fail on the second item (index 1) with a server error
        let engine = TestSyncEngineFactory.create(
            repo: repo,
            api: failAtIndexApi(indices: 1, type: .serverError500)
        )
        let worker = SyncWorker(engine: engine)

        // WHEN: The worker performs its task
        let result = await worker.doWork()

        // THEN: The output should show the session completed, but with 1 recorded failure
        assertOutputData(result, expectedType: "COMPLETED", expectedSucceeded: 3, expectedFailed: 1)
    }

    /// Verifies that the worker returns a retry signal if the sync session is terminated early
    /// due to network instability.
    func test_worker_returnsRetry_onEarlyNetworkTermination() async {
        // GIVEN: 5 pending responses
        for i in 0..<5 {
            let response = buildResponse(id: "resp-\(i)")
            do {
                try await repo.saveResponse(response)
            } catch {
                print("Failed to save: \(error.localizedDescription)")
            }
        }
        
        // Two consecutive timeouts trigger early termination logic in the engine
        let engine = TestSyncEngineFactory.create(repo: repo, api: timeoutAtIndexApi(indices: 0, 1))
        let worker = SyncWorker(engine: engine)

        // WHEN: The worker performs its task
        let result = await worker.doWork()

        // THEN: The result must be .retry so the OS reschedules the task for later
        XCTAssertEqual(result, .retry)
    }

    /// Verifies that the worker handles the "Nothing to Sync" case as a successful non-event.
    func test_worker_returnsSuccess_withNothingToSync() async {
        let engine = TestSyncEngineFactory.create(repo: repo, api: allSucceedApi())
        let worker = SyncWorker(engine: engine)

        // WHEN: Worker runs on an empty queue
        let result = await worker.doWork()

        // THEN: Result type should be NOTHING_TO_SYNC
        assertOutputType(result, "NOTHING_TO_SYNC")
    }

    /// Verifies that the worker returns success if it attempts to start while another
    /// sync session is already active.
    func test_worker_returnsSuccess_withAlreadyRunning() async {
        // GIVEN: An engine mock that always reports itself as already in progress
        let lockedEngine = AlreadyRunningEngine(
            repository: repo,
            apiService: allSucceedApi()
        )
        let worker = SyncWorker(engine: lockedEngine)

        // WHEN: Worker runs
        let result = await worker.doWork()

        // THEN: The worker treats this as success to prevent redundant task queuing
        assertOutputType(result, "ALREADY_RUNNING")
    }

    /// Verifies that the worker returns success when a sync is skipped due to hardware policies
    /// (e.g., low battery).
    func test_worker_returnsSuccess_withSkipped() async {
        // GIVEN: A pending response but a policy that prevents syncing
        let response = buildResponse(id: "resp-1")
        do {
            try await repo.saveResponse(response)
        } catch {
            print("Failed to save: \(error.localizedDescription)")
        }
        
        let engine = TestSyncEngineFactory.create(
            repo: repo,
            api: allSucceedApi(),
            devicePolicy: lowBatteryPolicy()
        )
        let worker = SyncWorker(engine: engine)

        // WHEN: Worker attempts to run
        let result = await worker.doWork()

        // THEN: The result type should be SKIPPED
        assertOutputType(result, "SKIPPED")
    }

    // MARK: - Helpers

    /// Validates the specific key-value pairs returned in a successful WorkerResult.
    private func assertOutputData(
        _ result: WorkerResult,
        expectedType: String,
        expectedSucceeded: Int,
        expectedFailed: Int
    ) {
        if case .success(let output) = result {
            XCTAssertEqual(output[SyncWorker.KEY_RESULT_TYPE] as? String, expectedType)
            XCTAssertEqual(output[SyncWorker.KEY_SUCCEEDED_COUNT] as? Int, expectedSucceeded)
            XCTAssertEqual(output[SyncWorker.KEY_FAILED_COUNT] as? Int, expectedFailed)
        } else {
            XCTFail("Expected .success result but got \(result)")
        }
    }

    /// Validates only the 'resultType' field in a successful WorkerResult.
    private func assertOutputType(_ result: WorkerResult, _ expectedType: String) {
        if case .success(let output) = result {
            XCTAssertEqual(output[SyncWorker.KEY_RESULT_TYPE] as? String, expectedType)
        } else {
            XCTFail("Expected .success result but got \(result)")
        }
    }
}

// MARK: - Mocking AlreadyRunning
/// A specialized mock for the SyncEngine to simulate a locked/busy state.
private class AlreadyRunningEngine: SyncEngine {
    override func sync() async -> SyncResult {
        return .alreadyRunning
    }
}
