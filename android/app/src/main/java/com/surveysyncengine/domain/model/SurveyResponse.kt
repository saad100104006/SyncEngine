package com.surveysyncengine.domain.model

import java.util.UUID

// ---------------------------------------------------------------------------
// Survey Response — top-level container for one completed survey session
// ---------------------------------------------------------------------------

data class SurveyResponse(
    val id: String = UUID.randomUUID().toString(),
    val farmerId: String,
    val surveyId: String,
    val status: SyncStatus = SyncStatus.PENDING,
    val sections: List<ResponseSection> = emptyList(),
    val attachments: List<MediaAttachment> = emptyList(),
    val failureReason: String? = null,
    val retryCount: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
    val syncedAt: Long? = null,
    val localStorageBytes: Long = 0L,
)