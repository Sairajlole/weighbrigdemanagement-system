# CLAUDE.md — Tulanam (weighbridge management)

Flutter **desktop** app (Windows + macOS) + **Firebase Cloud Functions** backend.
Brand: **Tulanam** (तुला = balance). India-hosted. First customer: YASH COTEX (cotton, Jalgaon MH).

## Project facts
- **Firebase project: `tulanam`** (org tulanam.com). Everything in **`asia-south1`** (Mumbai).
- Owner/ops account: **tech@tulanam.com**. Storage bucket: `tulanam.firebasestorage.app`.
- Migrated from the old `weighbridge-management` project — kept intact as backup, do NOT
  decommission until production is fully verified. See memory `tulanam-iam`.
- Custom auth (not Firebase Auth): `loginUser` verifies `credentials/{email}` (scrypt);
  the app uses anonymous Firebase Auth only for Firestore access during login.

## Build / run / deploy
- Flutter app: `flutter run -d macos` (or windows). Version lives in `pubspec.yaml`.
- Functions deploy: `firebase deploy --only functions:<name> --project tulanam` (CLI is
  logged in as tech@tulanam.com). gen-1 functions use the regional builder `const fns =
  functions.region("asia-south1")`; base `functions.https.HttpsError`/`config`/`logger` stay on `functions`.
- **After deploying any NEW callable (`onCall`) function, re-run `tool/grant_invokers.sh`** —
  the org's secure-by-default policy means new functions aren't publicly invokable otherwise.

## Workspace user provisioning
- `tool/create_workspace_user.js <email> "<Full Name>"` creates a tulanam.com Workspace
  user (Admin SDK Directory API) and sets their Google account profile photo to the brand
  avatar (`brand/tulanam_avatar_*.png`, default the light wordmark). Photo auto-applies to
  every user made via this script — and only this script (no domain-wide trigger). Modes:
  `--photo-only`, `--photo <path>`, `--check` (read-only auth test), `--dry-run`.
- Auth = gcloud ADC as super admin (tech@tulanam.com). Three one-time prerequisites, each of
  which produced a distinct error during first setup (all now done in prod):
  1. ADC scope: `gcloud auth application-default login --scopes=openid,https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/admin.directory.user`
     (default gcloud login lacks the directory scope).
  2. Trust the ADC OAuth client in Admin console → Security → API controls → App access
     control → Add app → OAuth Client ID `764086051850-6qr4p6gpi6hn506pt8ejuq83di341hur.apps.googleusercontent.com`
     → **Trusted**. Otherwise the consent screen shows "This app is blocked".
  3. `gcloud services enable admin.googleapis.com --project tulanam` (else 403 quota/disabled).
- The script sends `X-Goog-User-Project: tulanam` (user-cred ADC requires a quota project).
- Verified live: photo PUT works with URL-safe-Base64-with-padding (GAM-style). New-user
  creation returns `412 Domain user limit reached` when the Workspace subscription is out of
  seats — a billing/seat issue, not a script bug; free a seat and re-run the same command.
- **Scheduled enforcement** (covers users created any way, not just the CLI): the
  `brandUserPhotos` gen-1 function (`functions/index.js`, daily, Asia/Kolkata) re-stamps the
  brand photo onto EVERY tulanam.com user (enforce policy — overwrites custom photos too). It
  runs as the runtime SA `tulanam@appspot.gserviceaccount.com` impersonating tech@tulanam.com
  via KEYLESS domain-wide delegation (IAM `signJwt` → JWT-bearer; no key stored). Setup done:
  iamcredentials API enabled, SA has `serviceAccountTokenCreator` on itself. **Still required:
  authorize SA client `113449181934687086088` for the `admin.directory.user` scope under
  Admin console → API controls → Domain-wide delegation**, else every run fails the token
  exchange. Avatar bundled at `functions/assets/brand_avatar.png`. Config+status doc:
  `global/brandUserPhotos`. **Safe by default**: writes NO photos until that doc's
  `enabled === true` — every run before that just mints the token, lists users, and records
  the blast radius (`wouldStamp`, `sampleEmails`). Flip `enabled:true` to start enforcing.

## Versioning & releases
- See **VERSIONING.md**. `tool/bump_version.sh` decides the bump from `feat:`/`fix:` commits.
  `0.x` until public launch; `--launch` does the one-time `1.0.0 "Mundra"` jump.
- Tagging `vX.Y.Z` triggers `.github/workflows/release.yml` → uploads `releases/{version}/` →
  `onReleaseUploaded` writes `global/app_version` (the update feed).

## Post-production monitoring
- See **MONITORING.md**. Run `tool/triage_errors.sh` to triage the `error_reports`
  collection (client crashes). `errorReportDigest` (deployed) emails a daily summary.
- Keep the triage log in MONITORING.md current; fix highest `count × severity` first.

## Conventions / guardrails
- **Never print or commit `functions/.env`** (Meon/GSTIN/Gmail/MFA/license secrets). Never
  delete `functions/_test_emails.js`.
- `ALLOW_TEST_OTP` must stay unset in production (gates the `000000` OTP bypass — currently OFF).
- Face system: 3 generations; enrollment Storage is keyed by **operatorId** (server resolves
  it from email). See memory `face-frames-keying`. Live verification = local sidecar ArcFace.
- Commit style: Conventional Commits (`feat:`/`fix:`/`chore:`) — the version tooling depends on it.

## Maintaining this file
Update CLAUDE.md when a change alters **how future work should be done** — a new
convention, command, guardrail, or architecture decision. NOT for routine fixes/features
(git records those). Test: "would a future session do the wrong thing without knowing this?"

## Known pending (production hardening)
- **Firestore rules**: sensitive collections (credentials, auth_sessions, operator_pins,
  OTPs, licenses, global) are already server-only (`if false`). Business data
  (companies/** : customers, weighments, materials, etc.) is still `allow … : if true` —
  no company isolation because the client uses **anonymous** Firebase Auth (token carries
  no companyId). Real fix = mint a Firebase **custom token with a companyId claim** at
  login, switch the client off anonymous, scope company rules to that claim. Required
  before onboarding a 2nd company. See memory `production-readiness`.
- Windows code signing: **postponed** (planned, just not now) — macOS notarization is already in CI.
