# Architecture

## a. Architecture choice and alternatives considered

This project uses **Clean Architecture with a Repository pattern** — not MVVM.

MVVM is a UI architectural pattern that solves one specific problem: keeping UI state alive across Android lifecycle events (rotation, process death) by separating a `ViewModel` from the `View`. The spec explicitly requires no UI, so MVVM has no role here. Attaching a `ViewModel` to infrastructure code with no corresponding `View` would be architecture for its own sake.

Clean Architecture is the correct choice. The codebase is split into three layers with a strict inward dependency rule:

```
domain ← sync ← data
              ← worker
```

`domain` contains pure Kotlin models, repository interfaces, the `SurveyApiService` interface, and the `SyncError` hierarchy — no Android imports, no Room, no Retrofit. `sync` contains `SyncEngine` and its pure-Kotlin collaborators (`NetworkErrorClassifier`, `DevicePolicyEvaluator`); it imports only from `domain`. `data` implements the domain interfaces using Room, WorkManager, and Android system services; it is the only layer where Android framework imports are acceptable. `AndroidDevicePolicyEvaluator` deliberately lives in `data/platform/` rather than `sync/` for exactly this reason.

**Why `SurveyApiService` lives in `domain`, not `data`:** the sync engine needs to call the API. If the interface lived in `data/`, `SyncEngine` would have to import from an outer layer, breaking the dependency rule. The interface is a domain contract; the Retrofit implementation is a data concern.

**Why not a single god-class:** splitting `NetworkErrorClassifier` and `DevicePolicyEvaluator` out of `SyncEngine` gives each class one reason to change. Threshold tuning, policy changes, and classifier logic are all independently testable without instantiating the full engine.

**Alternative considered — event-sourced queue:** storing every status change as an immutable log event rather than mutating `status` in place. Rejected because folding the event log on every `getPendingResponses()` query is expensive on low-end devices with constrained SQLite, and the mutable `SyncStatus` column is simple to reason about.

**Where MVVM fits in future:** if a UI layer is added, MVVM slots cleanly above `sync`. A `ViewModel` would collect `SyncEngine.progress: SharedFlow<SyncProgress>` and expose it as `StateFlow<UiState>` for Compose or View binding. That bridge is already built — the `ViewModel` layer is absent only because the spec didn't ask for it.

## b. Media file uploads with pre-compression

`MediaAttachment` already carries `localFilePath` pointing to the original captured photo. To add compression, a `MediaCompressor` interface would be defined in `domain` and injected into `SyncEngine`:

```kotlin
interface MediaCompressor {
    suspend fun compress(sourcePath: String, targetPath: String): Long  // returns compressed size
}
```

Before uploading an attachment, the engine calls `compress()`, which writes a compressed copy to a staging directory. The engine uploads the staging file. On confirmed server receipt, the staging file is deleted. The original is deleted only after `markSynced()` — never speculatively. Compression happens lazily at sync time rather than at submission time, so the agent's "Submit" tap remains instant. A `compressedSizeBytes` column on `MediaAttachmentEntity` lets diagnostics report pre/post size savings and lets the metered-network byte cap in `SyncPolicy` operate on the actual upload size rather than the original.

## c. Scenario where network detection could make a wrong decision

If a specific survey payload (e.g. a malformed GPS boundary polygon) causes the server to reset the TCP connection without returning a valid HTTP response, the client sees a `SocketTimeoutException`. This maps to `SyncError.Timeout`, which is a network-level error. If two consecutive responses share the same malformed field, the `NetworkErrorClassifier` hits its threshold and returns `EarlyTermination` — incorrectly concluding the network is down when the real problem is bad data in those specific responses.

**Mitigation:** track a separate `consecutiveIdenticalPayloadFailures` counter alongside `consecutiveNetworkFailures`. If the abort threshold is reached but the failing responses all share the same `surveyId` or `sectionKey`, reclassify the termination reason as `SyncError.ClientError` and skip those responses rather than stopping the whole session. A lightweight schema validation pass in `SurveyRepositoryImpl.getPendingResponses()` (checking that GPS boundary polygons have ≥ 3 vertices, that required fields are non-null) can also catch the most common malformed payloads before they reach the network.

## d. Remote troubleshooting support

The `sync_log` table records every engine event (`STARTED`, `ITEM_SYNCED`, `ITEM_FAILED`, `EARLY_STOP`, `SKIPPED`, `BYTE_CAP_REACHED`) with a `sessionId`, `responseId`, error detail, and timestamp. `SurveyRepository.getDiagnosticsSnapshot()` aggregates:

- Pending / failed / synced counts
- Age of the oldest pending response in milliseconds (`oldestPendingAgeMs`) — reveals data stuck for days
- Total storage consumed by attachments
- Device storage available in bytes — rules out storage as the cause of failures
- Last 20 error strings from `sync_log`

A support team can request this snapshot without device access via an in-app "Send Diagnostic Report" action that POSTs the snapshot as JSON to a support endpoint. The most diagnostic fields are `retryCount` (a response at retryCount=10 signals a chronic payload problem), `oldestPendingAgeMs` (data not leaving the device), and the pattern of error types in `recentSyncErrors` (all timeouts = network; all 400s = schema mismatch after a server deploy).

## e. GPS field boundary capture — anticipated challenges

In rural Sub-Saharan Africa, satellite geometry (PDOP) degrades under tree canopy and in valleys, and multipath reflections from buildings or rocky terrain can produce position errors of 20–50 m. A single GPS fix is not a reliable boundary vertex.

Mitigation strategy: collect a burst of 5–10 readings at each vertex over 30 seconds, discard outliers beyond one standard deviation of the cluster, and average the remainder. Reject any vertex where the reported `accuracyMeters` exceeds 10 m or where HDOP > 5; surface a `LOW_ACCURACY` flag in `GpsPoint.accuracyMeters` so the server and the agent both know the vertex is suspect. `AnswerValue.GpsBoundary` already stores per-vertex accuracy, so no schema changes are needed.

Server-side validation should check: minimum 3 vertices (enforced client-side by `GpsBoundary.isComplete` but also verified on ingestion), no self-intersecting edges (a misplaced vertex produces a butterfly polygon), and a minimum area sanity check (a 0.001 hectare "farm" is almost certainly a GPS error). The `GpsBoundary` vertex order should be documented as counter-clockwise (standard GeoJSON convention) so area calculations are consistent.

## f. One thing I would do differently with more time

Add an **integration test suite backed by an in-memory Room database** (`Room.inMemoryDatabaseBuilder`) running under Robolectric. The current test suite uses `FakeSurveyRepository` — fast and effective for engine logic, but it does not exercise the actual SQL queries, the `TypeConverter` round-trips through SQLite, or the `CASCADE` delete behaviour on foreign keys (`ResponseSectionEntity`, `MediaAttachmentEntity`). A schema bug — a missing index causing a full table scan on `getPendingResponses()`, or a `TypeConverter` that serialises correctly but fails to deserialise an edge-case `AnswerValue` under SQLite's type coercion rules — would not be caught by the current suite. An integration layer running the real DAOs against an in-memory database would catch those issues and give confidence that the queries perform acceptably on the SQLite version shipped with `minSdk = 26`.
