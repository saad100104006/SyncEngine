//
//  StatusEnums.swift
//  SurveySyncEngineIOS
//
import Foundation

public enum SyncStatus: String, Codable {
    /// Saved locally, never attempted.
    case pending     = "PENDING"
    /// Currently being uploaded.
    case inProgress  = "IN_PROGRESS"
    /// Server confirmed receipt.
    case synced      = "SYNCED"
    /// Transient failure (network/5xx) — WILL be retried.
    case failed      = "FAILED"
    // FIX Bug 2: was "dead" (lowercase). Core Data predicates comparing
    // statusValue against SyncStatus.dead.rawValue would silently match
    // nothing, causing dead responses to re-appear in getPendingResponses()
    // and be retried forever.
    /// Permanent server rejection (4xx) — will NOT be retried.
    case dead        = "DEAD"
}

public enum UploadStatus: String, Codable {
    case pending    = "PENDING"
    case uploaded   = "UPLOADED"
    case failed     = "FAILED"
}
