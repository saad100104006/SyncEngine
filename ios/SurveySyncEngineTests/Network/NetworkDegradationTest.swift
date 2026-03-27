//
//  NetworkDegradationTests.swift
//  SurveySyncEngineIOS
//

import XCTest

/// Integration tests specifically focused on the Sync Engine's resilience and "fail-fast" behavior.
/// These tests verify that the engine correctly identifies a degraded network environment and
/// terminates the session early to preserve device resources, while ensuring it can resume
/// once conditions improve.
final class NetworkDegradationTests: XCTestCase {

    private var repo: FakeSurveyRepository!

    override func setUp() {
        super.setUp()
        // Using a thread-safe Fake Repository to track status changes during the sync loop
        repo = FakeSurveyRepository()
    }

    /// Verifies that if the threshold is set to 1, the engine immediately stops upon the first network error.
    func test_thresholdOf1_stopsAtFirstNetworkFailure() async throws {
        // GIVEN: 5 pending surveys
        for i in 0...4 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }
        
        // Configure API to timeout on the 3rd item (index 2)
        let engine = TestSyncEngineFactory.create(
            repo: repo,
            api: timeoutAtIndexApi(indices: 2),
            classifier: NetworkErrorClassifier(consecutiveFailureThreshold: 1)
        )

        // WHEN: Sync is executed
        let result = await engine.sync()

        // THEN: The result should be an early termination
        guard case let .earlyTermination(succeeded, failedBeforeStop, _, remainingCount) = result else {
            XCTFail("Expected .earlyTermination but got \(result)")
            return
        }

        XCTAssertEqual(succeeded.count, 2)          // resp-0 and resp-1 succeeded
        XCTAssertEqual(failedBeforeStop.count, 1)   // resp-2 failed and triggered the stop
        XCTAssertEqual(remainingCount, 2)           // resp-3 and resp-4 were never attempted
    }

    /// Verifies that the engine handles multiple consecutive failures correctly based on the threshold.
    func test_thresholdOf3_allowsTwoConsecutiveFailuresBeforeStopping() async throws {
        // GIVEN: 10 pending surveys
        for i in 0...9 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }
        
        // Timeouts at 4, 5, and 6. Threshold is 3, so it should stop AFTER the 3rd failure (index 6).
        let engine = TestSyncEngineFactory.create(
            repo: repo,
            api: timeoutAtIndexApi(indices: 4, 5, 6),
            classifier: NetworkErrorClassifier(consecutiveFailureThreshold: 3)
        )

        // WHEN: Sync is executed
        let result = await engine.sync()

        // THEN: Verify the split between succeeded, failed, and unattempted
        guard case let .earlyTermination(succeeded, failedBeforeStop, _, remainingCount) = result else {
            XCTFail("Expected .earlyTermination but got \(result)")
            return
        }

        XCTAssertEqual(succeeded.count, 4)          // resp 0-3 succeeded
        XCTAssertEqual(failedBeforeStop.count, 3)   // resp 4-6 failed
        XCTAssertEqual(remainingCount, 3)           // resp 7-9 remaining
    }

    /// Ensures that 'No Network' (UnknownHost) errors trigger the same abort logic as timeouts.
    func test_noNetworkError_triggersEarlyStopSameAsTimeout() async throws {
        // GIVEN
        for i in 0...5 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }
        let engine = TestSyncEngineFactory.create(
            repo: repo,
            api: noNetworkAtIndexApi(indices: 1, 2),
            classifier: NetworkErrorClassifier(consecutiveFailureThreshold: 2)
        )

        // WHEN
        let result = await engine.sync()

        // THEN
        if case .earlyTermination = result {
            // Success: NoNetwork treated as a network-level failure
        } else {
            XCTFail("Expected .earlyTermination but got \(result)")
        }
    }

    /// Critical check: Verifies that items following an early termination remain in their original PENDING state.
    func test_remainingResponses_areNotTouchedAfterEarlyStop() async throws {
            // GIVEN: 8 surveys
            for i in 0...7 {
                try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
            }
            
            let engine = TestSyncEngineFactory.create(
                repo: repo,
                api: timeoutAtIndexApi(indices: 2, 3),
                classifier: NetworkErrorClassifier(consecutiveFailureThreshold: 2)
            )

            // WHEN: Sync stops at index 3
            _ = await engine.sync()

            // THEN:
            // 1. Items 4-7 must remain PENDING
            for i in 4...7 {
                let status = try await repo.statusOf(id: "resp-\(i)")
                XCTAssertEqual(status, .pending, "Response \(i) should remain PENDING")
            }
            
            // 2. Items 2 and 3 must be marked FAILED (for retry later)
            let status2 = try await repo.statusOf(id: "resp-2")
            let status3 = try await repo.statusOf(id: "resp-3")
            XCTAssertEqual(status2, .failed)
            XCTAssertEqual(status3, .failed)
            
            // 3. Items 0 and 1 must be SYNCED
            let status0 = try await repo.statusOf(id: "resp-0")
            let status1 = try await repo.statusOf(id: "resp-1")
            XCTAssertEqual(status0, .synced)
            XCTAssertEqual(status1, .synced)
        }
    
    /// Verifies that items skipped during an early termination are processed in a subsequent sync if the network recovers.
    func test_earlyTermination_onSecondSyncAfterNetworkRecovers_processesRemaining() async throws {
        // GIVEN
        for i in 0...5 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }

        // Run 1: Network dies at index 1
        let engine1 = TestSyncEngineFactory.create(
            repo: repo,
            api: timeoutAtIndexApi(indices: 1, 2)
        )
        _ = await engine1.sync()

        // WHEN: Network recovers and a second sync starts
        let engine2 = TestSyncEngineFactory.create(
            repo: repo,
            api: allSucceedApi()
        )
        let result = await engine2.sync()

        // THEN: It should finish the queue
        guard case let .completed(succeeded, failed) = result else {
            XCTFail("Expected .completed but got \(result)")
            return
        }

        // Successfully processed the 5 items that were either FAILED or PENDING from Run 1
        XCTAssertEqual(succeeded.count, 5)
        XCTAssertTrue(failed.isEmpty)
    }

    /// Verifies that server-side errors (500s) do not contribute to a network-down termination.
    /// Logic: If the server returns a 500, the network is working, but the server is struggling.
    func test_serverErrors_interspersedWithNetworkErrors_doNotAccelerateAbort() async throws {
        // GIVEN: 9 surveys
        for i in 0...8 {
            try await repo.saveResponse(buildResponse(id: "resp-\(i)"))
        }

        // Pattern: network timeout -> server error -> no network
        // The server error (index 2) should reset the consecutive failure counter.
        let failurePlan: [Int: FailureType] = [
            1: .timeout,
            2: .serverError500,
            3: .noNetwork
        ]

        let engine = TestSyncEngineFactory.create(
            repo: repo,
            api: FakeSurveyApiService(
                failurePlan: failurePlan.map { index, type in
                    FailureInstruction(index, type)
                }
            ),
            classifier: NetworkErrorClassifier(consecutiveFailureThreshold: 2)
        )

        // WHEN: Sync is executed
        let result = await engine.sync()

        // THEN: It should NOT abort early because there weren't 2 CONSECUTIVE network-level failures.
        if case .completed = result {
            // Success: Processed the whole list (some failed, but loop finished)
        } else {
            XCTFail("Expected .completed (with some failed items) but got \(result)")
        }
    }
}
