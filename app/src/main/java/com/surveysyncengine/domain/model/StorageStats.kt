package com.surveysyncengine.domain.model

// ---------------------------------------------------------------------------
// StorageStats — reported so callers can warn users or pause collection
// ---------------------------------------------------------------------------

data class StorageStats(
    val totalPendingBytes: Long,
    val totalSyncedBytes: Long,
    val availableDeviceBytes: Long,
    val attachmentCount: Int,
)
