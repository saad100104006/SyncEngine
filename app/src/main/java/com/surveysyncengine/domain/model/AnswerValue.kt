package com.surveysyncengine.domain.model

// ---------------------------------------------------------------------------
// AnswerValue — a sealed hierarchy so answers can carry different types
// without collapsing everything to String. TypeConverters handle persistence.
//
// GpsCoordinate  — a single location (e.g. "where are you standing?")
// GpsBoundary    — an ordered polygon of vertices (e.g. farm field boundary).
//                  The spec requires capturing field boundaries per farm section;
//                  a single GpsCoordinate is not sufficient for that use case.
// ---------------------------------------------------------------------------

sealed class AnswerValue {
    data class Text(val value: String) : AnswerValue()
    data class Number(val value: Double) : AnswerValue()
    data class Bool(val value: Boolean) : AnswerValue()
    data class GpsCoordinate(val point: GpsPoint) : AnswerValue()
    data class GpsBoundary(val vertices: List<GpsPoint>) : AnswerValue() {
        /** A boundary needs at least 3 vertices to form a closed polygon. */
        val isComplete: Boolean get() = vertices.size >= 3
    }
    data class MultiChoice(val selected: List<String>) : AnswerValue()
    object Skipped : AnswerValue()
}