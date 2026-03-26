package com.surveysyncengine.data.local.entity
import androidx.room.Embedded
import androidx.room.Relation

// ---------------------------------------------------------------------------
// Aggregate — Room relation that assembles a full response in one query
// ---------------------------------------------------------------------------

data class SurveyResponseAggregate(
    @Embedded val response: SurveyResponseEntity,
    @Relation(parentColumn = "id", entityColumn = "surveyResponseId")
    val sections: List<ResponseSectionEntity>,
    @Relation(parentColumn = "id", entityColumn = "surveyResponseId")
    val attachments: List<MediaAttachmentEntity>,
)