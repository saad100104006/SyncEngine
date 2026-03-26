# Survey Response Sync Engine

A production-quality data layer for an offline-first agricultural survey app targeting field agents in rural Sub-Saharan Africa.

---

## Architecture

This project uses **Clean Architecture** — not MVVM.

MVVM is a UI pattern that solves UI state management across lifecycle events. The spec explicitly requires no UI, so MVVM has no role here. Clean Architecture is the right choice: it keeps business logic independent of Android frameworks, makes the sync engine fully unit-testable without a device, and enforces a clear dependency rule.

```
        ┌─────────────────────────────────┐
        │            domain               │  Pure Kotlin.
        │  models · interfaces · errors   │  No Android. No Room. No Retrofit.
        └────────────────┬────────────────┘
                         │ depends on
        ┌────────────────┴────────────────┐
        │              sync               │  Orchestration.
        │  SyncEngine · classifier ·      │  Pure Kotlin.
        │  DevicePolicyEvaluator (iface)  │  Depends only on domain interfaces.
        └────────────────┬────────────────┘
                         │ depends on
        ┌────────────────┴────────────────┐
        │              data               │  Android framework allowed here.
        │  Room · API · platform ·        │  Implements domain interfaces.
        │  AndroidDevicePolicyEvaluator   │  SyncEngine never imports from here.
        └─────────────────────────────────┘
        ┌─────────────────────────────────┐
        │             worker              │  Thin shell only.
        │  SyncWorker (WorkManager)       │  Delegates entirely to SyncEngine.
        └─────────────────────────────────┘
```

**The one rule:** dependencies point inward only. `sync` knows about `domain`. `data` knows about `domain`. Neither `sync` nor `domain` ever imports from `data`.

If a UI layer were added, MVVM would sit *above* this stack — a `ViewModel` collecting `SyncEngine.progress: SharedFlow<SyncProgress>` and exposing it as UI state. That bridge is already built; the ViewModel layer is absent because the spec didn't ask for it.

---

## Scenarios covered

| Scenario | Implementation |
|---|---|
| 1 — Offline storage | Room DB with repeating sections (`ResponseSection`), attachment tracking, crash recovery via `resetStuckInProgress()` |
| 2 — Partial failure | Per-item `SyncStatus` transitions; only `FAILED` items re-attempted on next sync |
| 3 — Network degradation | `NetworkErrorClassifier` counts *consecutive* network failures; aborts early to conserve battery |
| 4 — Concurrent sync prevention | `Mutex.tryLock()` returns `AlreadyRunning` immediately — no blocking, no corruption |
| 5 — Error mapping | `Throwable.toSyncError()` normalises all exception types into a sealed `SyncError` hierarchy |
| Bonus — WorkManager | `SyncWorker` + `SyncWorkerFactory`: network constraint, exponential backoff, `KEEP` dedup policy |
| Bonus — Progress reporting | `SharedFlow<SyncProgress>` emits `Started`, `ItemUploading`, `ItemSucceeded`, `ItemFailed`, `Finished` |
| Bonus — Device-aware policy | `DefaultDevicePolicyEvaluator` gates on battery %, storage free, network type; `AndroidDevicePolicyEvaluator` reads real system services |

---

## Package structure

