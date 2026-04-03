# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Breaking:** `Topsort.shared.configure()` now throws `ConfigurationError` on invalid URL
- **Breaking:** `AuctionProducts.init(ids:qualityScores:)` now throws `ValidationError` on mismatched array lengths

### Fixed
- Replace `fatalError()` calls with recoverable thrown errors
- Fix data race in `FilePersistedValue` by synchronizing reads with `serialQueue.sync`

### Added
- `ConfigurationError` and `ValidationError` error types with `LocalizedError` conformance
- EventManager, PendingEvents, and AuctionProducts test coverage (12 to 30 tests)
- `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`
- GitHub issue templates and pull request template

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
