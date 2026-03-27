//
//  SurveyResponse.swift
//  Agricultural_Survey
//
//
import Foundation


// MARK: - Response Section
/// Represents a specific group of answers within a survey, allowing for repeating sections (e.g., multiple crops).
public struct ResponseSection {
    // Unique identifier for the section instance
    public var id: String = UUID().uuidString
    
    // Reference to the parent survey response this section belongs to
    public var surveyResponseId: String
    
    // The key mapping this data to the survey template (e.g., "livestock_inventory")
    public var sectionKey: String
    
    // The index used to order sections, especially when a section is repeated multiple times
    public var repetitionIndex: Int
    
    // A dictionary of answers where the key is the question identifier and the value is the user input
    public var answers: [String: AnswerValue]
}

// MARK: - Media Attachment
/// Represents a file (image, video, etc.) captured during the survey that needs to be uploaded.
public struct MediaAttachment {
    // Unique identifier for the attachment
    public var id: String = UUID().uuidString
    
    // Reference to the parent survey response associated with this file
    public var surveyResponseId: String
    
    // The path to the file on the local device's file system
    public var localFilePath: String
    
    // The standard MIME type of the file (e.g., "image/jpeg")
    public var mimeType: String
    
    // The size of the file in bytes
    public var sizeBytes: Int64
    
    // Current status of the file upload process (defaults to .pending)
    public var uploadStatus: UploadStatus = .pending
    
    // The remote URL where the file is stored after a successful upload
    public var serverUrl: String? = nil
    
    // Timestamp of when the attachment was created, in milliseconds since the Unix epoch
    public var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
}

// MARK: - Survey Response
/// The primary domain model representing a completed agricultural survey submitted by a farmer.
public struct SurveyResponse {
    // Unique identifier for the entire survey submission
    public var id: String = UUID().uuidString
    
    // The unique ID of the farmer being surveyed
    public var farmerId: String
    
    // The ID of the survey template being used
    public var surveyId: String
    
    // The overall synchronization state of the survey (e.g., .pending, .synced, .failed)
    public var status: SyncStatus = .pending
    
    // An array containing all data sections filled out during the survey
    public var sections: [ResponseSection] = []
    
    // An array of all media files associated with this specific submission
    public var attachments: [MediaAttachment] = []
    
    // Description of the error if the last synchronization attempt failed
    public var failureReason: String? = nil
    
    // Number of times the sync engine has attempted to upload this response
    public var retryCount: Int = 0
    
    // Timestamp of when the survey was started/created in milliseconds
    public var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    
    // Timestamp of when the survey was successfully synced to the server
    public var syncedAt: Int64? = nil
    
    // The total disk space consumed by this response and its attachments locally
    public var localStorageBytes: Int64 = 0
}
