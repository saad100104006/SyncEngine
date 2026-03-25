package com.surveysyncengine.data.local.db.dao

import androidx.room.Dao
import androidx.room.Query

// ---------------------------------------------------------------------------
// MediaAttachmentDao
// ---------------------------------------------------------------------------

@Dao
interface MediaAttachmentDao {

    @Query("""
        UPDATE media_attachments 
        SET uploadStatus = 'UPLOADED', serverUrl = :serverUrl
        WHERE id = :id
    """)
    suspend fun markUploaded(id: String, serverUrl: String)

    @Query("UPDATE media_attachments SET uploadStatus = 'FAILED' WHERE id = :id")
    suspend fun markFailed(id: String)
}