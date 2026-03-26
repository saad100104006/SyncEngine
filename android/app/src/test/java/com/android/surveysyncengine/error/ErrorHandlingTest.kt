package com.android.surveysyncengine.error

import com.surveysyncengine.domain.error.SurveyHttpException
import com.surveysyncengine.domain.error.SyncError
import com.surveysyncengine.domain.error.toSyncError
import com.surveysyncengine.sync.NetworkErrorClassifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

class ErrorHandlingTest {

    // ======================================================================
    // Throwable → SyncError mapping
    // ======================================================================

    @Test
    fun `UnknownHostException maps to NetworkUnavailable`() {
        val error = UnknownHostException("Unable to resolve host").toSyncError()
        assertTrue(error is SyncError.NetworkUnavailable)
        assertTrue(error.isNetworkLevel())
        assertTrue(error.isRetryable())
    }

    @Test
    fun `ConnectException maps to NetworkUnavailable`() {
        val error = ConnectException("Connection refused").toSyncError()
        assertTrue(error is SyncError.NetworkUnavailable)
        assertTrue(error.isNetworkLevel())
    }

    @Test
    fun `SocketTimeoutException maps to Timeout`() {
        val error = SocketTimeoutException("Read timed out").toSyncError()
        assertTrue(error is SyncError.Timeout)
        assertTrue(error.isNetworkLevel())
        assertTrue(error.isRetryable())
    }

    @Test
    fun `HTTP 400 maps to ClientError and is not retryable`() {
        val error = SurveyHttpException(400, "Bad Request").toSyncError()
        assertTrue(error is SyncError.ClientError)
        assertEquals(400, (error as SyncError.ClientError).httpCode)
        assertFalse(error.isRetryable())
        assertFalse(error.isNetworkLevel())
    }

    @Test
    fun `HTTP 422 maps to ClientError`() {
        val error = SurveyHttpException(422, "Unprocessable Entity").toSyncError()
        assertTrue(error is SyncError.ClientError)
        assertFalse(error.isRetryable())
    }

    @Test
    fun `HTTP 500 maps to ServerError and is retryable`() {
        val error = SurveyHttpException(500, "Internal Server Error").toSyncError()
        assertTrue(error is SyncError.ServerError)
        assertEquals(500, (error as SyncError.ServerError).httpCode)
        assertTrue(error.isRetryable())
        assertFalse(error.isNetworkLevel())
    }

    @Test
    fun `HTTP 503 maps to ServerError and is retryable`() {
        val error = SurveyHttpException(503, "Service Unavailable").toSyncError()
        assertTrue(error is SyncError.ServerError)
        assertTrue(error.isRetryable())
    }

    @Test
    fun `unknown exception maps to Unknown error`() {
        val error = RuntimeException("Something unexpected").toSyncError()
        assertTrue(error is SyncError.Unknown)
        // Unknown is not retryable — we don't know if it's safe to retry
        assertFalse(error.isRetryable())
    }

    @Test
    fun `all error types produce non-blank user-facing messages`() {
        val errors = listOf(
            SyncError.NetworkUnavailable(UnknownHostException("x")),
            SyncError.Timeout(SocketTimeoutException("x")),
            SyncError.ClientError(400, "bad request"),
            SyncError.ServerError(500, "server error"),
            SyncError.Unknown(RuntimeException("x")),
        )
        errors.forEach { error ->
            assertTrue(
                "Expected non-blank message for $error",
                error.userFacingMessage().isNotBlank(),
            )
        }
    }

    // ======================================================================
    // NetworkErrorClassifier
    // ======================================================================

    @Test
    fun `classifier does not abort before threshold`() {
        val classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 2)
        classifier.recordFailure(SyncError.NetworkUnavailable(UnknownHostException()))
        assertFalse(classifier.shouldAbort())
    }

    @Test
    fun `classifier aborts at threshold`() {
        val classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 2)
        classifier.recordFailure(SyncError.NetworkUnavailable(UnknownHostException()))
        classifier.recordFailure(SyncError.Timeout(SocketTimeoutException()))
        assertTrue(classifier.shouldAbort())
    }

    @Test
    fun `successful upload resets consecutive counter`() {
        val classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 2)
        classifier.recordFailure(SyncError.Timeout(SocketTimeoutException()))
        assertEquals(1, classifier.consecutiveCount())

        classifier.recordSuccess()
        assertEquals(0, classifier.consecutiveCount())
        assertFalse(classifier.shouldAbort())
    }

    @Test
    fun `server errors do not count toward network-down threshold`() {
        val classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 2)
        classifier.recordFailure(SyncError.ServerError(500, "oops"))
        classifier.recordFailure(SyncError.ServerError(500, "oops"))
        classifier.recordFailure(SyncError.ServerError(500, "oops"))

        // Three server errors should NOT trigger network abort
        assertFalse(classifier.shouldAbort())
        assertEquals(0, classifier.consecutiveCount())
        assertEquals(3, classifier.totalFailureCount())
    }

    @Test
    fun `client errors do not count toward network-down threshold`() {
        val classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 2)
        classifier.recordFailure(SyncError.ClientError(400, "bad"))
        classifier.recordFailure(SyncError.ClientError(422, "invalid"))

        assertFalse(classifier.shouldAbort())
    }

    @Test
    fun `mixed server and network errors counter resets on server error`() {
        val classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 2)

        // One network failure
        classifier.recordFailure(SyncError.NetworkUnavailable(UnknownHostException()))
        assertEquals(1, classifier.consecutiveCount())

        // A server error resets the consecutive counter (it's not a network-level event)
        classifier.recordFailure(SyncError.ServerError(500, "oops"))
        assertEquals(0, classifier.consecutiveCount())

        // Another network failure — counter starts fresh
        classifier.recordFailure(SyncError.NetworkUnavailable(UnknownHostException()))
        assertEquals(1, classifier.consecutiveCount())
        assertFalse(classifier.shouldAbort())
    }

    @Test
    fun `classifier can be reset between sync sessions`() {
        val classifier = NetworkErrorClassifier(consecutiveFailureThreshold = 2)
        classifier.recordFailure(SyncError.Timeout(SocketTimeoutException()))
        classifier.recordFailure(SyncError.Timeout(SocketTimeoutException()))
        assertTrue(classifier.shouldAbort())

        classifier.reset()
        assertFalse(classifier.shouldAbort())
        assertEquals(0, classifier.consecutiveCount())
        assertEquals(0, classifier.totalFailureCount())
    }
}
