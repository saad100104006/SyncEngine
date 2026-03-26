package com.surveysyncengine.sync

import com.surveysyncengine.domain.error.SyncError

// ---------------------------------------------------------------------------
// NetworkErrorClassifier
//
// Tracks consecutive network-level failures (timeout / unreachable) to decide
// when to abort a sync session early rather than burning battery on retries.
//
// Default threshold = 1: one network failure aborts the session immediately.
//
// Rationale: field agents work in areas where connectivity drops suddenly and
// completely. If one upload times out, the next almost certainly will too.
// The spec scenario confirms this: "after 3 successful uploads, the 4th fails
// with a connection timeout. There are still 6 more responses in the queue" —
// the engine stops at failure 4, it does not attempt the remaining 6.
//
// Tests that need to observe partial failures without triggering early
// termination should pass consecutiveFailureThreshold = 99 explicitly.
//
// Design note: we count *consecutive* failures, not total. A successful upload
// resets the counter. This prevents a corrupt payload that causes a TCP reset
// from being misclassified as a network outage.
//
// Known limitation: a server returning 503 with a valid HTTP response is
// classified as ServerError, not NetworkUnavailable, so it does not count
// toward the threshold. See totalSessionFailures for overall failure tracking.
// ---------------------------------------------------------------------------
class NetworkErrorClassifier(
    private val consecutiveFailureThreshold: Int = 1,
) {
    private var consecutiveNetworkFailures = 0
    private var totalSessionFailures = 0

    fun recordSuccess() {
        consecutiveNetworkFailures = 0
    }

    fun recordFailure(error: SyncError) {
        totalSessionFailures++
        if (error.isNetworkLevel()) {
            consecutiveNetworkFailures++
        } else {
            // Server or client errors don't count toward network-down detection
            consecutiveNetworkFailures = 0
        }
    }

    fun shouldAbort(): Boolean =
        consecutiveNetworkFailures >= consecutiveFailureThreshold

    fun reset() {
        consecutiveNetworkFailures = 0
        totalSessionFailures = 0
    }

    fun consecutiveCount(): Int = consecutiveNetworkFailures
    fun totalFailureCount(): Int = totalSessionFailures
}
