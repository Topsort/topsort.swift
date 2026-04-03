# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-03-18

### Fixed
- Resolve swiftformat lint violations
- Replace `AsyncImage` with ephemeral `URLSession` image loader in banners
- Fix `LazyVStack` layout issue in `BannerView`

### Changed
- Refactor banner components

### Added
- Project documentation (`CLAUDE.md`)

## [1.0.1-alpha.0] - 2024-10-23

### Fixed
- Remove circular references from `FilePersistedValue`

### Added
- Run typos linter in CI
- Introduce swiftformat for code style enforcement

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
