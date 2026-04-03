# Contributing to topsort.swift

Thank you for your interest in contributing to the Topsort Swift SDK!

## Development Setup

1. Clone the repository:

   ```sh
   git clone https://github.com/Topsort/topsort.swift.git
   cd topsort.swift
   ```

2. Build the project:

   ```sh
   swift build
   ```

3. Run tests:

   ```sh
   swift test
   ```

No Xcode project is needed — the SDK uses Swift Package Manager exclusively.

## Code Style

This project enforces formatting with [SwiftFormat](https://github.com/nicklockwood/SwiftFormat). Run it before submitting a PR:

```sh
swiftformat .
```

CI will reject PRs with formatting violations.

## Branch Naming

Use descriptive branch names with a conventional prefix:

- `feat/add-geo-targeting` — new features
- `fix/retry-backoff-overflow` — bug fixes
- `chore/update-ci-runner` — maintenance
- `docs/add-migration-guide` — documentation
- `test/event-manager-coverage` — tests
- `refactor/extract-http-layer` — refactoring

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add geo-targeting support to auctions
fix(banners): prevent duplicate impression tracking
chore: bump swiftformat to 0.60
test: add EventManager retry coverage
docs: update README with error handling examples
```

## Pull Requests

- Each PR should represent a single logical unit of work
- Include a summary of what changed and why
- Add a test plan describing how to verify the changes
- Ensure `swift build`, `swift test`, and `swiftformat .` all pass
- Large changes should be broken into stacked PRs

## Testing

- Use **XCTest** — no third-party test frameworks
- Use `MockHTTPClient` for network-level mocks and `MockTopsort` for SDK-level mocks
- All tests use `@testable import` to access internal types

## Reporting Bugs

Open an issue with:

- Swift version and platform (iOS/macOS/tvOS/watchOS)
- SDK version
- Steps to reproduce
- Expected vs actual behavior
