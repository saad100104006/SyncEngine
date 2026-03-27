//
//  ErrorHandlingTests.swift
//  SurveySyncEngineIOS
//
//

import XCTest

/// Unit tests for the Error Mapping logic and the Network Status Classifier.
/// These tests ensure that raw iOS network errors and server status codes are correctly
/// categorized into domain-specific SyncErrors, and that the engine's "early abort"
/// logic functions accurately during flaky network conditions.
final class ErrorHandlingTests: XCTestCase {

    // MARK: - Error Mapping Tests
    
    /// Verifies that a standard iOS URLError for a missing host is mapped to our .networkUnavailable case.
    func test_URLError_CannotFindHost_MapsTo_NetworkUnavailable() {
        let nsError = URLError(.cannotFindHost)
        let error = nsError.toSyncError()
        
        XCTAssertTrue(error.isNetworkUnavailable)
        XCTAssertTrue(error.isNetworkLevel())
        XCTAssertTrue(error.isRetryable())
    }

    /// Verifies that a connection timeout is mapped to the .timeout case and flagged as retryable.
    func test_URLError_TimedOut_MapsTo_Timeout() {
        let nsError = URLError(.timedOut)
        let error = nsError.toSyncError()
        
        XCTAssertTrue(error.isTimeout)
        XCTAssertTrue(error.isNetworkLevel())
        XCTAssertTrue(error.isRetryable())
    }

    /// Verifies that 4xx Client Errors are mapped correctly and marked as non-retryable
    /// (since a 400 usually implies the request itself is malformed).
    func test_HTTP_400_MapsTo_ClientError_AndIsNotRetryable() {
        let httpException = SurveyHttpException(httpCode: 400, message: "Bad Request")
        let error = httpException.toSyncError()
        
        XCTAssertTrue(error.isClientError)
        XCTAssertEqual(error.httpCode, 400)
        XCTAssertFalse(error.isRetryable())
        XCTAssertFalse(error.isNetworkLevel())
    }

    /// Verifies that 5xx Server Errors are mapped correctly and marked as retryable.
    func test_HTTP_500_MapsTo_ServerError_AndIsRetryable() {
        let httpException = SurveyHttpException(httpCode: 500, message: "Internal Server Error")
        let error = httpException.toSyncError()
        
        XCTAssertTrue(error.isServerError)
        XCTAssertEqual(error.httpCode, 500)
        XCTAssertTrue(error.isRetryable())
    }

    /// Ensures that any unrecognized Swift Error is safely caught as an .unknown case.
    func test_Unknown_Exception_MapsTo_UnknownError() {
        struct RandomError: Error {}
        let error = RandomError().toSyncError()
        
        XCTAssertTrue(error.isUnknown)
        XCTAssertFalse(error.isRetryable())
    }

    /// Validates that every error case provides a descriptive message for the user interface.
    func test_AllErrorTypes_ProduceNonEmptyUserFacingMessages() {
        let errors: [SyncError] = [
            .networkUnavailable(URLError(.cannotFindHost)),
            .timeout(URLError(.timedOut)),
            .clientError(httpCode: 400, serverMessage: "bad request"),
            .serverError(httpCode: 500, serverMessage: "server error"),
            .unknown(URLError(.unknown))
        ]
        
        for error in errors {
            let message = error.userFacingMessage()
            XCTAssertFalse(message.isEmpty, "Expected non-empty message for \(error)")
        }
    }

    // MARK: - NetworkErrorClassifier Tests

    /// Ensures the classifier doesn't trigger an abort signal after only one failure.
    func test_Classifier_DoesNotAbortBeforeThreshold() {
        let classifier = NetworkErrorClassifier(consecutiveFailureThreshold: 2)
        classifier.recordFailure(.networkUnavailable(URLError(.cannotFindHost)))
        
        XCTAssertFalse(classifier.shouldAbort())
    }

    /// Ensures the classifier correctly triggers an abort once the consecutive threshold is reached.
    func test_Classifier_AbortsAtThreshold() {
        let classifier = NetworkErrorClassifier(consecutiveFailureThreshold: 2)
        
        classifier.recordFailure(.networkUnavailable(URLError(.cannotFindHost)))
        classifier.recordFailure(.timeout(URLError(.timedOut)))
        
        XCTAssertTrue(classifier.shouldAbort())
    }

    /// Verifies that a single success resets the consecutive failure counter to zero.
    func test_SuccessfulUpload_ResetsConsecutiveCounter() {
        let classifier = NetworkErrorClassifier(consecutiveFailureThreshold: 2)
        
        classifier.recordFailure(.timeout(URLError(.timedOut)))
        XCTAssertEqual(classifier.consecutiveCount(), 1)

        classifier.recordSuccess()
        XCTAssertEqual(classifier.consecutiveCount(), 0)
        XCTAssertFalse(classifier.shouldAbort())
    }

    /// Confirms that logic errors (500s) do not trigger a network-down abort because the server was reachable.
    func test_ServerErrors_DoNotCountTowardNetworkDownThreshold() {
        let classifier = NetworkErrorClassifier(consecutiveFailureThreshold: 2)
        
        classifier.recordFailure(.serverError(httpCode: 500, serverMessage: "oops"))
        classifier.recordFailure(.serverError(httpCode: 500, serverMessage: "oops"))
        
        XCTAssertFalse(classifier.shouldAbort())
        XCTAssertEqual(classifier.consecutiveCount(), 0) // Counter resets because server was reached
        XCTAssertEqual(classifier.totalFailureCount(), 2)
    }

    /// Tests the "intermittent" failure scenario where a server error interrupts a streak of network timeouts.
    func test_MixedServerAndNetworkErrors_CounterResetsOnServerError() {
        let classifier = NetworkErrorClassifier(consecutiveFailureThreshold: 2)

        classifier.recordFailure(.networkUnavailable(URLError(.notConnectedToInternet)))
        XCTAssertEqual(classifier.consecutiveCount(), 1)

        // This should reset the consecutive counter
        classifier.recordFailure(.serverError(httpCode: 500, serverMessage: "oops"))
        XCTAssertEqual(classifier.consecutiveCount(), 0)

        classifier.recordFailure(.networkUnavailable(URLError(.timedOut)))
        XCTAssertEqual(classifier.consecutiveCount(), 1)
        XCTAssertFalse(classifier.shouldAbort())
    }

    /// Ensures the classifier can be fully cleared for a new sync session.
    func test_Classifier_CanBeResetBetweenSyncSessions() {
        let classifier = NetworkErrorClassifier(consecutiveFailureThreshold: 2)
        
        classifier.recordFailure(.timeout(URLError(.timedOut)))
        classifier.recordFailure(.timeout(URLError(.timedOut)))
        XCTAssertTrue(classifier.shouldAbort())

        classifier.reset()
        XCTAssertFalse(classifier.shouldAbort())
        XCTAssertEqual(classifier.consecutiveCount(), 0)
        XCTAssertEqual(classifier.totalFailureCount(), 0)
    }
}
