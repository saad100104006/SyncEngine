//
//  TestSyncEngineFactory.swift
//  SurveySyncEngineIOS
//
// .
//

import Foundation

// ---------------------------------------------------------------------------
// TestSyncEngineFactory
//
// This factory serves as the "Dependency Injection" hub for Unit and Integration tests.
// By centralizing the creation of the SyncEngine, we ensure that every test uses
// a consistent configuration of Fakes and Mocks, making the tests easier to maintain.
// ---------------------------------------------------------------------------
/// A namespace for creating pre-configured SyncEngine instances for testing.
/// Using a caseless enum prevents this utility from being instantiated.
public enum TestSyncEngineFactory {

    /**
     Creates a SyncEngine instance backed entirely by test doubles.
     
     - Parameters:
        - repo: The `FakeSurveyRepository` providing in-memory data persistence.
        - api: The `SurveyApiService` (usually a `FakeSurveyApiService`) to simulate network calls.
        - devicePolicy: A mock evaluator to simulate different hardware states (e.g., low battery).
        - classifier: A custom error classifier to test different network failure thresholds.
     - Returns: A fully functional `SyncEngine` ready for a test run.
     */
    public static func create(
        repo: FakeSurveyRepository,
        api: SurveyApiService,
        devicePolicy: DevicePolicyEvaluator = FakeDevicePolicyEvaluator(policy: SyncPolicy(shouldSync: true)),
        classifier: NetworkErrorClassifier = NetworkErrorClassifier(consecutiveFailureThreshold: 2)
    ) -> SyncEngine {
        
        return SyncEngine(
            // Dependency: The Repository.
            // Since FakeSurveyRepository conforms to the SurveyRepository protocol,
            // it is injected here to bypass the real Core Data implementation.
            repository: repo,
            
            // Dependency: The Network Layer.
            // Allows us to inject pre-planned success or failure sequences.
            apiService: api,
            
            // Dependency: Hardware Policy.
            // Allows us to toggle sync permission (e.g., return .skipped) during a test.
            devicePolicy: devicePolicy,
            
            // Dependency: Error Classification.
            // Used to test the "Fail Fast" logic when the network is unstable.
            errorClassifier: classifier,
            
            // Thread Safety: Mutex.
            // Injected to ensure that sync sessions are mutually exclusive,
            // preventing race conditions even in high-speed test environments.
            mutex: NSLock()
        )
    }
}
