package com.android.surveysyncengine.data


import com.android.surveysyncengine.FakeSurveyRepository
import com.android.surveysyncengine.buildAttachment
import com.android.surveysyncengine.buildResponse
import com.android.surveysyncengine.buildResponseWithFarms
import com.android.surveysyncengine.buildSection
import com.surveysyncengine.domain.model.AnswerValue
import com.surveysyncengine.domain.model.FarmSectionKeys
import com.surveysyncengine.domain.model.GpsPoint
import com.surveysyncengine.domain.model.SyncStatus
import com.surveysyncengine.domain.model.UploadStatus
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class DataLayerTest {

    private lateinit var repo: FakeSurveyRepository

    @Before
    fun setUp() {
        repo = FakeSurveyRepository()
    }

    // ======================================================================
    // Save / Retrieve
    // ======================================================================

    @Test
    fun `saved response is retrievable by id`() = runTest {
        val response = buildResponse(id = "resp-1", farmerId = "farmer-abc")
        repo.saveResponse(response)

        val loaded = repo.getResponseById("resp-1")

        assertNotNull(loaded)
        assertEquals("resp-1", loaded!!.id)
        assertEquals("farmer-abc", loaded.farmerId)
    }

    @Test
    fun `non-existent id returns null`() = runTest {
        val loaded = repo.getResponseById("does-not-exist")
        assertNull(loaded)
    }

    @Test
    fun `sections with answers are persisted and retrieved correctly`() = runTest {
        val responseId = "resp-with-sections"
        val boundary = AnswerValue.GpsBoundary(
            vertices = listOf(
                GpsPoint(-1.2860, 36.8168, 4.0f),
                GpsPoint(-1.2855, 36.8175, 4.5f),
                GpsPoint(-1.2862, 36.8180, 3.8f),
            )
        )
        val section = buildSection(
            responseId = responseId,
            sectionKey = FarmSectionKeys.SECTION_KEY,
            repetitionIndex = 2,
            answers = mapOf(
                FarmSectionKeys.CROP_TYPE      to AnswerValue.Text("sorghum"),
                FarmSectionKeys.AREA_HECTARES  to AnswerValue.Number(3.75),
                FarmSectionKeys.YIELD_ESTIMATE to AnswerValue.Number(2200.0),
                FarmSectionKeys.GPS_BOUNDARY   to boundary,
                "is_irrigated"                 to AnswerValue.Bool(false),
                "skipped_q"                    to AnswerValue.Skipped,
            ),
        )
        repo.saveResponse(buildResponse(id = responseId, sections = listOf(section)))

        val loaded = repo.getResponseById(responseId)!!
        val loadedSection = loaded.sections[0]

        assertEquals(FarmSectionKeys.SECTION_KEY, loadedSection.sectionKey)
        assertEquals(2, loadedSection.repetitionIndex)
        assertEquals(AnswerValue.Text("sorghum"),      loadedSection.answers[FarmSectionKeys.CROP_TYPE])
        assertEquals(AnswerValue.Number(3.75),         loadedSection.answers[FarmSectionKeys.AREA_HECTARES])
        assertEquals(AnswerValue.Number(2200.0),       loadedSection.answers[FarmSectionKeys.YIELD_ESTIMATE])
        assertEquals(boundary,                         loadedSection.answers[FarmSectionKeys.GPS_BOUNDARY])
        assertEquals(AnswerValue.Bool(false),          loadedSection.answers["is_irrigated"])
        assertEquals(AnswerValue.Skipped,              loadedSection.answers["skipped_q"])

        // Boundary polygon is valid (≥3 vertices)
        val loadedBoundary = loadedSection.answers[FarmSectionKeys.GPS_BOUNDARY] as AnswerValue.GpsBoundary
        assertTrue(loadedBoundary.isComplete)
        assertEquals(3, loadedBoundary.vertices.size)
    }

    @Test
    fun `dynamic farm count produces correct section count`() = runTest {
        // Farmer reports 5 farms — dynamic, driven by prior answer at runtime
        val response = buildResponseWithFarms(farmCount = 5)
        repo.saveResponse(response)

        val loaded = repo.getResponseById(response.id)!!
        assertEquals(5, loaded.sections.size)
        (0..4).forEach { i -> assertEquals(i, loaded.sections[i].repetitionIndex) }
    }

    @Test
    fun `attachments are persisted with parent response`() = runTest {
        val att = buildAttachment(responseId = "resp-1", id = "att-1", sizeBytes = 204_800L)
        repo.saveResponse(buildResponse(id = "resp-1", attachments = listOf(att)))

        val loaded = repo.getResponseById("resp-1")!!
        assertEquals(1, loaded.attachments.size)
        assertEquals("att-1", loaded.attachments[0].id)
        assertEquals(204_800L, loaded.attachments[0].sizeBytes)
        assertEquals(UploadStatus.PENDING, loaded.attachments[0].uploadStatus)
    }

    // ======================================================================
    // Status tracking
    // ======================================================================

    @Test
    fun `status transitions PENDING → IN_PROGRESS → SYNCED`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-1"))

        assertEquals(SyncStatus.PENDING, repo.statusOf("resp-1"))
        repo.markInProgress("resp-1")
        assertEquals(SyncStatus.IN_PROGRESS, repo.statusOf("resp-1"))
        repo.markSynced("resp-1")
        assertEquals(SyncStatus.SYNCED, repo.statusOf("resp-1"))
    }

    @Test
    fun `status transitions PENDING → IN_PROGRESS → FAILED`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-1"))
        repo.markInProgress("resp-1")
        repo.markFailed("resp-1", "Server error", retryCount = 1)

        assertEquals(SyncStatus.FAILED, repo.statusOf("resp-1"))
        assertEquals(1, repo.retryCountOf("resp-1"))
        assertNotNull(repo.failureReasonOf("resp-1"))
    }

    @Test
    fun `getPendingResponses includes PENDING and FAILED, excludes SYNCED and IN_PROGRESS`() = runTest {
        repo.saveResponse(buildResponse(id = "pending"))
        repo.saveResponse(buildResponse(id = "failed"))
        repo.saveResponse(buildResponse(id = "synced"))
        repo.saveResponse(buildResponse(id = "in-progress"))

        repo.markFailed("failed", "error", retryCount = 1)
        repo.markSynced("synced")
        repo.markInProgress("in-progress")

        val pending = repo.getPendingResponses()

        assertEquals(2, pending.size)
        val pendingIds = pending.map { it.id }
        assertTrue(pendingIds.contains("pending"))
        assertTrue(pendingIds.contains("failed"))
    }

    @Test
    fun `getPendingResponses returns items ordered by createdAt ascending`() = runTest {
        val now = System.currentTimeMillis()
        repo.saveResponse(buildResponse(id = "resp-newest").copy(createdAt = now + 2000))
        repo.saveResponse(buildResponse(id = "resp-oldest").copy(createdAt = now))
        repo.saveResponse(buildResponse(id = "resp-middle").copy(createdAt = now + 1000))

        val pending = repo.getPendingResponses()

        assertEquals("resp-oldest", pending[0].id)
        assertEquals("resp-middle", pending[1].id)
        assertEquals("resp-newest", pending[2].id)
    }

    @Test
    fun `SYNCED responses are not returned by getPendingResponses`() = runTest {
        repeat(5) { repo.saveResponse(buildResponse(id = "resp-$it")) }
        (0..4).forEach { repo.markSynced("resp-$it") }

        val pending = repo.getPendingResponses()
        assertTrue(pending.isEmpty())
    }

    // ======================================================================
    // Attachment status
    // ======================================================================

    @Test
    fun `markAttachmentUploaded updates status and serverUrl`() = runTest {
        val att = buildAttachment(responseId = "resp-1", id = "att-1")
        repo.saveResponse(buildResponse(id = "resp-1", attachments = listOf(att)))

        repo.markAttachmentUploaded("att-1", "https://cdn.example.com/att-1.jpg")

        val loaded = repo.getResponseById("resp-1")!!
        assertEquals(UploadStatus.UPLOADED, loaded.attachments[0].uploadStatus)
        assertEquals("https://cdn.example.com/att-1.jpg", loaded.attachments[0].serverUrl)
    }

    @Test
    fun `markAttachmentFailed updates status to FAILED`() = runTest {
        val att = buildAttachment(responseId = "resp-1", id = "att-1")
        repo.saveResponse(buildResponse(id = "resp-1", attachments = listOf(att)))

        repo.markAttachmentFailed("att-1")

        val loaded = repo.getResponseById("resp-1")!!
        assertEquals(UploadStatus.FAILED, loaded.attachments[0].uploadStatus)
        assertNull(loaded.attachments[0].serverUrl)
    }

    // ======================================================================
    // Observation flow
    // ======================================================================

    @Test
    fun `observeAllResponses emits updated list when response is saved`() = runTest {
        val flow = repo.observeAllResponses()

        repo.saveResponse(buildResponse(id = "resp-1"))
        repo.saveResponse(buildResponse(id = "resp-2"))

        val snapshot = flow.first()
        assertEquals(2, snapshot.size)
    }

    @Test
    fun `observeByStatus filters correctly`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-pending"))
        repo.saveResponse(buildResponse(id = "resp-synced"))
        repo.markSynced("resp-synced")

        val synced = repo.observeByStatus(SyncStatus.SYNCED).first()
        assertEquals(1, synced.size)
        assertEquals("resp-synced", synced[0].id)
    }

    // ======================================================================
    // Storage stats
    // ======================================================================

    @Test
    fun `storage stats reflect attachment sizes correctly`() = runTest {
        val att1 = buildAttachment(responseId = "resp-1", sizeBytes = 1_000_000L)
        val att2 = buildAttachment(responseId = "resp-2", sizeBytes = 2_000_000L)
        repo.saveResponse(buildResponse(id = "resp-1", attachments = listOf(att1), localStorageBytes = 1_000_000L))
        repo.saveResponse(buildResponse(id = "resp-2", attachments = listOf(att2), localStorageBytes = 2_000_000L))

        val stats = repo.getStorageStats()

        assertEquals(3_000_000L, stats.totalPendingBytes)
        assertEquals(2, stats.attachmentCount)
    }

    @Test
    fun `synced responses are excluded from pending storage stats`() = runTest {
        repo.saveResponse(buildResponse(id = "resp-1", localStorageBytes = 1_000_000L))
        repo.saveResponse(buildResponse(id = "resp-2", localStorageBytes = 2_000_000L))
        repo.markSynced("resp-1")

        val stats = repo.getStorageStats()
        assertEquals(2_000_000L, stats.totalPendingBytes)
        assertEquals(1_000_000L, stats.totalSyncedBytes)
    }
    
    @Test
    fun `GpsBoundary with fewer than 3 vertices is flagged as incomplete`() {
        val incomplete = AnswerValue.GpsBoundary(
            listOf(GpsPoint(-1.286, 36.817, 5.0f), GpsPoint(-1.287, 36.818, 5.0f))
        )
        assertFalse(incomplete.isComplete)
    }

}