```
com.survey.sync/
├── domain/                         Pure Kotlin — inner-most layer
│   ├── model/                      SurveyResponse, ResponseSection, AnswerValue
│   │                               MediaAttachment, FarmSectionKeys, GpsPoint
│   ├── repository/                 SurveyRepository interface (+ logSyncEvent)
│   │                               SurveyApiService interface              ← moved here from data/
│   │                               DiagnosticsSnapshot
│   └── error/                      SyncError sealed class
│                                   SurveyHttpException, Throwable.toSyncError()
│
├── sync/                           Orchestration — pure Kotlin, no Android imports
│   ├── SyncEngine.kt               Depends on SurveyRepository + SurveyApiService (interfaces)
│   ├── SyncResult.kt               SyncResult + SyncProgress sealed classes
│   ├── DevicePolicy.kt             DevicePolicyEvaluator interface
│   │                               DefaultDevicePolicyEvaluator (lambda-based, pure Kotlin)
│   │                               FakeDevicePolicyEvaluator (tests)
│   └── NetworkErrorClassifier.kt   Consecutive failure tracking, abort threshold
│
├── data/                           Android framework allowed here
│   ├── local/
│   │   ├── db/                     SurveyDatabase, SurveyResponseDao,
│   │   │                           MediaAttachmentDao, SyncLogDao
│   │   ├── entity/                 Room entities + Mappers (domain ↔ entity)
│   │   └── converter/              SurveyTypeConverters (AnswerValue ↔ JSON)
│   ├── remote/
│   │   └── api/                    FakeSurveyApiService (configurable failure plan)
│   │                               SurveyApiService.kt (typealias → domain)
│   ├── platform/
│   │   └── AndroidDevicePolicyEvaluator.kt   BatteryManager + ConnectivityManager + StatFs
│   └── repository/
│       └── SurveyRepositoryImpl.kt Implements SurveyRepository interface
│
├── worker/
│   └── SyncWorker.kt               CoroutineWorker + SyncWorkerFactory
│
└── test/
    ├── FakeSurveyRepository.kt     In-memory repository implementing SurveyRepository
    ├── TestFixtures.kt             Builders + pre-baked API/policy configs
    ├── TestSyncEngineFactory.kt    Wires SyncEngine with fakes (no TODOs, no concrete deps)
    ├── sync/
    │   ├── SyncEngineTest.kt       All 5 spec scenarios + progress + device policy + crash recovery
    │   ├── NetworkDegradationTest.kt   Classifier threshold edge cases
    │   └── MissingCoverageTest.kt  DefaultDevicePolicyEvaluator thresholds, EarlyTermination
    │                               progress, storage-low policy, TimeoutCancellationException
    ├── data/
    │   └── DataLayerTest.kt        Save/retrieve, status tracking, TypeConverter round-trips
    ├── error/
    │   └── ErrorHandlingTest.kt    All exception types + classifier unit tests
    └── worker/
        └── SyncWorkerTest.kt       All SyncResult → WorkManager Result mappings
```

---

## Key design decisions

**`SyncEngine` depends only on domain interfaces** — `SurveyRepository` and `SurveyApiService` are both defined in `domain/`. `SyncEngine` never imports from `data/`. This means every test in the suite runs as plain JUnit + coroutines with no Room database, no Android runner, and no Robolectric.

**`SurveyApiService` lives in `domain/`** — not `data/`. The sync engine needs to call the API; if the interface lived in `data/`, the engine would have to import from an outer layer, violating the dependency rule. The data layer implements the interface; it doesn't define it.

**`AndroidDevicePolicyEvaluator` lives in `data/platform/`** — not `sync/`. The `sync` package is pure Kotlin. Android framework imports (`BatteryManager`, `ConnectivityManager`, `StatFs`) belong in `data/` where the Android dependency is already accepted. `SyncEngine` depends on the `DevicePolicyEvaluator` interface in `sync/`.

**`SyncStatus.IN_PROGRESS`** — a dedicated status that prevents double-pickup on concurrent or restarted syncs. `resetStuckInProgress()` recovers from crash-mid-sync on app start.

**`ResponseSection` with `repetitionIndex`** — repeating groups (e.g. 3 farms per farmer) are stored as flat rows keyed by `sectionKey` + `repetitionIndex`. The number of repetitions is dynamic (driven by a prior answer at runtime). Only the `answers` map is JSON-serialised via `TypeConverter`; the outer structure is relational.

**`NetworkErrorClassifier` counts consecutive failures, not total** — a server error between two timeouts resets the counter. Only unbroken runs of network-level failures trigger early termination. This prevents a single bad payload from being misclassified as a network outage.

**`Mutex.tryLock()` not `withLock()`** — the second caller gets `AlreadyRunning` immediately rather than suspending behind the first sync. A UI button tap while background sync is running gets an instant, honest answer.

**Fakes over mocks** — `FakeSurveyRepository` is a real in-memory implementation with inspection helpers (`statusOf()`, `retryCountOf()`). Tests assert on state, not on call sequences. `FakeRepositoryAdapter` implements `SurveyRepository` directly — no `TODO()` DAO stubs required.


## Dependencies

See `build.gradle.kts` for the full list. Key additions beyond standard Android:

| Library | Purpose |
|---|---|
| `kotlinx-coroutines-test` | `runTest` for coroutine-safe tests |
| `app.cash.turbine` | `Flow.test {}` — asserts `SharedFlow<SyncProgress>` emission order |
| `io.mockk:mockk` | Available but used sparingly — fakes are preferred over mocks |
| `androidx.work:work-testing` | `TestWorkerBuilder` for `SyncWorker` tests |
| `org.robolectric:robolectric` | Android `Context` in `SyncWorkerTest` without a device |
