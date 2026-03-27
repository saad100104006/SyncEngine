//
//  SurveyDTOs.swift
//  SurveySyncEngineIOS
//
//

import Foundation

/// Data Transfer Object representing the server's acknowledgment of a successful survey upload.
public struct UploadResponseDto {
    // The unique identifier assigned to the survey by the remote server's database
    public let serverId: String
    
    // The timestamp (in milliseconds) indicating when the server successfully processed the request
    public let receivedAt: Int64
}

/// Data Transfer Object representing the server's acknowledgment of a successful media attachment upload.
public struct AttachmentUploadDto {
    // The unique identifier of the attachment, confirming which file was processed
    public let attachmentId: String
    
    // The permanent remote URL where the file is now hosted (e.g., S3 or Cloud Storage bucket)
    public let serverUrl: String
}
