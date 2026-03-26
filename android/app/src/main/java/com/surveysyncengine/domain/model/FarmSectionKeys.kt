package com.surveysyncengine.domain.model

// ---------------------------------------------------------------------------
// FarmSectionKeys — canonical answer-key constants for the farm repeating
// section. Using constants rather than raw strings prevents typos across
// the codebase and makes the expected schema visible in one place.
//
// The answers map in ResponseSection is intentionally open (Map<String, AnswerValue>)
// so the engine can handle any survey schema, but the farm section fields
// from the spec are pinned here.
// ---------------------------------------------------------------------------

object FarmSectionKeys {
    const val SECTION_KEY   = "farm"
    const val CROP_TYPE     = "crop_type"       // AnswerValue.Text or MultiChoice
    const val AREA_HECTARES = "area_hectares"   // AnswerValue.Number
    const val YIELD_ESTIMATE = "yield_estimate" // AnswerValue.Number (kg or bags)
    const val GPS_BOUNDARY  = "gps_boundary"    // AnswerValue.GpsBoundary (polygon)
}
