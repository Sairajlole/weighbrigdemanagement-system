# Release, deployment & post-production maintenance

A factual map of what's implemented today, the gaps, and how to operate the app
after it's in customers' hands. Last reviewed 2026-06.

> **Implemented 2026-06 (this pass):**
> - **Client error reporting** → `CrashReporter` (`lib/shared/services/crash_reporter.dart`)
>   captures Flutter + uncaught async errors into the server-only `error_reports`
>   Firestore collection. (Crashlytics has no Windows support, so this is the
>   Firebase-native substitute. Native C++ crashes still aren't captured — Sentry
>   would add that.) **§5 gap is now closed.**
> - **Firebase-native publish** → the Storage-triggered Cloud Function
>   `onReleaseUploaded` (`functions/release_publish.js`): drop a zip at
>   `releases/{version}/{file}` and it computes sha256 + size and fills
>   `global/app_version` automatically. **No more manual feed editing.**
> - **CI release** → `.github/workflows/release.yml`: push a tag `vX.Y.Z` → builds
>   Windows (and macOS) → uploads to Storage → the function publishes the feed.
> - Manual path still works: `tool/release.sh` / `tool/publish_release.js`.
>
> **Why GitHub Actions (not "a Firebase feature") for builds:** Firebase has no
> service that compiles desktop apps — building Windows/macOS needs OS-specific CI
> runners, which GitHub Actions provides and Firebase does not. Firebase's role is
> hosting (Storage), the feed (Firestore), the publish trigger, and auto-update.

---

## 1. The two halves of "the backend"

There are **two independent things** people lump together as "the backend":

| | What it is | How it's deployed | Visibility you have |
|---|---|---|---|
| **Cloud Functions + Firestore rules** (`functions/`, `firestore.rules`) | The server logic + DB security | **Manual:** `firebase deploy --only functions,firestore:rules` from your machine | ✅ Good — logs in the Firebase/GCP console |
| **The Flutter desktop app** (the `.exe` / `.app` on weighbridge PCs) | The program operators run | **Self-update** via the version feed (below) | ❌ **None in production** (see §5) |

These are separate. Deploying functions does **not** update the installed app, and
shipping a new app does **not** change the server.

---

## 2. How the app self-updates today ("continuous push")

```
 You publish a release                The app, on every PC
 ─────────────────────                ─────────────────────
 1. Build + zip the app               a. On launch + every 6h, reads the
 2. Upload zip to a host                 Firestore doc  global/app_version
 3. Edit  global/app_version  ───────▶ b. Compares its version to latestVersion
    (latestVersion + platform           c. If newer + a verifiable package exists:
     url + sha256)                          • downloads the zip itself
                                            • checks it against the sha256
                                            • swaps files + relaunches
                                              (only when no live weighing cycle)
```

**The "update notice" is a single Firestore document: `global/app_version`.**
Shape the app reads (`version_provider.dart`):

```json
{
  "latestVersion": "1.1.0",
  "minimumVersion": "1.0.0",          // optional — force-update floor (see §4)
  "releaseNotes": "What changed…",
  "platforms": {
    "windows": { "url": "https://…/Tulanam-1.1.0-win.zip", "sha256": "<hex>", "size": 123456789 },
    "macos":   { "url": "https://…/Tulanam-1.1.0-mac.zip", "sha256": "<hex>", "size": 123456789 }
  }
}
```

**Why "manual install required" appears:** the app self-installs **only** when the
platform block has BOTH `url` and `sha256` (so it can download *and* verify the
package). If those are missing — which is the current state — the app knows a
version exists but has nothing trustworthy to install. **This is a release-config
gap, not a bug.** Fill `platforms.{os}` and it auto-updates.

- Optional updates (`latestVersion` > current): **silent** — download + restart in
  an idle gap, no banner. Status is shown inline on the Profile page.
- Required updates (`current` < `minimumVersion`): **full-screen block** until updated.
- The real swap-and-relaunch is enabled (`AppUpdater.applyEnabled = true`).
  ⚠️ macOS packages must be **Developer-ID signed + notarized** or the relaunch is
  blocked by Gatekeeper — test on a real Mac before relying on it.

**Today the publish step (1–3) is fully manual.** The release script in §6 automates it.

---

## 3. How new builds are produced today

- **`.github/workflows/build-windows.yml`** builds a Windows release on every push
  to `main` and uploads it as a **GitHub artifact** (7-day retention).
  - It does **not** sign, zip-for-update, upload to a host, or touch `global/app_version`.
  - There is **no macOS build CI**.
- So today: CI gives you a Windows build to download; everything after that (zip,
  hash, host, update the feed) is by hand.

---

## 4. Kill switch / forced rollout (already available)

