# Share Extension — Setup, Architecture & Testing Guide

This makes **Eternal-Hackathon-2026** appear in the iOS Share Sheet
(`UIActivityViewController`) alongside WhatsApp, Messages, Notes, etc.

All Swift/plist/entitlements files are already written. The steps below wire
them into the Xcode project (adding a new target and toggling capabilities
**must** be done in the Xcode GUI — it edits `project.pbxproj` and
provisioning safely).

---

## 0. Key identifiers (already baked into the code)

| Thing | Value |
|---|---|
| Main app bundle ID | `com.hackathon.Eternal-Hackathon-2026` |
| Extension bundle ID | `com.hackathon.Eternal-Hackathon-2026.ShareExtension` |
| App Group | `group.com.hackathon.Eternal-Hackathon-2026` |
| URL scheme | `eternalhackathon` |
| Deep link | `eternalhackathon://shared` |

If you change any of these, update `Shared/SharedConstants.swift` to match.

---

## 1. Add the Share Extension target

1. Open `Eternal-Hackathon-2026.xcodeproj` in Xcode.
2. **File ▸ New ▸ Target…**
3. Pick **Share Extension** → **Next**.
4. Product Name: **`ShareExtension`**. Language: Swift. **Finish**.
5. When prompted **"Activate ShareExtension scheme?"** → **Cancel** (keep the
   app scheme active; you'll run the extension via the host app anyway).

Xcode generates a `ShareExtension/` group with a template `ShareViewController.swift`,
`Info.plist`, and a `MainInterface.storyboard`.

6. **Delete the generated files** (`ShareViewController.swift`, `Info.plist`,
   and `MainInterface.storyboard`) — choose **Move to Trash**. We provide our
   own and don't use a storyboard.

---

## 2. Add the provided files to the correct targets

In Finder these already exist on disk. Add them to Xcode:

**Shared layer (add to BOTH targets):**
1. Right-click the project ▸ **Add Files to "Eternal-Hackathon-2026"…**
2. Select the `Shared/` folder → **Create groups**.
3. In **Target Membership** (File Inspector, right pane) tick **both**
   `Eternal-Hackathon-2026` **and** `ShareExtension` for:
   - `Shared/SharedConstants.swift`
   - `Shared/SharedContent.swift`
   - `Shared/SharedDataManager.swift`

**Extension files (ShareExtension target only):**
- `ShareExtension/ShareViewController.swift`
- `ShareExtension/ShareExtensionCoordinator.swift`
- `ShareExtension/ShareItemExtractor.swift`
Add them, membership = **ShareExtension only**.

**Main-app files (app target only):**
- `Eternal-Hackathon-2026/DeepLink/DeepLinkManager.swift`
- `Eternal-Hackathon-2026/DeepLink/AppLaunchManager.swift`
- `Eternal-Hackathon-2026/SharedInbox/SharedInboxViewModel.swift`
- `Eternal-Hackathon-2026/SharedInbox/SharedInboxViewController.swift`
(`SceneDelegate.swift`, `ViewController.swift`, `Info.plist` are already in
the target — they were edited in place.)

> Tip: select a file → open the **File Inspector** (⌥⌘1) → **Target
> Membership** to verify the checkboxes.

---

## 3. Point the extension at the provided Info.plist

1. Select the **ShareExtension** target ▸ **Build Settings**.
2. Search `INFOPLIST_FILE`.
3. Set it to `ShareExtension/Info.plist` (the file we wrote, with the
   activation rule). Make sure the template one is gone/unused.

The activation rule in that plist is what makes your app show up **only** when
the share payload contains a URL, image, PDF, movie, or text.

---

## 4. Enable the App Group on BOTH targets

Do this for the **app** target, then repeat for the **ShareExtension** target:

1. Select target ▸ **Signing & Capabilities**.
2. Confirm **Automatically manage signing** is on and the Team is `5QTW3RVA4Y`.
3. Click **+ Capability** ▸ **App Groups**.
4. Click **+** under App Groups and add exactly:
   `group.com.hackathon.Eternal-Hackathon-2026`
5. Ensure the checkbox next to it is **ticked**.

This regenerates each target's `.entitlements`. We already committed the
expected contents (`*.entitlements` files) — if Xcode created new ones, either
point `CODE_SIGN_ENTITLEMENTS` at ours or just confirm the group string
matches. **The group string must be byte-identical in both**, or the shared
container will be `nil` and nothing hands off.

---

## 5. Verify the URL scheme (main app)

Already added to `Eternal-Hackathon-2026/Info.plist` under `CFBundleURLTypes`
(scheme `eternalhackathon`). Nothing to do unless you renamed it.

---

## 6. Build & run

1. Select the **app** scheme + a simulator/device → **Run** (⌘R).
2. Stop it. Now select the **ShareExtension** scheme → **Run**; Xcode asks
   which host app to attach to — pick **Safari** or **Photos**. This lets you
   set breakpoints inside the extension.

---

## Architecture (MVVM + coordinators)

```
┌──────────────── Share Extension (separate process) ────────────────┐
│ ShareViewController  ── thin UIKit, shows status card               │
│        │ drives                                                     │
│ ShareExtensionCoordinator ── extract → persist → build deep link    │
│        │ uses                                                       │
│ ShareItemExtractor ── NSExtensionItem → NSItemProvider → async load │
└───────────────────────────────┬─────────────────────────────────────┘
                                 │  writes via
                    ┌────────────▼─────────────┐
                    │      SharedDataManager     │  ← App Group container
                    │  (UserDefaults + files)    │     (shared by both)
                    └────────────┬─────────────┘
                                 │  reads via
┌────────────────────────────────▼──────────────── Main App ──────────┐
│ SceneDelegate → AppLaunchManager → DeepLinkManager (route)           │
│        │ posts .didReceiveSharedContent                              │
│ SharedInboxViewModel  (MVVM)  →  SharedInboxViewController           │
└──────────────────────────────────────────────────────────────────────┘
```

- **ShareViewController** — entry point; no business logic.
- **ShareExtensionCoordinator** — orchestration + timeout, UIKit-free/testable.
- **ShareItemExtractor** — turns `NSItemProvider`s into `SharedContent` with
  `async/await`; handles multiple attachments and picks the most specific type.
- **SharedDataManager** — the only thing that touches the App Group; serial
  queue for thread safety; small metadata → UserDefaults, big blobs → files.
- **DeepLinkManager** — URL → typed `DeepLinkRoute` (scheme *and* universal link).
- **AppLaunchManager** — drains the queue on link-open and on activation.
- **SharedInboxViewModel/ViewController** — MVVM display of received items.

### Data flow
1. User taps **Share** anywhere → picks your app.
2. Extractor pulls attachments, copies blobs into the App Group, enqueues
   lightweight `SharedContent` JSON.
3. Extension opens `eternalhackathon://shared` (responder-chain `openURL:`).
4. App's SceneDelegate resolves the route, `AppLaunchManager` drains the queue
   and posts a notification.
5. The inbox screen renders the items.

---

## Custom URL Scheme vs Universal Links

| | Custom URL Scheme (`eternalhackathon://`) | Universal Links (`https://…`) |
|---|---|---|
| Setup | Trivial — one Info.plist entry | Needs a web domain + `apple-app-site-association` + Associated Domains entitlement |
| Reliability from an extension | High, works offline | Can fall back to Safari if the app can't be verified |
| Spoofing | Any app can claim the same scheme | Cryptographically tied to your domain |
| Best for | Internal app↔extension handoff (this project) | Public links you also want to open web pages |

**This project uses the custom scheme** for the extension→app hop (simplest,
most reliable). `DeepLinkManager` already also recognizes an `https://…/shared`
universal link, so you can add domain hosting later without code changes.

---

## Supporting more content types later

1. Add the `UTType` to `ShareItemExtractor.supportedTypes` and a matching
   `hasItemConformingToTypeIdentifier` branch in `parse(_:)`.
2. Add a `SUBQUERY` clause for its UTI in `ShareExtension/Info.plist`
   (`NSExtensionActivationRule`).
3. If it's a new binary kind, add a case to `SharedContentKind` and a row
   mapping in `SharedInboxViewModel`.

---

## Error handling (already implemented)

| Case | Handling |
|---|---|
| Empty share | `ExtractionError.emptyShare` → alert, `cancelRequest` |
| Unsupported type | Unknown attachments skipped; all-unknown → alert |
| Invalid URL | Falls back to string parsing, else unsupported |
| Missing App Group | `SharedStorageError.appGroupUnavailable` surfaced |
| Storage failure | `ShareError.storageFailed` → alert |
| Extension timeout | `withTimeout` (12s) → `ShareError.timedOut` |
| User cancellation | System dismisses; `cancelRequest` used on errors |
| Corrupt queue JSON | Auto-reset in `SharedDataManager.decodeItems` |

---

## Testing guide

**Simulator**
1. Run the app once (installs it + registers the extension & scheme).
2. Open **Safari** → any page → **Share** → your app should appear (tap **More**
   / **Edit Actions** the first time if it's hidden).
3. Tap it → "Saved" card → the app foregrounds into the Shared Inbox.

**Per content type**
- **URL:** Safari page → Share.
- **Text:** Notes → select text → Share.
- **Image / multiple images:** Photos → select one or several → Share.
- **PDF:** Files → a PDF → Share.
- **Video:** Photos → a clip → Share.

**Deep link only (no share):** in Terminal:
```
xcrun simctl openurl booted "eternalhackathon://shared"
```
The Shared Inbox should present (showing any queued items).

**Debugging the extension:** run the **ShareExtension** scheme, attach to
Safari/Photos, set breakpoints in `ShareItemExtractor`/`ShareExtensionCoordinator`.

**Common gotchas**
- App not in sheet → activation rule too strict, or app not installed since
  last change. Delete the app from the device/sim and reinstall.
- Nothing hands off → App Group string mismatch between the two `.entitlements`.
- App doesn't open → the responder-chain `openURL:` fallback still *saves*;
  open the app manually and `sceneDidBecomeActive` drains the queue.
```
