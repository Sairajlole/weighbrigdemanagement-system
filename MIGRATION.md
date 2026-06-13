# Migrating to a new Firebase project (Tulanam)

Moving everything from `weighbridge-management` to a brand-new Tulanam-owned
project. This is a **hard cutover with downtime** — do it in a maintenance window,
keep the old project until the new one is verified, and **back up first**.

Throughout, replace `<NEW>` with your new project ID (e.g. `tulanam-prod`).
Old project ID: `weighbridge-management`.  Old bucket: `weighbridge-management.firebasestorage.app`.

> ⚠️ Project IDs are permanent. Pick `<NEW>` carefully — you can't rename it later.

---

## Phase 0 — Back up the OLD project (do this even if you change nothing)
```bash
firebase use weighbridge-management
# Firestore -> a Storage bucket in the OLD project
gcloud firestore export gs://weighbridge-management.firebasestorage.app/backup-$(date +%F) --project weighbridge-management
# Storage files -> local (or another bucket)
gcloud storage cp -r gs://weighbridge-management.firebasestorage.app ./storage-backup
# Auth users (preserves UIDs + password hashes)
firebase auth:export users-backup.json --project weighbridge-management
```
Keep these. They are your rollback.

---

## Phase 1 — Create the new project (on the Tulanam account)
1. Sign in to the Firebase console **as your Tulanam Google account**.
2. **Add project** → name "Tulanam" → note the generated project ID; set it to `<NEW>` if available.
3. Enable, matching the old project's settings:
   - **Firestore** (same region as old — check old project's region first; it's immutable too).
   - **Authentication** → enable **Anonymous** + **Email/Password** providers.
   - **Storage** (creates the `<NEW>.firebasestorage.app` bucket).
   - **Functions** (requires Blaze/billing on the new project).
4. Register the platform apps (or let `flutterfire configure` do it in Phase 3): macOS, iOS, Android, Windows/Web as used.

---

## Phase 2 — Migrate the data
```bash
# Firestore: import the OLD export into the NEW project.
# The export must live in a bucket the NEW project can read — copy it over first:
gcloud storage cp -r gs://weighbridge-management.firebasestorage.app/backup-<DATE> gs://<NEW>.firebasestorage.app/import/
gcloud firestore import gs://<NEW>.firebasestorage.app/import/backup-<DATE> --project <NEW>

# Storage files: copy the whole bucket.
gcloud storage cp -r gs://weighbridge-management.firebasestorage.app/* gs://<NEW>.firebasestorage.app/

# Auth users: import (KEEPS UIDs — critical, operator docs reference uid).
#   Match the password hash params from the export header if prompted.
firebase auth:import users-backup.json --project <NEW>
```
**Verify in the new console:** collections present (`companies`, `operators`,
`credentials`, …), Storage files there, Auth users listed with the same UIDs.

---

## Phase 3 — Regenerate the app's Firebase config (automated)
`flutterfire` rewrites the generated config files for you (don't hand-edit these):
```bash
flutterfire configure --project=<NEW>
```
This regenerates: `lib/firebase_options.dart`, `macos/Runner/GoogleService-Info.plist`,
`ios/Runner/GoogleService-Info.plist`, `android/app/google-services.json`, and the
`flutter` block in `firebase.json`.

---

## Phase 4 — Update the hardcoded references (I'll do this for you)
`flutterfire` does NOT touch these — they have `weighbridge-management` baked in:
`lib/shared/services/cloud_functions_service.dart`, `functions/email_render.js`,
`functions/index.js`, `functions/release_publish.js`, `tool/publish_release.js`,
`.github/workflows/release.yml`, and the seed scripts.

Run (after Phase 3, so it doesn't fight flutterfire):
```bash
tool/rename_project.sh <NEW>        # find-replaces the bucket + project id in code
```
(Provided once you give me `<NEW>` — see the bottom.)

---

## Phase 5 — Functions: secrets, deploy, IAM (on the NEW project)
1. Recreate `functions/.env` values on the new project (these don't migrate):
   `MFA_ENC_KEY`, `RENDER_SECRET`, `RENDER_URL` (→ new project), `LICENSE_ADMIN_SECRET`,
   `GMAIL_EMAIL`/SMTP creds, `FAST2SMS_*`, `MEON_*`, `ERROR_DIGEST_TO`, etc.
2. Point the CLI at the new project and deploy:
   ```bash
   firebase use <NEW>
   firebase deploy --only firestore:rules,firestore:indexes,functions,storage
   ```
3. Re-apply the renderEmailDoc public access (it's a public Cloud Run service):
   ```bash
   gcloud run services add-iam-policy-binding renderemaildoc --region=us-central1 \
     --member=allUsers --role=roles/run.invoker --project <NEW>
   # and the compute SA token-creator-on-itself for signed URLs (as before)
   ```
4. Set `RENDER_URL` in `.env` to the NEW project's renderEmailDoc URL and redeploy.

---

## Phase 6 — Test the new project END TO END (before any cutover)
On a test machine with the Phase-3/4 build pointed at `<NEW>`:
- Log in (existing credentials — they migrated), do a weighment, print, send a report
  email, trigger a gate, change an operator PIN, run Check-for-updates.
- Confirm `error_reports`, notifications, and DigiLocker/SMS still work.
**Do not cut over until this passes.**

---

## Phase 7 — Cutover (the clever, low-pain part)
The installed apps still point at the OLD project. Use the OLD project's auto-update
to push the NEW-project app one last time:
1. **Freeze:** pick an off-hours window; tell operators to stop weighing.
2. **Final data sync:** re-run the Phase-2 Firestore import (delta) so anything written
   since the first import is captured. (Or keep the freeze tight enough that there's nothing.)
3. **Build the NEW-project app** (Phase 3/4 done) and publish it **through the OLD
   project's release flow** (`tool/release.sh` against the OLD project / its feed).
4. Every PC auto-updates → relaunches → now runs the NEW-project build → talks to `<NEW>`.
5. Confirm a few PCs are on the new project (login works, data shows).

After this, all future releases go through the NEW project's flow.

---

## Phase 8 — Decommission
- Keep `weighbridge-management` **read-only/idle for ~2 weeks** as a safety net.
- Once confident: remove billing, then delete it.
- Move the Tulanam app's domains/keys (Meon, FAST2SMS sender, Gmail/SMTP) to point at
  the new project where relevant.

---

## Rollback
At any point before Phase 7 completes, do nothing to the old project — the installed
apps still use it, fully intact. If Phase 7 goes wrong, push the OLD-project app back
through the (still-OLD) feed. After decommissioning, rollback = the Phase-0 backups.

## Gotchas
- **Region is immutable** on the new project too — match the old one.
- **Auth UIDs must be preserved** (Phase 2) or operator/session links break.
- **`.env` secrets don't migrate** — recreate them (Phase 5).
- **renderEmailDoc** is a separate public Cloud Run service — its IAM must be redone (Phase 5).
- The **6 SMS DLT templates / Meon KYC** are tied to your sender identity, not the project —
  they keep working, but update any project-specific webhook URLs.
</content>
