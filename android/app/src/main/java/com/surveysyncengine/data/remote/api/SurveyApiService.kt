package com.surveysyncengine.data.remote.api

import com.surveysyncengine.domain.api.AttachmentUploadDto
import com.surveysyncengine.domain.api.SurveyApiService
import com.surveysyncengine.domain.api.UploadResponseDto

// ---------------------------------------------------------------------------
// SurveyApiService has moved to domain.repository so SyncEngine can depend
// on it without importing from the data layer.
//
// Typealiases keep FakeSurveyApiService and other data-layer code compiling
// without any changes to their import statements.
// ---------------------------------------------------------------------------

typealias SurveyApiService    = SurveyApiService
typealias UploadResponseDto   = UploadResponseDto
typealias AttachmentUploadDto = AttachmentUploadDto
