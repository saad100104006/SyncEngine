//
//  SurveyMapper.swift
//  Agricultural_Survey
//
//  Created by User on 3/25/26.
//
import Foundation
import CoreData

/// A utility structure responsible for transforming data between Core Data managed objects (CD) and thread-safe Domain models.
public struct SurveyMapper {
    
    // MARK: - 1. Map Response (Core Data -> Domain)
    /// Converts a persistent Core Data survey record into a Domain-level SurveyResponse.
    public static func toDomain(cdSurvey: CDSurveyResponse) -> SurveyResponse {
        // Resolve the sync status from the stored string value
        let status = SyncStatus(rawValue: cdSurvey.statusValue) ?? .pending
        
        // Map and SORT Sections by repetitionIndex to ensure the UI renders them in the correct sequential order
        let cdSections = cdSurvey.sections?.allObjects as? [CDSurveySection] ?? []
        let domainSections = cdSections
            .map { toDomain(cdSection: $0) }
            .sorted { $0.repetitionIndex < $1.repetitionIndex }
        
        // Convert the set of Core Data attachments into an array of Domain attachments
        let cdAttachments = cdSurvey.attachments?.allObjects as? [CDSurveyAttachment] ?? []
        let domainAttachments = cdAttachments.map { toDomain(cdAttachment: $0) }
        
        // Convert Date objects to Int64 milliseconds for consistent cross-platform/API compatibility
        let createdAtDate = cdSurvey.createdAt ?? Date()
        let createdAtInt64 = Int64(createdAtDate.timeIntervalSince1970 * 1000)
        
        // Safely handle the optional synchronization timestamp
        let syncedAtInt64 = cdSurvey.syncedAt.map { Int64($0.timeIntervalSince1970 * 1000) }
        
        return SurveyResponse(
            id: cdSurvey.id?.uuidString ?? UUID().uuidString,
            farmerId: cdSurvey.farmerId ?? "",
            surveyId: cdSurvey.surveyId ?? "",
            status: status,
            sections: domainSections,
            attachments: domainAttachments,
            failureReason: cdSurvey.failureReason,
            retryCount: Int(cdSurvey.retryCount),
            createdAt: createdAtInt64,
            syncedAt: syncedAtInt64,
            localStorageBytes: cdSurvey.localStorageBytes
        )
    }
    
    // MARK: - 2. Map Section (Core Data -> Domain)
    /// Converts a Core Data section entity into a Domain-level ResponseSection, including its nested answers.
    public static func toDomain(cdSection: CDSurveySection) -> ResponseSection {
        var answersDict: [String: AnswerValue] = [:]
        
        if let cdAnswers = cdSection.answers?.allObjects as? [CDAnswer] {
            for cdAnswer in cdAnswers {
                // Map each answer to its corresponding key in the dictionary
                let key = cdAnswer.key ?? "unknown_key"
                answersDict[key] = toDomain(cdAnswer: cdAnswer)
            }
        }
        
        return ResponseSection(
            id: cdSection.id?.uuidString ?? UUID().uuidString,
            surveyResponseId: cdSection.survey?.id?.uuidString ?? "",
            sectionKey: cdSection.sectionKey ?? "",
            repetitionIndex: Int(cdSection.repetitionIndex),
            answers: answersDict
        )
    }
    
    // MARK: - 3. Map Answer Enum (Core Data -> Domain)
    /// Decodes the flattened Core Data answer record back into the strongly-typed AnswerValue enum.
    private static func toDomain(cdAnswer: CDAnswer) -> AnswerValue {
        let type = cdAnswer.answerTypeValue ?? "skipped"
        
        // Switch based on the stored type string to retrieve the correct payload
        switch type {
        case "text":
            return .text(cdAnswer.textValue ?? "")
        case "number":
            return .number(cdAnswer.numberValue)
        case "bool":
            return .bool(cdAnswer.boolValue)
        case "gps":
            return .gpsCoordinate(lat: cdAnswer.lat, lng: cdAnswer.lng, accuracyMeters: cdAnswer.accuracy)
        case "multiChoice":
            return .multiChoice(cdAnswer.multiChoiceValues ?? [])
        case "skipped":
            return .skipped
        default:
            return .skipped
        }
    }
    
    // MARK: - 4. Map Attachment (Core Data -> Domain)
    /// Converts a persistent attachment record into a Domain-level MediaAttachment model.
    public static func toDomain(cdAttachment: CDSurveyAttachment) -> MediaAttachment {
        let uploadStatus = UploadStatus(rawValue: cdAttachment.uploadStatusValue) ?? .pending
        
        // Convert Core Data Date to Int64 milliseconds
        let createdDate = cdAttachment.createdAt ?? Date()
        let createdAtInt64 = Int64(createdDate.timeIntervalSince1970 * 1000)
        
        return MediaAttachment(
            id: cdAttachment.id?.uuidString ?? UUID().uuidString,
            surveyResponseId: cdAttachment.survey?.id?.uuidString ?? "",
            localFilePath: cdAttachment.localFilePath ?? "",
            mimeType: cdAttachment.mimeType ?? "",
            sizeBytes: cdAttachment.sizeBytes,
            uploadStatus: uploadStatus,
            serverUrl: cdAttachment.serverUrl,
            createdAt: createdAtInt64
        )
    }
    
