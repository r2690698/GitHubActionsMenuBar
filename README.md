# GitHubActionsMenuBar

Native macOS menu bar app for monitoring GitHub Actions across repositories.

## Overview

- Uses SwiftUI/AppKit and runs as a menu bar app.
- Uses GitHub App device flow for browser-based sign-in.
- Stores the GitHub App user session in the macOS Keychain.
- Lists repositories with GitHub Actions workflows, ordered by latest activity.
- Shows the latest workflow status per repository and lets you drill into jobs and steps.
- Shows a status symbol in the menu bar for running, passed, or failed actions.
- Refreshes every 30 seconds.
- Supports local notifications for started, passed, and failed runs, with a test action in Settings.

## GitHub App Setup

Create a GitHub App with:

- Repository `Metadata: Read-only`
- Repository `Actions: Read-only`
- Device Flow enabled

Then install the app on your personal account and any organizations you want to monitor.

## Local Development

1. Open the package in Xcode, or run from SwiftPM.
2. Build with `swift build`.
3. Launch the app from Xcode or from the built product.
4. Open Settings from the menu bar app.
5. Click `Sign In With Browser`.
6. Complete the GitHub browser flow.
7. Install the GitHub App on the accounts and organizations you want included.

## Tests

Run the self-test suite with:

```bash
swift run GitHubActionsMenuBar --self-test
```

The self-tests currently cover:

- Run-state mapping for queued/running/passed/failed workflows
- Auth session expiry behavior
- Model decoding for workflow runs, jobs, steps, and device-flow responses

## Versioning And Releases

- The production version lives in the `VERSION` file.
- Use simple semantic versions such as `1.0.0`, `1.0.1`, `1.1.0`.
- Pull requests produce a GitHub prerelease tagged from the current version with a beta suffix.
  Example: `v1.0.0-beta.pr12`
- Pushes to `main` produce or update the production release for the exact version in `VERSION`.
- Before merging a release-worthy change to `main`, bump `VERSION` if you want a new production release tag.

## Project Structure

- `Sources/GitHubActionsMenuBar/GitHubActionsMenuBarApp.swift`
  App entry point and menu bar label wiring.
- `Sources/GitHubActionsMenuBar/GitHubActionsStore.swift`
  Main state container for auth, refresh polling, notifications, and job loading.
- `Sources/GitHubActionsMenuBar/GitHubClient.swift`
  GitHub App auth flow and GitHub REST API client.
- `Sources/GitHubActionsMenuBar/Views.swift`
  Main menu UI, repo list, drill-in detail view, and settings.
- `Sources/GitHubActionsMenuBar/Notifications.swift`
  macOS local notification handling.
- `Sources/GitHubActionsMenuBar/KeychainStore.swift`
  Secure storage for the GitHub App user session.
- `Sources/GitHubActionsMenuBar/SelfTestSupport.swift`
  Lightweight self-test runner for stable model and auth behaviors.

## Packaging A Runnable App

1. Build a release binary with `swift build -c release`.
2. Package the app bundle with `./scripts/package_app.sh`.
3. Open `dist/GitHubActionsMenuBar.app`.

## Notes

- The current machine is pointing to Command Line Tools, so `xcodebuild` is unavailable until full Xcode is selected.
- Polling is currently every 30 seconds. If you monitor a very large number of repositories, you may want to raise the interval to reduce API pressure.
- The packaged app icon is generated from `assets/Actions.png` by `scripts/build_app_icon.sh`.
- GitHub Actions release publishing for pull requests is skipped automatically for forked PRs, because GitHub does not grant write release permissions there by default.
