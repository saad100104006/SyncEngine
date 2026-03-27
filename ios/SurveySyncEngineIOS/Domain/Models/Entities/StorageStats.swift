//
//  StorageStats.swift
//  SurveySyncEngineIOS
//
//

import Foundation

/// A data structure representing the current state of local storage and device capacity.
/// Used primarily for UI dashboards, diagnostics, and pruning logic.
public struct StorageStats {
    // Total size in bytes of all survey data and attachments currently awaiting synchronization
    public var totalPendingBytes: Int64
    
    // Total size in bytes of surveys and media that have been successfully uploaded but still reside on the device
    public var totalSyncedBytes: Int64
    
    // The actual remaining storage capacity on the physical iOS device
    public var availableDeviceBytes: Int64
    
    // The total number of media files (images, videos, etc.) currently tracked by the database
    public var attachmentCount: Int
    
    // MARK: - SwiftUI Support
    
    /// A helper property providing mock data to render consistent layouts in SwiftUI Previews.
    public static var previewData: StorageStats {
        StorageStats(
            totalPendingBytes: 25_500_000,   // Roughly 25.5 MB of data to be uploaded
            totalSyncedBytes: 1_200_000_000, // Roughly 1.2 GB of historical data
            availableDeviceBytes: 45_000_000_000, // Roughly 45 GB of free phone space
            attachmentCount: 142
        )
    }
}
