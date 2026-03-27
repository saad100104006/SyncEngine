//
//  NetworkErrorClassifier.swift
//  SurveySyncEngineIOS
//
//

import Foundation

/**
 NetworkErrorClassifier
 
 This utility monitors the stability of the network connection during a sync session.
 Its primary purpose is to differentiate between isolated request failures and a
 total loss of connectivity, allowing the Sync Engine to abort early and conserve
 device battery/resources if the network is effectively down.
 */
public class NetworkErrorClassifier {
    // The number of back-to-back network failures allowed before deciding the connection is dead
    private let consecutiveFailureThreshold: Int
    private var consecutiveNetworkFailures = 0
    private var totalSessionFailures = 0

    /// Initializes the classifier with a custom threshold (defaults to 2).
    public init(consecutiveFailureThreshold: Int = 2) {
        self.consecutiveFailureThreshold = consecutiveFailureThreshold
    }

    /// Resets the consecutive failure counter.
    /// Should be called immediately after any successful API response to signal a healthy connection.
    public func recordSuccess() {
        consecutiveNetworkFailures = 0
    }

    /// Updates failure counters based on the type of error encountered.
    /// - Parameter error: The SyncError returned from the network layer.
    public func recordFailure(_ error: SyncError) {
        totalSessionFailures += 1
        
        // Check if the error is a connectivity issue (timeout/unreachable) vs a server logic error
        if error.isNetworkLevel() {
            consecutiveNetworkFailures += 1
        } else {
            // If the server returns a 4xx or 5xx, the network is technically functional.
            // Therefore, we reset the consecutive counter as we aren't "disconnected".
            consecutiveNetworkFailures = 0
        }
    }

    /// Determines if the sync session should be halted early.
    /// - Returns: True if consecutive network-level failures meet or exceed the threshold.
    public func shouldAbort() -> Bool {
        return consecutiveNetworkFailures >= consecutiveFailureThreshold
    }

    /// Completely clears all session stats for a fresh synchronization run.
    public func reset() {
        consecutiveNetworkFailures = 0
        totalSessionFailures = 0
    }

    // MARK: - Inspection Helpers (Diagnostic methods for Unit Tests)

    /// Returns the current count of back-to-back network-level failures.
    public func consecutiveCount() -> Int {
        return consecutiveNetworkFailures
    }

    /// Returns the total number of failures (of any type) encountered during the session.
    public func totalFailureCount() -> Int {
        return totalSessionFailures
    }
}
