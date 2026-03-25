package com.surveysyncengine.data.local.db

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.surveysyncengine.data.local.converter.SurveyTypeConverters
import com.surveysyncengine.data.local.db.dao.MediaAttachmentDao
import com.surveysyncengine.data.local.db.dao.SurveyResponseDao
import com.surveysyncengine.data.local.db.dao.SyncLogDao
import com.surveysyncengine.data.local.entity.MediaAttachmentEntity
import com.surveysyncengine.data.local.entity.ResponseSectionEntity
import com.surveysyncengine.data.local.entity.SurveyResponseEntity
import com.surveysyncengine.data.local.entity.SyncLogEntity

@Database(
    entities = [
        SurveyResponseEntity::class,
        ResponseSectionEntity::class,
        MediaAttachmentEntity::class,
        SyncLogEntity::class,
    ],
    version = 1,
    exportSchema = true,
)

@TypeConverters(SurveyTypeConverters::class)
abstract class SurveyDatabase : RoomDatabase() {
    abstract fun surveyResponseDao(): SurveyResponseDao
    abstract fun mediaAttachmentDao(): MediaAttachmentDao
    abstract fun syncLogDao(): SyncLogDao
}
