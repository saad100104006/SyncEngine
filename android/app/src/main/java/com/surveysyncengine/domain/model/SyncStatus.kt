package com.surveysyncengine.domain.model

// ---------------------------------------------------------------------------
// Status enums
// ---------------------------------------------------------------------------

enum class SyncStatus {
    PENDING,        // saved locally, never attempted
    IN_PROGRESS,    // currently being uploaded (guards against double-pick)
    SYNCED,         // confirmed by server
    FAILED,         // last attempt failed transiently (network, 5xx) — WILL be retried
    DEAD,           // server permanently rejected this payload (4xx) — will NOT be retried
}
