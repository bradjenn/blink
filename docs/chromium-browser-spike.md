# Chromium Project Browser Spike

## Release Framing

For the next Blink release, the browser should be presented as an isolated project browser:

- a project-scoped browser pane inside the workspace
- optimized for local development, docs, auth flows, and project links
- not a full personal browser replacement

Acceptable limitations for this release:

- no sync/import story
- no claim of full browser parity with Safari/Chrome
- rough edges in niche popup or window-management flows are acceptable if the main project workflow is solid
- "Open in default browser" remains the escape hatch for unsupported cases

## Goal

Move Blink's browser panes toward a Chromium-backed runtime that can support:

- project-scoped browser profiles
- modern site compatibility
- popup/window flows that behave like a real browser
- browser-specific tab creation when a browser pane is focused

## Branch Scope

This branch does two things in parallel:

1. lands browser UX changes that should survive the engine swap
2. prepares the build/runtime seams for a CEF integration spike

## Product Decisions

- `Cmd-T` should open a browser tab when the active pane is a browser.
- New browser tabs opened from the active project should land on `https://daily.dev`.
- Browser tabs should continue to participate in Blink's existing workspace layout model.

## Immediate Implementation Steps

1. Keep the current browser actions flowing through `AppStore`.
2. Treat `BrowserManager` as the engine boundary.
3. Add a `BrowserEngine` type now so state/actions are not implicitly WebKit-only.
4. Chromium is now the active runtime in app builds; keep WebKit as the fallback and test harness path until Chromium coverage catches up.

## CEF Integration Checklist

### Build And Packaging

- Add the CEF framework and resources to the repo or to a managed vendor location.
- Update [`project.yml`](../project.yml) to embed the CEF framework and any required helper targets/resources.
- Add Objective-C++ / C++ build support for the CEF bridge layer.
- Regenerate [`Blink.xcodeproj`](../Blink.xcodeproj/project.pbxproj) via `xcodegen`.

### Runtime

- Add a Chromium browser controller/manager alongside the current WebKit controller.
- Route `BrowserManager` through the selected engine.
- Create project-scoped Chromium profile directories for cookie/storage isolation.
- Map Chromium popup creation into Blink browser tabs instead of dropping requests.

### macOS App Structure

- Add helper subprocess handling required by Chromium/CEF.
- Verify codesigning and notarization for the main app and helper binaries.
- Validate local development and release packaging separately.

## Release Readiness Gaps

- Chromium smoke coverage is still more important than the current unit test suite, because tests mostly exercise the fallback path.
- Product copy and release notes need to say "isolated project browser" consistently.
- Release builds need a final packaging sanity check for the CEF helper/runtime bundle layout.

## Non-Goals For This Spike

- replacing every WebKit path immediately
- shipping a release-quality Chromium browser in one pass
- building profile sync/history/download management
