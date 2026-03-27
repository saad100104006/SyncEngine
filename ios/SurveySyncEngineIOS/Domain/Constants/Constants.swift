//
//  Constants.swift
//  SurveySyncEngineIOS
//
//

import Foundation

/// Global configuration values and thresholds for the Survey Sync Engine.
struct Constants {
    // Artificial delay applied when the device is in a low battery state to throttle background processing
    static let lowBatteryDelay: TimeInterval = 0.2 // 200ms expressed as seconds
    
    // The minimum battery percentage required to perform intensive sync operations without throttling
    static let minBatteryPercent = 15
    
    // The safety threshold for device storage (50 MB); sync may pause if available space falls below this
    static let minStorageBytes: Int64 = 50 * 1024 * 1024
    
    // The maximum allowed data transfer size (10 MB) when the user is on a metered (cellular) connection
    static let meteredMaxBytes: Int64 = 10 * 1024 * 1024
}
