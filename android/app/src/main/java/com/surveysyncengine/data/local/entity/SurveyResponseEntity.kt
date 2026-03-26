package com.surveysyncengine.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.surveysyncengine.domain.model.SyncStatus

// ---------------------------------------------------------------------------
// SurveyResponseEntity
// ---------------------------------------------------------------------------

@Entity(tableName = "survey_responses")
data class SurveyResponseEntity(
    @PrimaryKey val id: String,
    val farmerId: String,
    val surveyId: String,
    val status: SyncStatus,
    val failureReason: String?,
    val retryCount: Int,
    val createdAt: Long,
    val syncedAt: Long?,
    val localStorageBytes: Long,
)

