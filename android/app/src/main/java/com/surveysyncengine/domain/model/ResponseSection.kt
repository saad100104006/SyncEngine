package com.surveysyncengine.domain.model

import java.util.UUID

// ---------------------------------------------------------------------------
// ResponseSection — supports repeating groups (e.g. 3 farms per farmer).
// sectionKey identifies the group type; repetitionIndex identifies which
// instance within the group. answers is an open map to handle any schema.
// ---------------------------------------------------------------------------

data class ResponseSection(
    val id: String = UUID.randomUUID().toString(),
    val surveyResponseId: String,
    val sectionKey: String,              // e.g. "farm", "household_member"
    val repetitionIndex: Int,            // 0-based; driven by prior answer
    val answers: Map<String, AnswerValue>,
)
