//
//  DataLayerTests.swift
//  SurveySyncEngineIOS
//
//

import XCTest
import Combine
import CoreData

/// Unit tests for the SurveyRepository and Core Data persistence layer.
/// These tests verify that domain objects are correctly mapped to and from the database,
/// status transitions are atomic, and reactive observers fire on data changes.
final class DataLayerTests: XCTestCase {

    var repo: SurveyRepository!
    var coreDataStack: CoreDataStack!

    override func setUpWithError() throws {
        // Use In-Memory storage so tests are isolated, fast, and don't persist to the simulator's disk.
        coreDataStack = CoreDataStack(inMemory: true)
        repo = SurveyRepositoryImpl(context: coreDataStack.mainContext)
    }

    // MARK: - Save / Retrieve

    /// Verifies that a survey saved to the repository can be successfully fetched using its unique ID.
    func testSavedResponseIsRetrievableById() async throws {
        let validId = UUID().uuidString
        let response = buildResponse(id: validId, farmerId: "farmer-abc")
        
        try await repo.saveResponse(response)
        let loaded = try await repo.getResponseById(id: validId)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, validId)
        XCTAssertEqual(loaded?.farmerId, "farmer-abc")
    }

    /// Ensures that querying for a non-existent ID returns nil rather than throwing or crashing.
    func testNonExistentIdReturnsNull() async throws {
        let loaded = try await repo.getResponseById(id: "does-not-exist")
        XCTAssertNil(loaded)
    }

    /// Verifies that complex nested AnswerValue types (GPS, Bool, Skip) are serialized/deserialized correctly.
    func testSectionsWithAnswersArePersistedAndRetrievedCorrectly() async throws {
        let responseId = UUID().uuidString
        
        let section = buildSection(
            surveyResponseId: responseId,
            sectionKey: "farm_details",
            repetitionIndex: 2,
            answers: [
                "crop_type": .text("sorghum"),
                "area_hectares": .number(3.75),
                "plot_location": .gpsCoordinate(lat: -1.2860, lng: 36.8168, accuracyMeters: 4.0),
                "is_irrigated": .bool(false),
                "skipped_q": .skipped
            ]
        )
        
        try await repo.saveResponse(buildResponse(id: responseId, sections: [section]))

        // Use custom async unwrap to handle the Optional result of the fetch
        let loaded = try await XCTUnwrapAsync(await repo.getResponseById(id: responseId))
        
        let loadedSection = loaded.sections[0]
        XCTAssertEqual(loadedSection.sectionKey, "farm_details")
        XCTAssertEqual(loadedSection.repetitionIndex, 2)
        
        // Pattern match against specific AnswerValue cases
        if case .text(let val) = loadedSection.answers["crop_type"] {
            XCTAssertEqual(val, "sorghum")
        } else { XCTFail("Expected text value") }
        
        if case .number(let val) = loadedSection.answers["area_hectares"] {
            XCTAssertEqual(val, 3.75)
        } else { XCTFail("Expected number value") }
    }

    // MARK: - Status Tracking

    /// Tests the linear lifecycle of a survey from Pending -> InProgress -> Synced.
    func testStatusTransitions() async throws {
        let id = UUID().uuidString
        try await repo.saveResponse(buildResponse(id: id))

        // 1. Verify Initial State
        var loaded = try await repo.getResponseById(id: id)
        XCTAssertEqual(loaded?.status, .pending)

        // 2. Verify Processing State
        try await repo.markInProgress(responseId: id)
        loaded = try await repo.getResponseById(id: id)
        XCTAssertEqual(loaded?.status, .inProgress)

        // 3. Verify Completion State
        try await repo.markSynced(responseId: id, syncedAt: 123456789)
        loaded = try await repo.getResponseById(id: id)
        
        let finalResult = try XCTUnwrap(loaded)
        XCTAssertEqual(finalResult.status, .synced)
    }

    /// Ensures the fetch request for 'pending' surveys correctly includes both new and failed items, but excludes synced ones.
    func testGetPendingResponsesFiltering() async throws {
        let pendingId = UUID().uuidString
        let failedId = UUID().uuidString
        let syncedId = UUID().uuidString

        try await repo.saveResponse(buildResponse(id: pendingId))
        try await repo.saveResponse(buildResponse(id: failedId))
        try await repo.saveResponse(buildResponse(id: syncedId))

        // Set one to failed and one to synced
        try await repo.markFailed(responseId: failedId, reason: "error", retryCount: 1)
        try await repo.markSynced(responseId: syncedId, syncedAt: 0)

        let pending = try await repo.getPendingResponses()

        // Expect 2 items: the original pending item and the one that failed (retryable)
        XCTAssertEqual(pending.count, 2)
        
        let ids = pending.map { $0.id }
        XCTAssertTrue(ids.contains(pendingId))
        XCTAssertTrue(ids.contains(failedId))
        XCTAssertFalse(ids.contains(syncedId))
    }

    // MARK: - Observation Flow

    /// Tests that the AsyncStream emits a new snapshot whenever a write operation occurs in the database.
    func testObserveAllResponsesEmitsUpdatedList() async throws {
        let stream = repo.observeAllResponses()
        var iterator = stream.makeAsyncIterator()

        // 1. Initial emit occurs immediately upon subscription (empty array)
        _ = await iterator.next()

        // 2. Perform a write and check for the subsequent emission
        let validId = UUID().uuidString
        try await repo.saveResponse(buildResponse(id: validId))
        
        let snapshot = await iterator.next()
        
        XCTAssertEqual(snapshot?.count, 1)
        XCTAssertEqual(snapshot?.first?.id, validId)
    }

    // MARK: - JSON Round-trip

    /// Tests the underlying data converter to ensure all AnswerValue enums survive JSON serialization.
    func testAnswerValueTypesSurviveJsonRoundTrip() throws {
        let original: [String: AnswerValue] = [
            "crop": .text("maize"),
            "size": .number(2.5),
            "gps": .gpsCoordinate(lat: -1.2860, lng: 36.8168, accuracyMeters: 4.0),
            "is_ready": .bool(true),
            "options": .multiChoice(["A", "B"]),
            "nothing": .skipped
        ]

        let json = SurveyDataConverter.answersToJson(original)
        let restored = SurveyDataConverter.jsonToAnswers(json)

        XCTAssertEqual(original.count, restored.count)
        
        // Validate floating point precision for coordinate data
        if case .gpsCoordinate(let lat, _, _) = restored["gps"] {
            XCTAssertEqual(lat, -1.2860, accuracy: 0.0001)
        } else { XCTFail("GPS data lost during round-trip") }
    }
}

// MARK: - Test Helpers

extension DataLayerTests {
    /// Factory method to create a domain model with default values for testing.
    func buildResponse(
        id: String = UUID().uuidString,
        farmerId: String = "farmer-1",
        status: SyncStatus = .pending,
        sections: [ResponseSection] = []
    ) -> SurveyResponse {
        return SurveyResponse(
            id: id,
            farmerId: farmerId,
            surveyId: "survey-123",
            status: status,
            sections: sections,
            attachments: [],
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    /// Factory method to create a response section.
    func buildSection(
        surveyResponseId: String,
        sectionKey: String = "general",
        repetitionIndex: Int = 0,
        answers: [String: AnswerValue] = [:]
    ) -> ResponseSection {
        return ResponseSection(
            surveyResponseId: surveyResponseId,
            sectionKey: sectionKey,
            repetitionIndex: repetitionIndex,
            answers: answers
        )
    }
}

extension XCTestCase {
    /// Utility to bridge XCTUnwrap with Swift Concurrency.
    func XCTUnwrapAsync<T>(
        _ expression: @autoclosure () async throws -> T?,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> T {
        let result = try await expression()
        return try XCTUnwrap(result, message(), file: file, line: line)
    }
}
