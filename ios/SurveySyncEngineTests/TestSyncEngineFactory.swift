//
//  TestSyncEngineFactory.swift
//  SurveySyncEngineIOS
//
import Foundation

public enum TestSyncEngineFactory {
    /// Note: the `mutex: NSLock()` parameter from the class-based version
    /// has been removed. The actor runtime makes it unnecessary.
    public static func create(
        repo: FakeSurveyRepository,
        api: SurveyApiService,
        devicePolicy: DevicePolicyEvaluator = FakeDevicePolicyEvaluator(policy: SyncPolicy(shouldSync: true)),
        classifier: NetworkErrorClassifier = NetworkErrorClassifier(consecutiveFailureThreshold: 1)
    ) -> SyncEngine {
        return SyncEngine(
            repository:      repo,
            apiService:      api,
            devicePolicy:    devicePolicy,
            errorClassifier: classifier
        )
    }
}
