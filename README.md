# Survey Response Sync Engine

Offline-first sync engine for a field survey app used by agricultural agents in rural Sub-Saharan Africa. Built as a data-layer exercise — no UI.

## Platforms

| Platform | Language | Concurrency |
|---|---|---|
| [Android](./android/README.md) | Kotlin | Coroutines + Mutex |
| [iOS](./ios/README.md) | Swift | async/await + Actor |

Both platforms implement the same sync contract independently. No shared code layer — each is idiomatic for its platform.

## Scenarios covered

1. **Offline storage** — surveys saved locally, survive app restarts
2. **Partial failure** — per-item status tracking, only failed responses retried
3. **Network degradation** — early termination on timeout to conserve battery
4. **Concurrent sync prevention** — second sync call rejected immediately
5. **Error mapping** — all failure types normalised into a consistent error model


## Structure

```
survey-sync/
├── android/        Kotlin — Room, Coroutines, WorkManager
├── ios/            Swift — async/await, Actor, Swift Package
├── ARCHITECTURE.md Design decisions, trade-offs, future considerations
└── README.md       This file
```
