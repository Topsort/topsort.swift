# CLAUDE.md — topsort.swift

## Project Overview

Swift SDK for Topsort retail media: auctions, event tracking, and banner ads.

- **Two SPM libraries**: `Topsort` (core) and `TopsortBanners` (SwiftUI UI components)
- **Zero external dependencies** — pure Swift/Foundation/SwiftUI
- **Privacy manifest**: `Sources/Topsort/PrivacyInfo.xcprivacy` (copied resource) declares User ID, Purchase History, Product Interaction and Search History as linked/not tracking; keep it in step with any new event field that identifies the user
- **Platforms**: iOS 15+, macOS 12+
- **Swift tools version**: 5.9 (kept below 6.0 to stay in Swift 5 language mode; the sources use typed throws, so a Swift 6 toolchain is required to build)

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

Events are queued → periodically flushed (every 30s) → batched into POSTs of at most 500 events → retried on failure.

- **Retry**: exponential backoff `min(10 * 2^retries, 1200)` seconds, max 50 retries, max 10 concurrent; a batch that exhausts its retries is dropped
- **Non-retriable**: all 4xx except 408 and 429. 5xx and transport failures retry
- **Bounds**: queue capped at 5000 events (oldest shed first); each POST carries at most 500 events
- **Flush triggers**: queue reaches `flushAt` (default 30), the `flushInterval` timer, `flush()`, background/terminate, connectivity restored. `configure` rejects `flushAt < 1` and `flushInterval <= 0`
- **Queue/pending state**: persisted to plist files in `Application Support/com.topsort.analytics/` (migrated from Documents on first launch; `PathHelper.swift`), debounced 5 s, synchronous on background/terminate

### Auction Pipeline (AuctionManager)

Direct async/await request → response. 1–5 auctions per request (enforced). Default timeout: 60s. Typed throws via `AuctionError`.

### Banners (`TopsortBanners`)

`TopsortBanner` is a SwiftUI `View` with an internal `@MainActor ViewModel`. It:
1. Runs an auction via `TopsortProtocol`
2. Loads the winning asset URL via `RemoteImage` (an ephemeral `URLSession` loader, not `AsyncImage`)
3. Tracks the impression when the image has loaded (not on appear), clicks on tap
4. Builds the auction with the injected `TopsortProtocol`'s `opaqueUserId`
5. Provides fluent callbacks: `.buttonClickedAction()`, `.onError()`, `.onNoWinners()`, `.onImageLoad()`

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
- UI components are SwiftUI only; UIKit/AppKit appear only behind `canImport` for the lifecycle observer and image decoding

## Important Constants & Paths

| Constant | Value | Location |
|----------|-------|----------|
| API base (events) | `https://api.topsort.com/v2/events` | `EventManager.swift` |
| API base (auctions) | `https://api.topsort.com/v2/auctions` | `AuctionManager.swift` |
| Analytics version | `__analytics_version` in `Version.swift` | User-Agent: `analytics-swift/<version>` |
| Max auctions/request | 5 | `AuctionManager.swift` |
| Max retries | 50 | `EventManager.swift` |
| Max concurrent sends | 10 | `EventManager.swift` |
| Max queued events | 5000 (oldest dropped) | `EventManager.swift` |
| Max events per batch | 500 | `EventManager.swift` |
| Max backoff | 1200s (20 min) | `EventManager.swift` |
| Flush interval | 30s | `EventManager.swift` |
| Flush threshold (`flushAt`) | 30 events | `Configuration.swift` |

**Persistence files** (`Application Support/com.topsort.analytics/`):
- `com.topsort.analytics.opaque-user-id.plist`
- `com.topsort.analytics.event-queue.plist`
- `com.topsort.analytics.pending-events.plist`

## Code Style

- **Always run `swiftformat .` before opening a PR** to avoid CI failures
- **swiftformat** enforced in CI (default rules, no `.swiftformat` config file)
- Source files: PascalCase (`EventManager.swift`, `BannerView.swift`)
- Test targets: lowercase with dots (`topsort.swiftTests`, `banners.swiftTests`)
- No `.swift-version` file: swiftformat reads it as the *language* version, and anything above 5.3 turns on rules the sources do not follow. The toolchain requirement lives in README and `Package.swift`

## CI (GitHub Actions)

| Workflow | Trigger | Runner | Command |
|----------|---------|--------|---------|
| Test | push to main, PR | macos-15 | `swift build` + `swift test`; `xcodebuild test` on an iPhone simulator |
| Format | PR (*.swift changes) | macos-14 | `swiftformat --lint .` |
| Typos | PR (*.md, *.yml, *.swift) | ubuntu-22.04 | `crate-ci/typos@v1.24.1` |
| Actions | PR (.github/workflows/*) | ubuntu-latest | `actionlint v1.7.7` |
| Conventional Commits | PR (opened/edited/synchronize) | ubuntu-24.04 | `amannn/action-semantic-pull-request` |
| Release Please | push to main | ubuntu-24.04 | `googleapis/release-please-action` |
| Publish Pages | after Test on main | ubuntu-24.04 | publishes `coverage.json` for the README badge |

## Testing

Coverage is measured on the iOS simulator job over the two library targets (test bundles excluded)
and gated at 75 % lines by `.github/scripts/coverage.py`; the same script writes the badge JSON
(green at or above the gate, orange below).

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

## Releasing

release-please keeps a release PR open against `main`; merging it bumps `Sources/Topsort/Version.swift`
and the README `from:` line (both annotated `x-release-please-version`), updates `CHANGELOG.md`,
tags without a `v` prefix, and creates the GitHub release. Nothing to publish afterwards — SPM reads
the tag. PR titles are the squash-merge subjects it reads, so they must be Conventional Commits with
a lowercase subject (`validate-pr-title.yml` enforces it). `feat!:` or a `BREAKING CHANGE:` footer
makes the next release a major.

## Contributor Recipes

**Add a new event type**: define model struct → add `EventItem` case in `EventManager.swift` → add `Topsort.track(...)` method

**Add a new auction field**: add property to model struct in `Auctions.swift` → `Codable` auto-picks it up

**Add a new UI component**: new file in `Sources/TopsortBanners/` → depend on `Topsort` target → accept `TopsortProtocol` for DI

**Add a new test**: use `MockHTTPClient` for network-level mocks, `MockTopsort` for SDK-level mocks
