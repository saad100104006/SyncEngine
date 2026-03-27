//
//  FakeDevicePolicyEvaluator.swift
//  SurveySyncEngineIOS
//
//

import Foundation

// MARK: - Fake for Tests & Previews
/// A mock implementation of DevicePolicyEvaluator designed for unit testing and SwiftUI previews.
/// It allows developers to manually inject a specific SyncPolicy to simulate various device
/// conditions (e.g., low battery, no storage, or metered connection) without needing real hardware sensors.
public class FakeDevicePolicyEvaluator: DevicePolicyEvaluator {
    
    // The policy that will be returned whenever evaluate() is called.
    // This can be updated dynamically during a test to simulate changing environments.
    public var policy: SyncPolicy
    
    /// Initializes the fake evaluator with a default "Go" policy (shouldSync = true).
    public init(policy: SyncPolicy = SyncPolicy(shouldSync: true)) {
        self.policy = policy
    }
    
    /// Returns the manually configured policy regardless of actual device hardware state.
    public func evaluate() -> SyncPolicy {
        return policy
    }
}
