//
//  SyncWorkerHandler.swift
//  SurveySyncEngineIOS
//
import Foundation

enum WorkerResult: Equatable {
    case success(outputData: [String: Any])
    case retry
    case failure

    static func == (lhs: WorkerResult, rhs: WorkerResult) -> Bool {
        switch (lhs, rhs) {
        case (.retry, .retry), (.failure, .failure): return true
        case (.success(let l), .success(let r)):
            return (l[SyncWorker.KEY_RESULT_TYPE] as? String) == (r[SyncWorker.KEY_RESULT_TYPE] as? String)
        default: return false
        }
    }
}

/// A background worker responsible for executing a synchronization session.
///
/// This class acts as a bridge between the system's background task scheduler
/// and the `SyncEngine`. It maps domain-specific `SyncResult` outcomes into
/// system-level `WorkerResult` states.
public class SyncWorker {
    public static let KEY_RESULT_TYPE      = "resultType"
    public static let KEY_SUCCEEDED_COUNT  = "succeededCount"
    public static let KEY_FAILED_COUNT     = "failedCount"

    /// The engine instance used for the sync.
    /// Using 'any SyncEngineProtocol' allows for easy dependency injection of stubs.
    private let syncEngine: any SyncEngineProtocol

    /// Creates a new worker with the provided engine.
    public init(engine: any SyncEngineProtocol) {
        self.syncEngine = engine
    }

    /// Executes the sync and maps the result to a Worker-compatible format.
     func doWork() async -> WorkerResult {
        // Because syncEngine is a protocol-based Actor,
        // calling sync() is a safe, isolated async operation.
        switch await syncEngine.sync() {
            
        case .completed(let succeeded, let failed):
            return .success(outputData: [
                SyncWorker.KEY_RESULT_TYPE: "COMPLETED",
                SyncWorker.KEY_SUCCEEDED_COUNT: succeeded.count,
                SyncWorker.KEY_FAILED_COUNT: failed.count
            ])
            
        case .earlyTermination:
            // Signals to the system that the work should be retried later
            // (e.g., due to network loss or consecutive errors).
            return .retry
            
        case .nothingToSync:
            return .success(outputData: [SyncWorker.KEY_RESULT_TYPE: "NOTHING_TO_SYNC"])
            
        case .alreadyRunning:
            // We treat 'already running' as a success at the worker level
            // because the desired outcome (a sync occurring) is currently in flight.
            return .success(outputData: [SyncWorker.KEY_RESULT_TYPE: "ALREADY_RUNNING"])
            
        case .skipped(let reason):
            return .success(outputData: [
                SyncWorker.KEY_RESULT_TYPE: "SKIPPED",
                "reason": reason
            ])
            
        default:
            return .failure
        }
    }
}
