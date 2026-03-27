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

/// Adapts SyncEngine output to background scheduler lifecycle states.
/// Uses SyncEngineProtocol (not the concrete actor) so test doubles can be injected
/// without subclassing — which actors do not support.
class SyncWorker {
    static let KEY_RESULT_TYPE     = "resultType"
    static let KEY_SUCCEEDED_COUNT = "succeededCount"
    static let KEY_FAILED_COUNT    = "failedCount"

    // ACTOR FIX: changed from `SyncEngine` to `SyncEngineProtocol`.
    private let syncEngine: SyncEngineProtocol

    init(engine: SyncEngineProtocol) { self.syncEngine = engine }

    func doWork() async -> WorkerResult {
        switch await syncEngine.sync() {
        case .completed(let s, let f):
            return .success(outputData: [SyncWorker.KEY_RESULT_TYPE: "COMPLETED",
                                          SyncWorker.KEY_SUCCEEDED_COUNT: s.count,
                                          SyncWorker.KEY_FAILED_COUNT: f.count])
        case .earlyTermination:
            return .retry
        case .nothingToSync:
            return .success(outputData: [SyncWorker.KEY_RESULT_TYPE: "NOTHING_TO_SYNC"])
        case .alreadyRunning:
            return .success(outputData: [SyncWorker.KEY_RESULT_TYPE: "ALREADY_RUNNING"])
        case .skipped:
            return .success(outputData: [SyncWorker.KEY_RESULT_TYPE: "SKIPPED"])
        default:
            return .failure
        }
    }
}
