//
//  StatusEnums.swift
//  SurveySyncEngineIOS
//
//

import Foundation

/// Defines the various synchronization states a SurveyResponse can inhabit during its lifecycle.
public enum SyncStatus: String, Codable {
    // Initial state: The survey is saved locally on the device but has not been queued for upload yet.
    case pending = "PENDING"
    
    // Active state: The Sync Engine is currently attempting to transmit this survey to the server.
    case inProgress = "IN_PROGRESS"
    
    // Final success state: The server has acknowledged receipt and returned a unique server-side ID.
    case synced = "SYNCED"
    
    // Recoverable error state: The last upload attempt failed due to network or server issues; the engine will retry.
    case failed = "FAILED"
    
    // Terminal error state: The survey has exceeded the maximum retry limit or encountered a non-recoverable client error.
    case dead = "dead"
}

/// Defines the specific upload states for individual MediaAttachments (images, videos, etc.).
public enum UploadStatus: String, Codable {
    // The file exists locally but hasn't been successfully uploaded to the storage server yet.
    case pending = "PENDING"
    
    // The file has been successfully uploaded, and a remote server URL has been retrieved.
    case uploaded = "UPLOADED"
    
    // The file upload failed; the parent survey's sync logic will determine if a retry is possible.
    case failed = "FAILED"
}
