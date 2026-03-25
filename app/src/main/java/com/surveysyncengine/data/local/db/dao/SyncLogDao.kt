package com.surveysyncengine.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import com.surveysyncengine.data.local.entity.SyncLogEntity

// ---------------------------------------------------------------------------
// SyncLogDao — append-only; used for diagnostics / remote support
// ---------------------------------------------------------------------------

@Dao
interface SyncLogDao {

    @Insert
    suspend fun insert(entry: SyncLogEntity)

    @Query("SELECT * FROM sync_log ORDER BY timestamp DESC LIMIT :limit")
    suspend fun getRecent(limit: Int = 50): List<SyncLogEntity>

    @Query("SELECT * FROM sync_log WHERE responseId = :responseId ORDER BY timestamp DESC")
    suspend fun getForResponse(responseId: String): List<SyncLogEntity>

    /** Keep log table lean — delete entries older than retention window. */
    @Query("DELETE FROM sync_log WHERE timestamp < :olderThan")
    suspend fun pruneOlderThan(olderThan: Long): Int
}