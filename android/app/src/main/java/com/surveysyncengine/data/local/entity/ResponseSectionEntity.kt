package com.surveysyncengine.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

// ---------------------------------------------------------------------------
// ResponseSectionEntity
// Stores repeating groups. Each row = one repetition of one section type.
// answers serialized as JSON via TypeConverter.
// ---------------------------------------------------------------------------

@Entity(
    tableName = "response_sections",
    foreignKeys = [ForeignKey(
        entity = SurveyResponseEntity::class,
        parentColumns = ["id"],
        childColumns = ["surveyResponseId"],
        onDelete = ForeignKey.CASCADE,
    )],
    indices = [Index("surveyResponseId")],
)
data class ResponseSectionEntity(
    @PrimaryKey val id: String,
    val surveyResponseId: String,
    val sectionKey: String,
    val repetitionIndex: Int,
    /** JSON-serialized Map<String, AnswerValue> — TypeConverter handles marshalling. */
    val answersJson: String,
)
