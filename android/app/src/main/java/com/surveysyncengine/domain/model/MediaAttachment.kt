package com.surveysyncengine.domain.model

import java.util.UUID

// ---------------------------------------------------------------------------
// MediaAttachment — photo or file linked to a survey response
// ---------------------------------------------------------------------------

data class MediaAttachment(
    val id: String = UUID.randomUUID().toString(),
    val surveyResponseId: String,
    val localFilePath: String,
    val mimeType: String,
    val sizeBytes: Long,
    val uploadStatus: UploadStatus = UploadStatus.PENDING,
    val serverUrl: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
)
