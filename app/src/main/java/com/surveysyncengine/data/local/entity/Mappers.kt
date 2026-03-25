package com.surveysyncengine.data.local.entity

import com.surveysyncengine.data.local.converter.SurveyTypeConverters
import com.surveysyncengine.domain.model.MediaAttachment
import com.surveysyncengine.domain.model.ResponseSection
import com.surveysyncengine.domain.model.SurveyResponse

private val converters = SurveyTypeConverters()

// ---------------------------------------------------------------------------
// Aggregate → Domain
// ---------------------------------------------------------------------------

fun SurveyResponseAggregate.toDomain(): SurveyResponse = SurveyResponse(
    id = response.id,
    farmerId = response.farmerId,
    surveyId = response.surveyId,
    status = response.status,
    sections = sections.map { it.toDomain() },
    attachments = attachments.map { it.toDomain() },
    failureReason = response.failureReason,
    retryCount = response.retryCount,
    createdAt = response.createdAt,
    syncedAt = response.syncedAt,
    localStorageBytes = response.localStorageBytes,
)

fun ResponseSectionEntity.toDomain(): ResponseSection = ResponseSection(
    id = id,
    surveyResponseId = surveyResponseId,
    sectionKey = sectionKey,
    repetitionIndex = repetitionIndex,
    answers = converters.jsonToAnswers(answersJson),
)

fun MediaAttachmentEntity.toDomain(): MediaAttachment = MediaAttachment(
    id = id,
    surveyResponseId = surveyResponseId,
    localFilePath = localFilePath,
    mimeType = mimeType,
    sizeBytes = sizeBytes,
    uploadStatus = uploadStatus,
    serverUrl = serverUrl,
    createdAt = createdAt,
)

// ---------------------------------------------------------------------------
// Domain → Entity
// ---------------------------------------------------------------------------

fun SurveyResponse.toEntity(): SurveyResponseEntity = SurveyResponseEntity(
    id = id,
    farmerId = farmerId,
    surveyId = surveyId,
    status = status,
    failureReason = failureReason,
    retryCount = retryCount,
    createdAt = createdAt,
    syncedAt = syncedAt,
    localStorageBytes = localStorageBytes,
)

fun ResponseSection.toEntity(): ResponseSectionEntity = ResponseSectionEntity(
    id = id,
    surveyResponseId = surveyResponseId,
    sectionKey = sectionKey,
    repetitionIndex = repetitionIndex,
    answersJson = converters.answersToJson(answers),
)

fun MediaAttachment.toEntity(): MediaAttachmentEntity = MediaAttachmentEntity(
    id = id,
    surveyResponseId = surveyResponseId,
    localFilePath = localFilePath,
    mimeType = mimeType,
    sizeBytes = sizeBytes,
    uploadStatus = uploadStatus,
    serverUrl = serverUrl,
    createdAt = createdAt,
)
