//
//  NetworkErrorClassifier.swift
//  SurveySyncEngineIOS
//
import Foundation

/// Tracks consecutive network-level failures to decide when to abort early.
///
/// Default threshold = 1 (was 2).
/// Rationale: spec says "the 4th fails with a connection timeout — there are
/// still 6 more in the queue" — one timeout must stop the session.
/// Tests needing to survive one timeout pass threshold: 2 explicitly.
public class NetworkErrorClassifier {
    private let consecutiveFailureThreshold: Int
    private var consecutiveNetworkFailures = 0
    private var totalSessionFailures = 0

    // FIX Bug 4: default was 2, now 1.
    public init(consecutiveFailureThreshold: Int = 1) {
        self.consecutiveFailureThreshold = consecutiveFailureThreshold
    }

    public func recordSuccess() { consecutiveNetworkFailures = 0 }

    public func recordFailure(_ error: SyncError) {
        totalSessionFailures += 1
        if error.isNetworkLevel() {
            consecutiveNetworkFailures += 1
        } else {
            consecutiveNetworkFailures = 0
        }
    }

    public func shouldAbort() -> Bool {
        return consecutiveNetworkFailures >= consecutiveFailureThreshold
    }

    public func reset() {
        consecutiveNetworkFailures = 0
        totalSessionFailures = 0
    }

    public func consecutiveCount() -> Int { consecutiveNetworkFailures }
    public func totalFailureCount() -> Int { totalSessionFailures }
}
