# Analytics.swift

## Objectives

- Easy-to-use, just configure and go iOS analytics library.
- Support for multiple iOS versions.
  - No async/await sadly :(
- Support for both SwiftUI and UIKit.
- Support for Objective-C even.
- User can send events manually, but also automatically track events.
- Distribution via Swift packages, cocoa pods, and carthage.
- CI / CD via Github Actions.
  - Maybe even use fastlane.

## Tasks

- [ ] Topsort events API client
  - No need to use OpenAPI generator
  - [x] API Models
    - [x] Tests
  - [x] Map API Errors
    - [ ] Tests
  - [ ] Simple function that send events to the Topsort API. No need for a class for now.
    - [ ] Tests
  - [ ] Main class with configuration (API Key, optional custom host, etc)
    - [ ] Tests

## Questions

- How do we achieve global compatibility?
  - Is there an LTS swift / iOS version?
    - Segment uses 13.0
- How can we inspect the main view for products?
  - Does it work the same on SwiftUI and UIKit?
