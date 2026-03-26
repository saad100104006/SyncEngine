package com.surveysyncengine.domain.model

// ---------------------------------------------------------------------------
// GpsPoint — a single GPS vertex with accuracy metadata.
// Stored as a plain data class so it can be embedded in both GpsCoordinate
// (single point) and GpsBoundary (polygon vertices).
// ---------------------------------------------------------------------------

data class GpsPoint(
    val lat: Double,
    val lng: Double,
    val accuracyMeters: Float,
)