    // MARK: - 5. Map Swift Domain -> Core Data
    /// Creates and populates a Core Data CDSurveyResponse from a Domain-level SurveyResponse object.
    public static func toCoreData(survey: SurveyResponse, context: NSManagedObjectContext) -> CDSurveyResponse {
        let cdSurvey = CDSurveyResponse(context: context)
        
        // Map top-level properties
        cdSurvey.id = UUID(uuidString: survey.id) ?? UUID()
        cdSurvey.farmerId = survey.farmerId
        cdSurvey.surveyId = survey.surveyId
        cdSurvey.statusValue = survey.status.rawValue
        cdSurvey.failureReason = survey.failureReason
        cdSurvey.retryCount = Int64(survey.retryCount)
        cdSurvey.localStorageBytes = survey.localStorageBytes
        
        // Convert Int64 milliseconds back to Foundation Date objects for Core Data
        cdSurvey.createdAt = Date(timeIntervalSince1970: TimeInterval(survey.createdAt) / 1000.0)
        if let syncedAt = survey.syncedAt {
            cdSurvey.syncedAt = Date(timeIntervalSince1970: TimeInterval(syncedAt) / 1000.0)
        }
        
        // Recursively map and link child sections
        for section in survey.sections {
            let cdSection = toCoreData(section: section, context: context)
            cdSection.survey = cdSurvey // Established Inverse Relationship
        }
        
        // Recursively map and link child attachments
        for attachment in survey.attachments {
            let cdAttachment = toCoreData(attachment: attachment, context: context)
            cdAttachment.survey = cdSurvey // Established Inverse Relationship
        }
        
        return cdSurvey
    }
    
    /// Creates and populates a CDSurveySection, including its dictionary of answers.
    public static func toCoreData(section: ResponseSection, context: NSManagedObjectContext) -> CDSurveySection {
        let cdSection = CDSurveySection(context: context)
        cdSection.id = UUID(uuidString: section.id) ?? UUID()
        cdSection.sectionKey = section.sectionKey
        cdSection.repetitionIndex = Int64(section.repetitionIndex)
        
        // Iterate through the dictionary and create individual CDAnswer records
        for (key, value) in section.answers {
            let cdAnswer = CDAnswer(context: context)
            cdAnswer.key = key
            cdAnswer.section = cdSection // Link Answer to Section
            
            // Map the enum case back to the flattened Core Data attributes
            switch value {
            case .text(let text):
                cdAnswer.answerTypeValue = "text"
                cdAnswer.textValue = text
            case .number(let num):
                cdAnswer.answerTypeValue = "number"
                cdAnswer.numberValue = num
            case .bool(let bool):
                cdAnswer.answerTypeValue = "bool"
                cdAnswer.boolValue = bool
            case .gpsCoordinate(let lat, let lng, let acc):
                cdAnswer.answerTypeValue = "gps"
                cdAnswer.lat = lat
                cdAnswer.lng = lng
                cdAnswer.accuracy = acc
            case .multiChoice(let choices):
                cdAnswer.answerTypeValue = "multiChoice"
                cdAnswer.multiChoiceValues = choices
            case .skipped:
                cdAnswer.answerTypeValue = "skipped"
            case .gpsBoundary(let points):
                cdAnswer.answerTypeValue = "gpsBoundary"
                
                // Encode the boundary point array into binary Data for storage
                do {
                    let encodedData = try JSONEncoder().encode(points)
                    cdAnswer.boundaryData = encodedData
                } catch {
                    print("Failed to encode boundary points: \(error)")
                }
            }
        }
        
        return cdSection
    }

    /// Creates and populates a CDSurveyAttachment from a Domain MediaAttachment.
    public static func toCoreData(attachment: MediaAttachment, context: NSManagedObjectContext) -> CDSurveyAttachment {
        let cdAttachment = CDSurveyAttachment(context: context)
        cdAttachment.id = UUID(uuidString: attachment.id) ?? UUID()
        cdAttachment.localFilePath = attachment.localFilePath
        cdAttachment.mimeType = attachment.mimeType
        cdAttachment.sizeBytes = attachment.sizeBytes
        cdAttachment.uploadStatusValue = attachment.uploadStatus.rawValue
        cdAttachment.serverUrl = attachment.serverUrl
        
        // Ensure the timestamp is correctly converted from milliseconds to Date
        cdAttachment.createdAt = Date(timeIntervalSince1970: TimeInterval(attachment.createdAt) / 1000.0)
        
        return cdAttachment
    }
}
