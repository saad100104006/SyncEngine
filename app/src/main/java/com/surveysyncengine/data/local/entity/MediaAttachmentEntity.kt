package com.surveysyncengine.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import com.surveysyncengine.domain.model.UploadStatus

// ---------------------------------------------------------------------------
// MediaAttachmentEntity
// ---------------------------------------------------------------------------

@Entity(
    tableName = "media_attachments",
    foreignKeys = [ForeignKey(
        entity = SurveyResponseEntity::class,
        parentColumns = ["id"],
        childColumns = ["surveyResponseId"],
        onDelete = ForeignKey.CASCADE,
    )],
    indices = [Index("surveyResponseId")],
)
data class MediaAttachmentEntity(
    @PrimaryKey val id: String,
    val surveyResponseId: String,
    val localFilePath: String,
    val mimeType: String,
    val sizeBytes: Long,
    val uploadStatus: UploadStatus,
    val serverUrl: String?,
    val createdAt: Long,
)