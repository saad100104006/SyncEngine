package com.surveysyncengine.domain.api

import com.surveysyncengine.domain.model.SurveyResponse

// ---------------------------------------------------------------------------
// SurveyApiService — domain-level interface for uploading responses.
//
// Lives in domain so SyncEngine depends only on domain, never on data.
// ---------------------------------------------------------------------------

interface SurveyApiService {

    /**
     * Upload a single survey response.
     * Throws on any failure — callers map Throwable → SyncError.
     */
    suspend fun uploadSurveyResponse(response: SurveyResponse): UploadResponseDto

    /**
     * Upload a single media attachment.
     * @return publicly accessible URL where the server stored the file.
     */
    suspend fun uploadAttachment(
        surveyResponseId: String,
        attachmentId: String,
        localFilePath: String,
        mimeType: String,
    ): AttachmentUploadDto
}

data class UploadResponseDto(
    val serverId: String,
    val receivedAt: Long,
)

data class AttachmentUploadDto(
    val attachmentId: String,
    val serverUrl: String,
)
