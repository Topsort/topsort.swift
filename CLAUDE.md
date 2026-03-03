# CLAUDE.md — topsort.swift

## Project Overview

Swift SDK for Topsort retail media: auctions, event tracking, and banner ads.

- **Two SPM libraries**: `Topsort` (core) and `TopsortBanners` (SwiftUI UI components)
- **Zero external dependencies** — pure Swift/Foundation/SwiftUI
- **Platforms**: iOS 15+, macOS 12+, tvOS 11+, watchOS 7.1+
- **Swift tools version**: 5.3

## Build & Test

```sh
swift build
swift test
```

No Makefile, no Xcode project — SPM only.

## Architecture

### Core (`Topsort`)

**Singleton facade**: `Topsort.shared` (private init) wraps:
- `EventManager.shared` — fire-and-forget event tracking (impressions, clicks, purchases)
- `AuctionManager.shared` — async/await auction requests

**`TopsortProtocol`** defines the full public API surface. Used for DI/testability — `TopsortBanner` accepts any `TopsortProtocol` conformer (defaults to `Topsort.shared`).

### Event Pipeline (EventManager)

Events are queued → periodically flushed (every 60s) → batched into a single POST → retried on failure.

- **Retry**: exponential backoff `min(10 * 2^retries, 1200)` seconds, max 50 retries, max 10 concurrent
- **Non-retriable**: only HTTP 400
- **Queue/pending state**: persisted to plist files in app Documents directory

### Auction Pipeline (AuctionManager)

Direct async/await request → response. 1–5 auctions per request (enforced). Default timeout: 60s. Typed throws via `AuctionError`.

### Banners (`TopsortBanners`)

`TopsortBanner` is a SwiftUI `View` with an internal `@MainActor ViewModel`. It:
1. Runs an auction via `TopsortProtocol`
2. Loads the winning asset URL via `AsyncImage`
3. Auto-tracks impressions on appear, clicks on tap
4. Provides fluent callbacks: `.buttonClickedAction()`, `.onError()`, `.onNoWinners()`, `.onImageLoad()`

`BannerAuctionBuilder` constructs the auction config (slotId, deviceType, products, category, etc.).

## Key Patterns & Conventions

| Pattern | Location | Purpose |
|---------|----------|---------|
| `With` protocol | `Utils/With.swift` | Fluent value-copy builder: `.with(path:to:)` |
| `@FilePersistedValue<T: Codable>` | `Utils/FilePersistedValue.swift` | Plist persistence via serial dispatch queue |
| `@TSDateValue` | `Utils/TSDateValue.swift` | ISO 8601 date serialization with fractional seconds |
| `Action<I>` / `UnitAction` | `Utils/Action.swift` | Callback type aliases: `(I) -> Void` / `() -> Void` |
| Typed throws | `AuctionManager` | `throws(AuctionError)` for auction calls |

### Type conventions
- Internal types: `class` singletons (`EventManager`, `AuctionManager`, `HTTPClient`)
- Public models: `struct` value types conforming to `Codable` (`Event`, `PurchaseEvent`, `Auction`, `AuctionResponse`)
- No UIKit — SwiftUI only for UI components

## Important Constants & Paths

| Constant | Value | Location |
|----------|-------|----------|
| API base (events) | `https://api.topsort.com/v2/events` | `EventManager.swift` |
| API base (auctions) | `https://api.topsort.com/v2/auctions` | `AuctionManager.swift` |
| Analytics version | `__analytics_version` in `Version.swift` | User-Agent: `analytics-swift/<version>` |
| Max auctions/request | 5 | `AuctionManager.swift` |
| Max retries | 50 | `EventManager.swift` |
| Max concurrent sends | 10 | `EventManager.swift` |
| Max backoff | 1200s (20 min) | `EventManager.swift` |
| Flush interval | 60s | `EventManager.swift` |

**Persistence files** (app Documents dir):
- `com.topsort.analytics.opaque-user-id.plist`
- `com.topsort.analytics.event-queue.plist`
- `com.topsort.analytics.pending-events.plist`

## Code Style

- **swiftformat** enforced in CI (default rules, no `.swiftformat` config file)
- Source files: PascalCase (`EventManager.swift`, `BannerView.swift`)
- Test targets: lowercase with dots (`topsort.swiftTests`, `banners.swiftTests`)

## CI (GitHub Actions)

| Workflow | Trigger | Runner | Command |
|----------|---------|--------|---------|
| Test | push (all branches) | macos-15 | `swift build` + `swift test` |
| Format | PR (*.swift changes) | macos-14 | `swiftformat --lint .` |
| Typos | PR (*.md, *.yml, *.swift) | ubuntu-22.04 | `crate-ci/typos@v1.24.1` |
| Actions | PR (.github/workflows/*) | ubuntu-latest | `actionlint v1.7.7` |

## Testing

Tests use **XCTest** — no third-party test frameworks. Two mock strategies:

1. **`MockHTTPClient`** — subclasses `HTTPClient`, overrides `asyncPost`. Inject via `auctionManager.client = mockClient` (internal property)
2. **`MockTopsort`** — conforms to `TopsortProtocol`. Inject via `TopsortBanner(bannerAuctionBuilder:topsort:)`

All tests use `@testable import` to access internal types.

## Git Workflow

- **Never commit directly to `main`.** All changes go through PRs from a dedicated branch.
- Branch names should be descriptive (e.g., `feat/add-google-environment`, `fix/merge-pagination-offset`).
- **Large changes must be broken into stacked PRs** — each PR should be independently reviewable and represent a single logical unit of work. Avoid monolithic PRs that touch many unrelated things at once.
- Each PR in a stack should be based on the previous branch, not `main`, so they can be reviewed and merged in order.
- **Admin override** (`gh pr merge --admin`) is only appropriate to bypass the review requirement when all CI checks pass. Never use it to force-merge a PR with failing CI — fix the failures first. Before using `--admin`, check whether the repo allows it. If admin override is not permitted or you cannot verify it is, do not merge — ask the user instead.
- Keep branches up to date with `main` before merging — rebase or merge `main` into your branch to resolve conflicts locally, not in the merge commit.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for all commit messages (e.g., `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`).
- Never approve or merge a PR that has unresolved review comments — address or explicitly dismiss each one first. Always check nested/threaded comments (e.g. replies under bot comments) as they may contain substantive issues not visible at the top level.
- Before merging with `--admin`, wait at least **5 minutes** after the PR is opened. This gives Bugbot and other async bots time to post their comments. After the wait, check all PR comments (including nested/threaded replies) for unresolved issues before merging.
- After every significant architectural change, review this `CLAUDE.md` and update it if the change affects documented patterns, constraints, or workflows.

## Contributor Recipes

**Add a new event type**: define model struct → add `EventItem` case in `EventManager.swift` → add `Topsort.track(...)` method

**Add a new auction field**: add property to model struct in `Auctions.swift` → `Codable` auto-picks it up

**Add a new UI component**: new file in `Sources/TopsortBanners/` → depend on `Topsort` target → accept `TopsortProtocol` for DI

**Add a new test**: use `MockHTTPClient` for network-level mocks, `MockTopsort` for SDK-level mocks