You can force every PC onto a version by setting **`minimumVersion`** in
`global/app_version`. Any app below it shows a blocking screen until it updates.
Use this for: a critical bug fix, a security patch, or a server change that needs a
matching client. (It's only as strong as the auto-update working — see §6/§2.)

---

## 5. Bug identification after production — **the real gap**

| Layer | Can you see problems in production? |
|---|---|
| **Cloud Functions** | ✅ Yes — `console.error/warn` (170 sites) land in **Firebase Console → Functions → Logs** (and GCP Logging). You can search, alert, and trace server errors. |
| **The desktop app** | ❌ **No.** There is **no crash reporting, no error telemetry, no analytics.** No `FlutterError.onError` / `runZonedGuarded` handler. Client errors are `debugPrint` only — printed to a console nobody sees on a customer's PC. **If the app crashes on a weighbridge, you won't know unless someone phones you.** |

**This is the single most important thing to fix for "maintenance after production."**
Right now you are blind to client-side crashes and errors.

### Recommended: add crash + error reporting (Firebase Crashlytics)
- Free, Firebase-native, supports Flutter desktop reasonably (Windows/macOS via the
  Crashlytics SDK; for unsupported bits, fall back to logging non-fatals to Firestore).
- Wire once in `main.dart`:
  - `FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;`
  - wrap `runApp` in `runZonedGuarded(..., (e, s) => FirebaseCrashlytics.instance.recordError(e, s, fatal: true))`.
  - log handled errors with `recordError(e, s)` in the `catch` blocks that matter.
- Result: a dashboard of crashes/errors **by version**, with stack traces and how many
  devices are hit — so you find bugs *before* customers report them, and confirm a fix
  landed after pushing an update.

(Alternative: **Sentry** — also good for Flutter desktop, richer, paid above a free tier.)

---

## 6. The release process — going forward

### One-time setup
1. **Host = Firebase Storage** (bucket `weighbridge-management.firebasestorage.app`).
2. Release packages must be **publicly downloadable** — the script uses `makePublic()`,
   which sets a public object URL (independent of Storage *security rules*).
3. Auth for the publish script: `gcloud auth application-default login` once (or set
   `GOOGLE_APPLICATION_CREDENTIALS` to a service-account key).

### Each release
```bash
# 1. Bump the version in pubspec.yaml (e.g. version: 1.1.0+5)
# 2. On macOS:
tool/release.sh 1.1.0                 # builds, NOTARIZE the .app, zips, uploads, updates the feed
# 3. On a Windows machine:
flutter build windows --release
#    zip build\windows\x64\runner\Release\  → Tulanam-1.1.0-win.zip
node tool/publish_release.js windows 1.1.0 Tulanam-1.1.0-win.zip
# 4. (optional) force everyone onto it:
node tool/publish_release.js windows 1.1.0 Tulanam-1.1.0-win.zip --required
```
After step 2/3, installed apps pick it up within ~6h (or instantly on Profile →
Check for updates) and auto-update in an idle gap.

### The cross-compile rule
You can only build for the OS you're on. Build Windows on Windows (or in CI), macOS
on macOS. The script publishes whatever you built.

### Better: automate it in CI (recommended next step)
Extend `build-windows.yml` (and add a macOS job) so that on a **git tag** (e.g.
`v1.1.0`) it builds, zips, uploads to Firebase Storage, and updates `global/app_version`
automatically — turning a release into "push a tag." (Needs a service-account secret
in GitHub.)

---

## 7. The post-production loop (how to actually maintain)

```
        ┌─────────────────────────────────────────────────────────┐
        │ 1. OBSERVE   server: Functions logs/alerts                │
        │              client: Crashlytics (after §5)  ← add this   │
        │ 2. TRIAGE    reproduce, find the version + device impact  │
        │ 3. FIX       branch → fix → flutter analyze / tests       │
        │ 4. SHIP      server bug → firebase deploy (instant)       │
        │              client bug → tool/release.sh (auto-update)   │
        │ 5. ENFORCE   critical? set minimumVersion (force update)  │
        │ 6. VERIFY    confirm the error stops in the dashboards     │
        └─────────────────────────────────────────────────────────┘
```

- **Server bugs are easy:** fix → `firebase deploy --only functions` → live for everyone
  immediately (no client update needed). You already have the logs to find them.
- **Client bugs need a release** (§6) — and you need §5 to *find* them in the first place.
- **Data fixes:** one-off Firestore corrections via the Admin SDK / console; never hand-edit
  `credentials`, `auth_sessions`, `operator_pins` (server-only) except through a script.
- **Rollback:** to undo a bad app release, set `global/app_version` back to the previous
  `latestVersion` + its package; to undo functions, redeploy the previous commit.

---

## 8. Priorities (what to do, in order)
1. **Add Crashlytics** (§5) — without it you can't see production bugs. Highest value.
2. **Fill `global/app_version.platforms`** via the release script (§6) so auto-update works.
3. **Test the macOS notarized self-update + Windows self-update** end-to-end once.
4. **Automate releases in CI** on a tag (§6) — removes the manual steps.
5. (Optional) lightweight **analytics** (Firebase Analytics) if you want usage insight.
</content>
