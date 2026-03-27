//
//  DiagnosticsSnapshot.swift
//  SurveySyncEngineIOS
//
//

import Foundation

/// A data-heavy model representing a point-in-time "health check" of the synchronization system.
/// This is used by the UI and support logs to monitor the health of the local database and sync status.
public struct DiagnosticsSnapshot {
    // Number of surveys currently in the 'pending' state
    public let pendingCount: Int
    
    // Number of surveys that have failed their last upload attempt
    public let failedCount: Int
    
    // Number of surveys successfully synchronized but still stored in the local database
    public let syncedCount: Int
    
    // The age of the oldest survey awaiting sync (in milliseconds); nil if no surveys are pending
    public let oldestPendingAgeMs: Int64?
    
    // Total disk space (in bytes) occupied by all survey data and media files
    public let totalStorageBytes: Int64
    
    // A collection of recent error messages or event strings to help troubleshoot sync issues
    public let recentSyncErrors: [String]
    
    // The current free space remaining on the physical iOS/macOS device
    public let deviceStorageAvailableBytes: Int64
    
    /// Memberwise initializer for creating a snapshot from repository data.
    public init(
        pendingCount: Int,
        failedCount: Int,
        syncedCount: Int,
        oldestPendingAgeMs: Int64?,
        totalStorageBytes: Int64,
        recentSyncErrors: [String],
        deviceStorageAvailableBytes: Int64
    ) {
        self.pendingCount = pendingCount
        self.failedCount = failedCount
        self.syncedCount = syncedCount
        self.oldestPendingAgeMs = oldestPendingAgeMs
        self.totalStorageBytes = totalStorageBytes
        self.recentSyncErrors = recentSyncErrors
        self.deviceStorageAvailableBytes = deviceStorageAvailableBytes
    }
}
