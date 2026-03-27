//
//  SyncEngineTests.swift
//  SurveySyncEngineIOS
//
//

import XCTest
import Combine

/// A comprehensive suite of unit tests for the SyncEngine core logic.
/// These tests verify synchronization behavior across various scenarios, including
/// successful batches, partial failures, network degradation, and hardware policy enforcement.
final class SyncEngineTests: XCTestCase {

    // The fake repository allows us to inspect database state changes during tests
    private var repo: FakeSurveyRepository!

    override func setUp() {
        super.setUp()
        // Initialize a clean repository state before each individual test run
        repo = FakeSurveyRepository()
    }
    
    // MARK: - Scenario 1: Offline Storage / Empty Queue

    /// Ensures the engine returns a specific status when no work is pending in the database.
    func test_syncWithEmptyQueue_returnsNothingToSync() async throws {
        let engine = makeEngine(api: allSucceedApi())
        
        let result = await engine.sync()
        
        XCTAssertEqual(result, .nothingToSync)
    }

    /// Verifies that responses saved locally are correctly identified as 'pending' by the repository.
    func test_responsesSavedOffline_areRetrievableAfterRestart() async throws {
        for i in 0..<10 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }

        let pending = try await repo.getPendingResponses()

        XCTAssertEqual(pending.count, 10)
        for response in pending {
            XCTAssertEqual(response.status, .pending)
        }
    }

    /// Validates that complex survey structures with repeating sections are fully preserved in the database.
    func test_responseWithRepeatingFarmSections_persistsAllRepetitions() async throws {
        let response = buildResponseWithFarms(farmCount: 3, responseId: "multi-farm")
        try await repo.saveResponse(response)

        let loaded = try await repo.getResponseById(id: "multi-farm")

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sections.count, 3)
        XCTAssertEqual(loaded?.sections[0].repetitionIndex, 0)
        XCTAssertEqual(loaded?.sections[1].repetitionIndex, 1)
        XCTAssertEqual(loaded?.sections[2].repetitionIndex, 2)
        
        loaded?.sections.forEach { section in
            XCTAssertEqual(section.sectionKey, "farm")
        }
    }

    /// Confirms the "Happy Path" where a full batch of items is uploaded without any errors.
    func test_all10Responses_syncSuccessfully() async throws {
        for i in 0..<10 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }
        let engine = makeEngine(api: allSucceedApi())

        let result = await engine.sync()

        // Result should be .completed with all items in the success list
        guard case let .completed(succeeded, failed) = result else {
            XCTFail("Expected .completed but got \(result)")
            return
        }
        
        XCTAssertEqual(succeeded.count, 10)
        XCTAssertTrue(failed.isEmpty)
        XCTAssertFalse(result.hasPartialFailure)
    }

    /// Checks that the database status is updated to .synced for every item after a successful run.
    func test_allResponses_areMarkedSynced_afterSuccessfulUpload() async throws {
        let ids = (0..<5).map { "resp-\($0)" }
        for id in ids {
            try await repo.saveResponse(buildResponse(id: id))
        }
        let engine = makeEngine(api: allSucceedApi())

        _ = await engine.sync()

        for id in ids {
            let status = try await repo.statusOf(id: id)
            XCTAssertEqual(status, .synced)
        }
    }

    // MARK: - Scenario 2: Partial Failure

    /// Tests that a single server error (500) does not stop the engine from processing the rest of the queue.
    func test_responses1to5Succeed_and6Fails_correctStatusTracking() async throws {
        let ids = (0...7).map { "resp-\($0)" }
        for id in ids {
            try await repo.saveResponse(buildResponse(id: id))
        }
        // Simulate a failure on the 6th item
        let engine = makeEngine(api: failAtIndexApi(indices: 5, type: .serverError500))

        let result = await engine.sync()

        guard case let .completed(succeeded, failed) = result else {
            XCTFail("Expected .completed but got \(result)")
            return
        }

        // Verify successful uploads 0-4
        for i in 0...4 {
            let status = try await repo.statusOf(id: "resp-\(i)")
            XCTAssertEqual(status, .synced)
            XCTAssertTrue(succeeded.contains("resp-\(i)"))
        }

        // Verify item 5 failed but kept its status as .failed
        let status5 = try await repo.statusOf(id: "resp-5")
        XCTAssertEqual(status5, .failed)
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(failed[0].responseId, "resp-5")
        XCTAssertTrue(failed[0].error.isServerError)

        // Verify the engine continued and finished items 6-7
        let status6 = try await repo.statusOf(id: "resp-6")
        let status7 = try await repo.statusOf(id: "resp-7")
        XCTAssertEqual(status6, .synced)
        XCTAssertEqual(status7, .synced)
    }

    /// Verifies that items already synced are ignored in subsequent runs, even if others need retrying.
    func test_failedResponses_areNotReUploaded_onNextSync() async throws {
        for i in 0...4 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }
        
        // First run: item 2 fails
        let firstEngine = makeEngine(api: failAtIndexApi(indices: 2))
        _ = await firstEngine.sync()

        // Second run: everything succeeds
        let secondEngine = makeEngine(api: allSucceedApi())
        let result = await secondEngine.sync()

        guard case let .completed(succeeded, _) = result else {
            XCTFail("Expected .completed but got \(result)")
            return
        }

        // Only the previously failed item should have been attempted this time
        XCTAssertEqual(succeeded.count, 1)
        XCTAssertEqual(succeeded[0], "resp-2")
    }

    /// Confirms that the engine accurately identifies and reports specific failed items in the final result.
    func test_partialFailureResult_reportsExactlyWhichResponsesFailed() async throws {
        for i in 0...4 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }
        let engine = makeEngine(api: failAtIndexApi(indices: 1, 3))

        let result = await engine.sync()

        guard case let .completed(succeeded, failed) = result else {
            XCTFail("Expected .completed but got \(result)")
            return
        }

        let failedIds = failed.map { $0.responseId }
        XCTAssertEqual(failedIds.count, 2)
        XCTAssertTrue(failedIds.contains("resp-1"))
        XCTAssertTrue(failedIds.contains("resp-3"))

        XCTAssertEqual(succeeded.count, 3)
        XCTAssertTrue(succeeded.contains("resp-0"))
        XCTAssertTrue(succeeded.contains("resp-2"))
        XCTAssertTrue(succeeded.contains("resp-4"))
    }

    /// Ensures the persistent retry counter increases every time an item fails a sync attempt.
    func test_retryCount_incrementsOnEachFailedAttempt() async throws {
        try await repo.saveResponse(buildResponse(id: "resp-0"))
        
        let engine1 = makeEngine(api: failAtIndexApi(indices: 0))
        _ = await engine1.sync()
        let count1 = try await repo.retryCountOf(id: "resp-0")
        XCTAssertEqual(count1, 1)

        let engine2 = makeEngine(api: failAtIndexApi(indices: 0))
        _ = await engine2.sync()
        let count2 = try await repo.retryCountOf(id: "resp-0")
        XCTAssertEqual(count2, 2)
    }

    // MARK: - Scenario 3: Network Degradation / Early Termination

    /// Verifies that consecutive timeouts trigger a "Fail Fast" early termination of the session.
    func test_twoConsecutiveTimeouts_triggerEarlyTermination() async throws {
            for i in 0...9 {
                try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
            }
            
            // Set threshold to 2 for consecutive timeouts
            let engine = makeEngine(
                api: timeoutAtIndexApi(indices: 3, 4),
                classifier: NetworkErrorClassifier(consecutiveFailureThreshold: 2)
            )

            let result = await engine.sync()

            // Confirm early termination state and counts
            guard case let .earlyTermination(succeeded, failedBeforeStop, reason, remainingCount) = result else {
                XCTFail("Expected .earlyTermination but got \(result)")
                return
            }
            
            XCTAssertEqual(succeeded.count, 3) // Items 0, 1, 2
            XCTAssertEqual(failedBeforeStop.count, 2) // Items 3, 4
            XCTAssertTrue(reason.isTimeout)
            XCTAssertEqual(remainingCount, 5) // Items 5-9
        }
    
    /// Ensures that a successful upload resets the consecutive failure counter to prevent accidental aborts.
    func test_successfulUpload_resetsConsecutiveNetworkFailureCounter() async throws {
        for i in 0...5 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }
        // Failure at 1, success at 2, failure at 3 (Not consecutive)
        let engine = makeEngine(
            api: timeoutAtIndexApi(indices: 1, 3),
            classifier: NetworkErrorClassifier(consecutiveFailureThreshold: 2)
        )

        let result = await engine.sync()

        // Should finish the batch since failures weren't back-to-back
        if case .completed = result {
            // Success
        } else {
            XCTFail("Expected .completed but got \(result)")
        }
    }

    /// Validates that items skipped due to early termination are left as PENDING in the database.
    func test_earlyTermination_preservesRemainingResponsesAsPending() async throws {
        for i in 0...7 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }
        let engine = makeEngine(api: noNetworkAtIndexApi(indices: 2, 3))

        _ = await engine.sync()

        for i in 4...7 {
            let status = try await repo.statusOf(id: "resp-\(i)")
            XCTAssertEqual(status, .pending, "resp-\(i) should remain PENDING after early stop")
        }
    }

    /// Verifies that a single network failure is tolerated if the threshold is higher than 1.
    func test_singleNetworkFailure_doesNotAbortWhenThresholdIsRaised() async throws {
        for i in 0...4 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }
        let engine = makeEngine(
            api: timeoutAtIndexApi(indices: 2),
            classifier: NetworkErrorClassifier(consecutiveFailureThreshold: 2)
        )

        let result = await engine.sync()

        guard case let .completed(succeeded, failed) = result else {
            XCTFail("Expected .completed but got \(result)")
            return
        }
        
        XCTAssertEqual(succeeded.count, 4)
        XCTAssertEqual(failed.count, 1)
    }

    // MARK: - Scenario 4: Concurrent Sync Prevention

    /// Ensures the engine's internal lock prevents two simultaneous sync calls from overlapping.
    func test_secondSyncReturnsAlreadyRunning_whileFirstIsInFlight() async throws {
        for i in 0...4 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }
        // Simulate artificial delay to keep the first sync busy
        let slowApi = allSucceedApi()
        slowApi.setDelay(200_000_000)
        let engine = makeEngine(api: slowApi)

        // Launch first sync in background
        let syncTask = Task {
            await engine.sync()
        }

        // Give the task a moment to acquire the lock
        try await Task.sleep(nanoseconds: 50_000_000)
        
        // This second call should immediately return .alreadyRunning
        let secondResult = await engine.sync()

        _ = await syncTask.value

        XCTAssertEqual(secondResult, .alreadyRunning)
    }

    /// Validates that even if two syncs are called near-simultaneously, the API is only called once per item.
    func test_concurrentSync_doesNotDuplicateUploads() async throws {
        for i in 0...2 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }
        let api = allSucceedApi()
        let engine = makeEngine(api: api)

        // Run both concurrently
        async let task1 = engine.sync()
        async let task2 = engine.sync()
        _ = await (task1, task2)

        // Total calls should still only be 3
        XCTAssertEqual(api.callCount(), 3)
        for i in 0...2 {
            let status = try await repo.statusOf(id: "resp-\(i)")
            XCTAssertEqual(status, .synced)
        }
    }

    // MARK: - Scenario 5: Network Error Handling & Retries

    /// Ensures connectivity errors are properly categorized as network-level failures.
    func test_noNetwork_mapsToNetworkUnavailableError() async throws {
            try await repo.saveResponse(buildResponse(id: "resp-0"))
            
            let engine = makeEngine(
                api: noNetworkAtIndexApi(indices: 0),
                classifier: NetworkErrorClassifier(consecutiveFailureThreshold: 99)
            )

            let result = await engine.sync()
            
            guard case let .completed(_, failed) = result else {
                XCTFail("Expected .completed but got \(result)")
                return
            }
            XCTAssertTrue(failed[0].error.isNetworkUnavailable)
        }

    /// Checks that 500 errors are mapped correctly and remain eligible for retry.
    func test_server500_mapsToServerError_andIsRetryable() async throws {
        try await repo.saveResponse(buildResponse(id: "resp-0"))
        let engine = makeEngine(api: failAtIndexApi(indices: 0, type: .serverError500))

        let result = await engine.sync()
        
        guard case let .completed(_, failed) = result else { return XCTFail() }
        XCTAssertTrue(failed[0].error.isServerError)
        XCTAssertTrue(failed[0].error.isRetryable())
    }

    /// Checks that 400 errors are mapped correctly and marked as non-retryable terminal failures.
    func test_client400_mapsToClientError_andIsNotRetryable() async throws {
        try await repo.saveResponse(buildResponse(id: "resp-0"))
        let engine = makeEngine(api: failAtIndexApi(indices: 0, type: .clientError400))

        let result = await engine.sync()
        
        guard case let .completed(_, failed) = result else { return XCTFail() }
        XCTAssertTrue(failed[0].error.isClientError)
        XCTAssertFalse(failed[0].error.isRetryable())
    }

    /// Validates that a terminal client error moves the response to a 'Dead' state so it stops appearing in the queue.
    func test_clientError400_marksResponseDead_andNeverRetried() async throws {
        try await repo.saveResponse(buildResponse(id: "resp-0"))
        let engine = makeEngine(api: failAtIndexApi(indices: 0, type: .clientError400))

        _ = await engine.sync()

        let status = try await repo.statusOf(id: "resp-0")
        XCTAssertEqual(status, .dead)

        // Second sync should find nothing to do
        let result = await makeEngine(api: allSucceedApi()).sync()
        XCTAssertEqual(result, .nothingToSync)
    }

    /// Verifies that server errors permit retries in subsequent sync cycles.
    func test_serverError500_marksResponseFailed_andIsRetriedNextSync() async throws {
        try await repo.saveResponse(buildResponse(id: "resp-0"))

        // First attempt fails
        let engine1 = makeEngine(api: failAtIndexApi(indices: 0, type: .serverError500))
        _ = await engine1.sync()
        
        let status1 = try await repo.statusOf(id: "resp-0")
        XCTAssertEqual(status1, .failed)

        // Second attempt succeeds
        let engine2 = makeEngine(api: allSucceedApi())
        let result = await engine2.sync()
        
        guard case let .completed(succeeded, _) = result else { return XCTFail() }
        XCTAssertEqual(succeeded.count, 1)
        
        let status2 = try await repo.statusOf(id: "resp-0")
        XCTAssertEqual(status2, .synced)
    }

    // MARK: - Progress Reporting

    /// Tests the sequence of events emitted to the progress publisher during a successful sync.
    func test_progressFlow_emitsStarted_thenItems_thenFinished() async throws {
            for i in 0...2 {
                try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
            }
            let engine = makeEngine(api: allSucceedApi())

            var emittedEvents: [SyncProgress] = []
            let cancellable = engine.progressPublisher.sink { event in
                emittedEvents.append(event)
            }

            _ = await engine.sync()
            cancellable.cancel()

            // 1 Start + 3 Uploading + 3 Succeeded + 1 Finished = 8 total
            XCTAssertEqual(emittedEvents.count, 8, "Expected exactly 8 progress events")
            guard emittedEvents.count == 8 else { return }

            guard case let .started(total) = emittedEvents[0] else { return XCTFail("Expected .started") }
            XCTAssertEqual(total, 3)

            // Confirm individual item progress logic
            guard case let .itemUploading(_, idx0, _) = emittedEvents[1] else { return XCTFail() }
            XCTAssertEqual(idx0, 0)
            guard case let .itemSucceeded(_, sIdx0, _) = emittedEvents[2] else { return XCTFail() }
            XCTAssertEqual(sIdx0, 0)

            guard case let .finished(result) = emittedEvents[7] else { return XCTFail("Expected .finished") }
            if case .completed = result {} else { XCTFail("Expected completed result") }
        }

    /// Ensures that failure events are correctly emitted to the progress publisher when an upload fails.
    func test_progressFlow_emitsItemFailed_forFailedUploads() async throws {
            try await repo.saveResponse(buildResponse(id: "resp-0"))
            let engine = makeEngine(api: failAtIndexApi(indices: 0, type: .serverError500))

            var emittedEvents: [SyncProgress] = []
            let cancellable = engine.progressPublisher.sink { event in
                emittedEvents.append(event)
            }

            _ = await engine.sync()
            cancellable.cancel()

            // Timeline: Start -> Uploading -> Failed -> Finished
            XCTAssertEqual(emittedEvents.count, 4, "Expected exactly 4 progress events")
            guard emittedEvents.count == 4 else { return }

            guard case .started = emittedEvents[0] else { return XCTFail("Expected .started") }
            guard case let .itemUploading(upId, _, _) = emittedEvents[1] else { return XCTFail("Expected .itemUploading") }
            XCTAssertEqual(upId, "resp-0")

            guard case let .itemFailed(responseId, error, _, _) = emittedEvents[2] else { return XCTFail("Expected .itemFailed") }
            XCTAssertEqual(responseId, "resp-0")
            XCTAssertTrue(error.isServerError)
            
            guard case .finished = emittedEvents[3] else { return XCTFail("Expected .finished") }
        }

    // MARK: - Device Aware Policy

    /// Verifies that the sync engine respects hardware constraints like low battery by skipping the session.
    func test_syncSkipped_whenBatteryIsCriticallyLow() async throws {
        for i in 0...3 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }
        let engine = makeEngine(api: allSucceedApi(), devicePolicy: lowBatteryPolicy())

        let result = await engine.sync()

        guard case let .skipped(reason) = result else {
            XCTFail("Expected .skipped but got \(result)")
            return
        }
        XCTAssertTrue(reason.contains("Battery"))
        
        for i in 0...3 {
            let status = try await repo.statusOf(id: "resp-\(i)")
            XCTAssertEqual(status, .pending)
        }
    }

    /// Tests the byte cap constraint, ensuring the engine terminates early on metered connections when usage is exceeded.
    func test_syncRespectsByteCap_onMeteredNetwork() async throws {
        for i in 0...4 {
            // 6MB per item
            try await repo.saveResponse(buildResponse(id: "resp-\(i)", localStorageBytes: 6 * 1024 * 1024))
        }
        let engine = makeEngine(
            api: allSucceedApi(),
            devicePolicy: meteredPolicy(capBytes: 10 * 1024 * 1024)
        )

        let result = await engine.sync()

        // 12MB (2 items) > 10MB cap. Should stop after item 2.
        guard case let .earlyTermination(succeeded, _, _, _) = result else {
            XCTFail("Expected .earlyTermination but got \(result)")
            return
        }
        XCTAssertEqual(succeeded.count, 2)
    }

    // MARK: - Crash Recovery

    /// Ensures that items stuck in an 'In Progress' state (due to crash/termination) are reset to 'Pending' upon restart.
    func test_inProgressResponses_resetToPending_onRecovery() async throws {
        try await repo.saveResponse(buildResponse(id: "resp-stuck", status: SyncStatus.pending))
        try await repo.markInProgress(responseId: "resp-stuck")
        
        let status1 = try await repo.statusOf(id: "resp-stuck")
        XCTAssertEqual(status1, .inProgress)

        try await repo.resetStuckInProgress()

        let status2 = try await repo.statusOf(id: "resp-stuck")
        XCTAssertEqual(status2, .pending)
    }

    // MARK: - Pruning Logic

    /// Verifies that data pruning (cleanup) is called at the start of every synchronization session.
    func test_pruning_isCalledBeforeEverySyncSession() async throws {
        class SpyRepo: FakeSurveyRepository {
            var pruneMediaCalled = false
            var pruneRecordsCalled = false
            
            override func pruneUploadedMedia(olderThanMs: Int64) async throws -> Int64 {
                pruneMediaCalled = true
                return 0
            }
            override func pruneSyncedResponses(olderThanMs: Int64) async throws -> Int {
                pruneRecordsCalled = true
                return 0
            }
        }
        
        let spy = SpyRepo()
        try await spy.saveResponse(buildResponse(id: "resp-0"))
        
        let engine = SyncEngine(
            repository: spy,
            apiService: allSucceedApi(),
            devicePolicy: normalPolicy(),
            errorClassifier: NetworkErrorClassifier()
        )
        
        _ = await engine.sync()

        XCTAssertTrue(spy.pruneMediaCalled, "pruneUploadedMedia should be called")
        XCTAssertTrue(spy.pruneRecordsCalled, "pruneSyncedResponses should be called")
    }

    // MARK: - Helpers

    /// Factory method to build a SyncEngine with specific test mocks.
    private func makeEngine(
        api: SurveyApiService,
        devicePolicy: DevicePolicyEvaluator = normalPolicy(),
        classifier: NetworkErrorClassifier = NetworkErrorClassifier(consecutiveFailureThreshold: 1)
    ) -> SyncEngine {
        return TestSyncEngineFactory.create(
            repo: repo,
            api: api,
            devicePolicy: devicePolicy,
            classifier: classifier
        )
    }
}
