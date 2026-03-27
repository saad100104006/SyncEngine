//
//  SurveyApiService.swift
//  SurveySyncEngineIOS
//

import Foundation

/// A protocol defining the required network operations for the Agricultural Survey system.
/// This abstraction allows the Sync Engine to remain agnostic of the underlying networking library (e.g., URLSession or Alamofire).
public protocol SurveyApiService {
    
    /// Sends a completed survey response to the remote server.
    /// - Parameter response: The Domain-level model containing all survey answers and metadata.
    /// - Returns: An UploadResponseDto containing the server-assigned ID and confirmation timestamp.
    /// - Throws: An error if the network is unreachable, the request times out, or the server returns a non-200 status code.
    func uploadSurveyResponse(response: SurveyResponse) async throws -> UploadResponseDto
    
    /// Uploads a single media file (image, document, etc.) associated with a specific survey.
    /// - Parameters:
    ///   - surveyResponseId: The unique identifier of the parent survey response.
    ///   - attachmentId: The unique identifier for this specific attachment.
    ///   - localFilePath: The disk location of the file to be uploaded.
    ///   - mimeType: The format of the file (e.g., "image/png") to set the correct HTTP Content-Type.
    /// - Returns: An AttachmentUploadDto containing the final remote URL of the uploaded file.
    /// - Throws: An error if the file cannot be read or the upload fails.
    func uploadAttachment(
        surveyResponseId: String,
        attachmentId: String,
        localFilePath: String,
        mimeType: String
    ) async throws -> AttachmentUploadDto
}
