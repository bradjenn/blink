# CEF Upgrade Smoke Tests

## Purpose

Use this checklist after:

- bumping CEF or Chromium
- changing popup routing or popup window lifecycle
- changing auth popup handling
- changing download handling
- changing WebAuthn, permission, or media prompt behavior

These are the highest-risk browser regressions in Blink because they cross Chromium, CEF, AppKit popup windows, and Blink's own popup policy.

## Test Environment

- Use the `Blink Dev` target.
- Start from a fresh build of the branch being tested.
- Prefer a clean app relaunch before the pass.
- If testing auth, keep one run with remembered login state and one run without it.

## Core Checks

### 1. Basic Browser Pane

- Open a workspace browser pane.
- Navigate to a normal site.
- Confirm typing in the address bar works.
- Confirm clicking web content focuses the page.
- Confirm back, forward, and reload work.
- Confirm `Cmd-W` closes only the active browser pane/window.

### 2. OAuth Popup Login

- Start a login flow that opens a popup.
- Confirm the popup can take focus and accept typing.
- Confirm closing the popup closes only the popup.
- Complete login with a full credential flow.
- Repeat with a remembered-login flow if available.
- Confirm the opener updates to the logged-in state without a manual refresh.
- Confirm the app does not crash during popup close.

### 3. Download Popup Flow

- Trigger a download from a site known to open a popup first.
- Confirm the download starts successfully.
- Confirm no blank or white popup window remains visible.
- Confirm the popup does not flash on screen.
- Confirm the download still completes if the popup stays hidden.

### 4. WebAuthn / Security Key / Nearby Device

- Trigger a login flow that may offer passkey, security key, or nearby-device auth.
- Confirm Blink does not crash if Chromium tries to enter that path.
- Confirm unexpected Bluetooth or permission prompts do not appear unless explicitly intended.
- If the prompt is intentionally suppressed, confirm fallback auth methods still work.

### 5. External Handoff Cases

- Trigger a popup that Blink is expected to hand off externally.
- Confirm it opens in the default browser.
- Confirm Blink does not keep a stray popup window around.
- Confirm the main Blink window remains stable.

### 6. Popup Close Semantics

- Open a normal popup window.
- Close it with the close button.
- Close it with `Cmd-W`.
- Confirm the main Blink app stays alive.
- Confirm no duplicate close behavior occurs.

## Regression Triggers To Watch

Pay extra attention if a change touches:

- `Blink/Browser/Chromium/BlinkChromiumBrowserHost.mm`
- `Blink/Browser/Chromium/BlinkChromiumRuntime.mm`
- popup focus or responder handling
- `OnBeforePopup`
- `OnShowPermissionPrompt`
- `OnRequestMediaAccessPermission`
- `OnBeforeDownload` / `OnDownloadUpdated`
- popup `NSWindow` close/lifetime handling

## Notes From Recent Failures

The most fragile pattern has been:

- show popup window immediately
- focus popup browser immediately
- classify the popup only after later URL/download/auth callbacks

That ordering causes auth, download, and popup-close regressions. When changing this area, prefer:

- classify first when possible
- delay presentation for generic popups
- keep auth behavior explicit
- keep hidden download popups alive long enough for the download to finish
- avoid synchronous AppKit teardown from Chromium callbacks

## Minimum Pre-Release Pass

Before merging a CEF/Chromium bump, at minimum verify:

1. one standard browser navigation flow
2. one OAuth popup flow
3. one download-triggering popup flow
4. one popup close flow with `Cmd-W`
5. one WebAuthn-adjacent login flow
