//
//  main.swift
//  SurveySyncEngineIOS
//

import Foundation
import CoreData
import Combine

/// This main entry point serves as the Integration Test for the entire Survey Sync Engine.
/// It wires together the Core Data stack, the Repository, the API, and the Engine to
/// demonstrate a full data lifecycle: Create -> Save -> Observe -> Sync -> Success.

print("🛠 Initializing Sync Engine Test Rig...")

// 1. Initialize our Storage & Repository
// Uses the singleton Core Data stack to provide a managed object context.
let context = CoreDataStack.shared.mainContext
let repository = SurveyRepositoryImpl(context: context)
let apiService = FakeSurveyApiService() // Uses the mock implementation to avoid real network calls

// 2. Setup Policy Evaluator
// Simulates ideal hardware conditions to ensure the engine doesn't throttle or skip the session.
let devicePolicy = DefaultDevicePolicyEvaluator(
    batteryPercentProvider: { 85 },                        // High battery
    isChargingProvider: { true },                          // Plugged in
    availableStorageBytesProvider: { 1024 * 1024 * 500 },  // 500MB free
    networkTypeProvider: { .wifi }                         // On WiFi
)

// 3. Create the Engine
// The brain of the operation, coordinating the data flow.
let engine = SyncEngine(
    repository: repository,
    apiService: apiService,
    devicePolicy: devicePolicy
)

// 4. Setup Progress Observation
// Uses Combine to listen to the progress stream and print real-time logs to the console.
var cancellables = Set<AnyCancellable>()
engine.progressPublisher
    .sink { progress in
        switch progress {
        case .itemUploading(let id, let index, let total):
            print("📤 [Progress] Uploading \(id) (\(index + 1)/\(total))")
        case .itemSucceeded(let id, _, _):
            print("✅ [Progress] Success: \(id)")
        case .itemFailed(let id, let error, _, _):
            print("❌ [Progress] Failed \(id): \(error.userFacingMessage())")
        case .finished(_):
            print("🏁 [Progress] Sync Logic Finished.")
        default: break
        }
    }
    .store(in: &cancellables)

// 5. Execution Block
// Wrap the async workflow in a Task to bridge between the synchronous main thread and async engine.
Task {
    do {
        // --- STEP 1: Create Dummy Data ---
        print("📝 Seeding mock survey response...")
        
        let responseId = UUID().uuidString
        let mockSurvey = SurveyResponse(
            id: responseId,
            farmerId: "FARMER-9921",
            surveyId: "SURVEY-2026A",
            status: .pending,
            sections: [
                ResponseSection(
                    surveyResponseId: responseId,
                    sectionKey: "farm_plot",
                    repetitionIndex: 0,
                    answers: ["crop": .text("Cassava")]
                )
            ]
        )
        
        // Save the domain model to the local database via the repository/mapper.
        try await repository.saveResponse(mockSurvey)
        print("💾 Survey saved to Core Data.")

        // --- STEP 2: Run the Sync ---
        print("🛰 Starting Sync Session...")
        let result = await engine.sync()

        // --- STEP 3: Print Final Status ---
        print("\n--- FINAL SYNC RESULT ---")
        switch result {
        case .completed(let succeeded, let failed):
            print("Status: COMPLETED")
            print("Succeeded: \(succeeded.count), Failed: \(failed.count)")
        case .nothingToSync:
            print("Status: NOTHING TO SYNC")
        case .skipped(let reason):
            print("Status: SKIPPED - \(reason)")
        case .earlyTermination(_, _, let reason, let remaining):
            print("Status: TERMINATED EARLY - \(reason.userFacingMessage())")
            print("Remaining: \(remaining)")
        case .alreadyRunning:
            print("Status: BUSY")
        }
        
        // Exit the test rig process successfully
        exit(0)
        
    } catch {
        print("❌ Fatal Error: \(error)")
        exit(1)
    }
}

// 6. Keep the process alive
// Necessary for command-line tools to prevent the process from ending before the Task finishes.
RunLoop.main.run()
