# In-app auto-update

Goal: a "Claude-style" flow — a popup appears, the user clicks **Update & Restart**,
the new version downloads (verified), swaps in, and the app relaunches.

## What's in the app already

| Piece | File | Status |
|---|---|---|
| Feed model (per-platform package + SHA-256) | `lib/shared/providers/version_provider.dart` | ✅ |
| Updater: download (MOTW-free) → SHA-256 verify → apply | `lib/shared/services/app_updater.dart` | ✅ (apply **gated off**) |
| Provider | `lib/shared/providers/update_provider.dart` | ✅ |
| Popup banner ("Update & Restart") | `lib/shared/widgets/update_banner.dart` | ✅ |
| Mounted app-wide (under the lock) | `lib/main.dart` | ✅ |

The download + integrity check are live. The **swap-and-relaunch (`apply`) is gated by
`AppUpdater.applyEnabled = false`** until verified on real machines — a wrong swap can
brick the install and it can't be tested in CI. Until then the button reveals the
verified package instead of swapping.

## 1. The feed: `global/app_version` (Firestore)

```jsonc
{
  "latestVersion": "1.4.0",
  "minimumVersion": "1.2.0",        // < this → forced (_VersionGate) update
  "releaseNotes": "Bug fixes…",
  "platforms": {
    "macos":   { "url": "https://…/Tulanam-1.4.0-mac.zip", "sha256": "<hex>", "size": 84211000 },
    "windows": { "url": "https://…/Tulanam-1.4.0-win.zip", "sha256": "<hex>", "size": 79110000 }
  }
}
```

`size` is optional (used for an accurate progress bar). `updateUrl` (legacy single URL)
is still read as a fallback.

## 2. Packaging + hosting per release

**macOS (you have Apple Developer ID):**
1. `flutter build macos --release`
2. **Codesign** the `.app` with your Developer-ID Application cert (hardened runtime).
3. **Notarize** (`xcrun notarytool submit … --wait`) and **staple** (`xcrun stapler staple`).
   *Gatekeeper blocks the relaunch otherwise.*
4. Zip it: `ditto -c -k --keepParent "Tulanam.app" Tulanam-<v>-mac.zip`
5. `shasum -a 256 Tulanam-<v>-mac.zip` → put hash + size in the feed.

**Windows (no signing — per the decision):**
1. `flutter build windows --release` → the `Release` folder is the install.
2. Zip the **contents** of that folder: `Tulanam-<v>-win.zip`.
3. `CertUtil -hashfile Tulanam-<v>-win.zip SHA256` → hash + size into the feed.
4. Ship the app as a **per-user install** under `%LOCALAPPDATA%\Tulanam` (NOT `Program Files`)
   so the updater can swap files without UAC. First install shows a one-time SmartScreen
   "unknown publisher" warning (unavoidable without signing); updates after that are silent.

**Host** the two zips on any HTTPS host (Firebase Storage/Hosting, S3, a CDN), then write
their URLs + SHA-256 into `global/app_version`.

## 3. Enabling the silent apply (after testing)

The apply helpers are implemented but **off**. Before flipping `applyEnabled = true`:
- **macOS:** install the app, publish a newer notarized build to the feed, click
  Update & Restart → confirm it swaps `…/Tulanam.app` and relaunches on the new version
  (Gatekeeper must accept it — i.e. notarization worked).
- **Windows:** install per-user, publish a newer build, click Update & Restart → confirm
  the PowerShell helper waits for exit, extracts over `%LOCALAPPDATA%\Tulanam`, and relaunches.
  Watch for AV false-positives on the unsigned self-updater.

Then set `AppUpdater.applyEnabled = true` and move forced (`updateRequired`) updates from the
`_VersionGate` "Close App" dialog to the banner's Update & Restart.

## 4. Costs / prerequisites
- **Apple Developer Program** — $99/yr (Developer-ID signing + notarization). Required for macOS silent updates.
- **Windows** — none (unsigned; one-time first-install SmartScreen warning). Optional later:
  **Azure Trusted Signing** (~$120/yr) drops in as the signing step with no redesign.
- **Hosting** for the two zips + the Firestore feed.

## 5. Hardening ideas (later)
- Sign the feed/package with an Ed25519 key (public key in the app) in addition to SHA-256.
- Delta updates (ship only changed files) to shrink downloads.
- Staged rollout % in the feed.
- Swap the custom macOS path for **Sparkle** (via `auto_updater`) if you want its
  battle-tested install + appcast — same UX, more native machinery.
