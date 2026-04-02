# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ObservationCompanion is a SwiftUI iOS app for real-time Eagle Eye Networks camera monitoring, built on the [EENSwiftToolkit](https://github.com/klaushofrichter/een-swift-toolkit) Swift SDK. It includes a watchOS companion app and Dynamic Island widgets.

**Targets:** iOS 16+, watchOS 10+, Xcode 15+

## Build & Test Commands

```bash
# Build for iOS Simulator
xcodebuild build -project ObservationCompanion.xcodeproj \
  -scheme ObservationCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run unit tests (62 tests, no credentials needed)
xcodebuild test -project ObservationCompanion.xcodeproj \
  -scheme ObservationCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ObservationCompanionTests

# Run E2E tests (requires .env with TEST_USER, TEST_PASSWORD, plus Node.js/Playwright)
./run-e2e-tests.sh
```

## Architecture

**MVVM with centralized state.** `AppState` is an `ObservableObject` singleton passed via `@EnvironmentObject`. It owns connection state, HLS player, SSE event stream, token TTL, and camera list.

### Connection state machine

`scanning` (QR/OAuth input) -> `connecting` (loading camera + feed) -> `live` (streaming + events) -> `expired` / `error(String)`

### Authentication modes
- **QR Code / deep link:** Token injected via URL scheme `eenobserve://view?token=...&cam=...&base=...&ttl=...&events=...`
- **OAuth:** Full flow through `OAuthWebView` -> een-mobile-proxy -> Keychain token storage with auto-refresh

### Key data flow
1. Auth provides token + base URL -> `EENSwiftToolkit` initialized
2. Camera info fetched via `toolkit.cameras.get(id:)`
3. HLS feed URL from `toolkit.feeds.list(params:)` -> AVPlayer
4. SSE subscription via `toolkit.eventSubscriptions.create/connect` for real-time events
5. Historical events loaded via `toolkit.events.list(params:)` (up to 250)
6. Events forwarded to watchOS via `PhoneWatchConnectivityManager`

### Xcode targets
- **ObservationCompanion** — main iOS app
- **ObservationCompanionWatch** — watchOS companion
- **ObservationCompanionWidgets** — Dynamic Island / Lock Screen Live Activity
- **Shared/** — models shared between iOS and watchOS (`WatchEvent`, `MonitoringActivityAttributes`)

## Versioning

Pre-commit hook (`.husky/pre-commit`) auto-bumps the patch version in `package.json` and regenerates `ObservationCompanion/Version.swift` via `scripts/generate-version.sh`. Both files are auto-staged. Do not edit `Version.swift` manually.

## Dependencies

- **EENSwiftToolkit** — Swift package (SPM, `production` branch) for Eagle Eye Networks API v3.0
- **Node.js packages** (testing/tooling only): playwright, dotenv, husky

## CI/CD

- **tests.yml** — PR to `production`: build + unit tests; E2E is manual-trigger only
- **release.yml** — merge to `production`: creates GitHub Release from `package.json` version, syncs back to `develop`

## Branch Strategy

`develop` is the working branch. PRs go to `production` for release. After merge, `production` syncs back to `develop`.
