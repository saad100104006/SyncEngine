package com.surveysyncengine.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

// ---------------------------------------------------------------------------
// SyncLogEntity — append-only audit trail for remote diagnostics
// ---------------------------------------------------------------------------

@Entity(tableName = "sync_log")
data class SyncLogEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val sessionId: String,
    val responseId: String?,
    val event: String,          // "STARTED", "ITEM_SYNCED", "ITEM_FAILED", "EARLY_STOP", etc.
    val detail: String?,        // error message or extra context
    val timestamp: Long = System.currentTimeMillis(),
)
