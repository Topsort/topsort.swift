# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-08-29

Everything since 1.0.0. Three things change silently on upgrade and are worth knowing about
before you ship: events go out in batches (a proxy or WAF sees fewer, larger `POST /v2/events`
requests), the on-disk queue moves from `Documents` to `Application Support` (migrated
automatically on first launch), and a `4xx` response is no longer retried.

### Added
- `Configuration` struct and `configure(_:)` — `apiKey`, `url`, `auctionsTimeout`, `flushAt`,
  `flushInterval`, `logLevel`. The positional `configure(apiKey:url:auctionsTimeout:)` is
  deprecated but still works
- Event batching: events accumulate until `flushAt` (default 30) or `flushInterval`
  (default 30 s, was a fixed 60 s), and `flush()` sends them on demand
- Flush and persist when the app goes to the background or terminates
- Skip sends while offline (`NWPathMonitor`) and flush when connectivity returns
- Pageview events: `track(pageview:)`, `PageViewEvent`, `Page`
- Event fields from the API spec: `deviceType`, `channel`, `additionalAttribution`, `clickType`
  on `Event`; `deviceType`, `channel` on `PurchaseEvent`; `vendorId` on `PurchaseItem`
- Auction fields from the API spec: `Auction.opaqueUserId`, `Auction.placementId`,
  `Winner.campaignId`, `Asset.content`
- `Topsort.isConfigured`; `track()` before `configure()` logs a warning and drops the event,
  `executeAuctions()` throws `AuctionError.notConfigured`
- Structured logging with `LogLevel` (`none`, `error`, `warning`, `debug`)
- `ConfigurationError` (including `.notConfigured`) and `ValidationError` with `LocalizedError`
  conformance
- API contract tests against the OpenAPI spec; `CONTRIBUTING.md`, `SECURITY.md`, issue and
  pull request templates

### Changed
- `Topsort.shared.configure()` throws `ConfigurationError` on an invalid URL instead of
  crashing; `AuctionProducts.init(ids:qualityScores:)` throws `ValidationError` on mismatched
  lengths. Callers now need `try`
- Queue and pending-event files live in `Application Support/com.topsort.analytics/`, not
  `Documents`. Existing files are moved on first launch
- Persistence is debounced (5 s) to reduce disk writes
- `swift-tools-version` is 5.9 (was 5.3). The sources already required a Swift 6 toolchain
  (typed throws); the manifest now says so
- `opaqueUserId` is an explicit parameter in `Event` constructors
- `AuctionCategory.disjunctions` is `[[String]]`, as the API defines it

### Fixed
- Banner impressions fire when the image has loaded, not when the auction responds (#28)
- A batch that exhausted its 50 retries was never removed and was re-sent on every flush,
  forever (#50)
- Every status except 400 was retried. 4xx is now permanent, except 408 and 429; 5xx and
  transport failures still retry (#51)
- A flush that ran before `configure()` (timer, backgrounding, connectivity) posted the queue
  restored from disk without a key; it now waits for the key instead of losing the batch to a
  401 (#51)
- The event queue is capped at 5,000 events (oldest dropped first) and a `POST` carries at
  most 500, so a long offline backlog can no longer produce one oversized request (#52)
- An event that cannot be serialized (a non-finite `unitPrice`, say) is dropped on its own
  instead of stalling the queue or taking its batch with it (#52)
- Data race in `FilePersistedValue` reads
- Deadlock when persisting from the background notification (#38)

### Removed
- tvOS and watchOS from `Package.swift`. The declared floors (tvOS 11, watchOS 7.1) were below what the
  sources need and never compiled, so no integrator could have been on them (#53)
- Codecov integration (#49)

## [1.0.0] - 2025-03-18

### Fixed
- Resolve swiftformat lint violations
- Replace `AsyncImage` with ephemeral `URLSession` image loader in banners
- Fix `LazyVStack` layout issue in `BannerView`

### Changed
- Refactor banner components

### Added
- Project documentation (`CLAUDE.md`)

## [1.0.0-alpha.0] - 2024-08-26

### Added
- Initial SDK release
- Core auction API (`executeAuctions`)
- Event tracking (impressions, clicks, purchases) with batching and retry
- `TopsortBanner` SwiftUI component
- File-based event persistence across app launches
- Exponential backoff retry (up to 50 retries, 1200s max backoff)
- Zero external dependencies
- CI workflows for testing, formatting, typos, and action linting

> **Note:** The git tag `1.0.1-alpha.0` (2024-10-23) was created between `1.0.0-alpha.0` and `1.0.0` and contained fixes for `FilePersistedValue` circular references and CI improvements. It is omitted from this changelog as the version number is a SemVer anomaly (pre-release of 1.0.1 predating 1.0.0 stable).
