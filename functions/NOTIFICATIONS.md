# In-app notification engine

Every notification event also writes a **free, uncapped** in-app entry, surfaced
in the app's notification center (`/notifications`) and the shell bell/popup.

```
event (index.js)
   └─ notifyContact({ companyId, notif, sms, critical })
        ├─ _writeInApp(...)        ← in-app entry FIRST (free, never gated)
        ├─ email  (capped unless critical)
        └─ sms    (capped unless critical)
```

## Document schema — `companies/{c}/notifications/{id}`
| field | meaning |
|---|---|
| `title`, `body` | from `notif.heading` / `notif.intro` |
| `category` | security · billing · licence · operator · kyc · backup · account · welcome · system |
| `severity` | info · warn · critical (derived from `notif.accent`) |
| `link` | in-app route to deep-link to on tap (e.g. `/settings/mfa`) |
| `operatorEmail` | **`"*"` = company-wide** (default); a specific email = personal, only that user sees it |
| `type` | mirrors `category` (back-compat with the old UI) |
| `read`, `createdAt` | unread flag + server timestamp |

## Per-operator targeting
The feed is shared per company, so personal notices are addressed with
`operatorEmail`. The client filters with `operatorEmail in ["*", myEmail]`.

- **Personal (operatorEmail = the person):** password-changed, MFA on/off,
  contact-changed, KYC result, operator-deactivated, operator-invite welcome,
  company welcome.
- **Company-wide (`"*"`):** security/gate alerts, licence activated/expiring/
  expired, billing (90% + limit-reached), weighbridge-limit, address-grace,
  backup-failed.

To add a personal notification, set `operatorEmail` inside the `notif` object.

**Shared-state note:** `read` and deletion act on the shared doc, so for a
company-wide (`"*"`) item the first reader marks it read for everyone, and the
client disables swipe-delete on `"*"` items (only personal items are deletable),
so one operator can't destroy a shared alert. `markAllNotificationsRead` is
audience-scoped — it never touches another operator's personal docs. Per-user
read state on shared items would need a `readBy` array (not done).

## Cost-cap interaction
In-app is **always written** (free). Critical events (`critical: true`) also send
email/SMS uncapped; discretionary events' email/SMS are capped, but the in-app
entry is unaffected — so the notification center never loses an event.

## SMS (FAST2SMS) — deliberately lean
SMS costs per message and each template needs its own DLT registration, so SMS is
reserved for messages that must reach someone **off-screen / out-of-band**.
Everything else (welcome, licence, KYC, operator lifecycle, **account-security**
password/2FA/contact changes, backup, quota) is **email + in-app only**.

**Templates to register in FAST2SMS** (env var → text):
| env var | route | text |
|---|---|---|
| `FAST2SMS_OTP_ID` | OTP (`/dev/otp/send`) | `Tulanam: {#var#} is your verification code. Valid for 10 minutes. Do not share it with anyone.` |
| `FAST2SMS_TPL_SECURITY_ALERT` | DLT bulk | `Tulanam security alert: {#var#}. Please review your account now. - Tulanam` |
| `FAST2SMS_TPL_GATE_ALERT` | DLT bulk | `Tulanam gate alert: {#var#}. Please check the gate control system. - Tulanam` |
| `FAST2SMS_TPL_ADDRESS_GRACE` | DLT bulk | `Tulanam: Verify your business address within {#var#} days to keep your account active. Use the code in the letter we mailed. - Tulanam` |
| `FAST2SMS_TPL_WEIGHMENT_RECEIPT` | DLT bulk | `Tulanam: Weighment {#var#} for vehicle {#var#} is recorded. Net weight {#var#} kg. - Tulanam` |
| `FAST2SMS_TPL_DAILY_DIGEST` | DLT bulk | `Tulanam: Daily summary — {#var#} weighments, {#var#} tonnes recorded. - Tulanam` |

`dailyDigest` is sent only when the owner opts in. **Removed from SMS** (now email +
in-app): passwordChanged, mfaChanged, contactChanged, licenseExpiry, licenseExpired,
operatorInvite, welcome, licenseActivated, operatorDeactivated, kycResult,
backupFailed, quotaReached.

## Client-side notifications (`lib/shared/services/app_notifier.dart`)
The client raises notifications for failures the server can't see. `AppNotifier`
writes the same schema and **throttles per key** (default 15 min) so a flapping
device can't flood the center. Use `raise(paths, …)` or `raiseCompany(companyId, …)`.
Wired:
- **Weighbridge scale disconnected/error** (`scaleAlertProvider`, re-arms on reconnect)
- **Receipt print failed** (weighment_screen print sites — was fire-and-forget)
- **Offline sync failed** (`offline_queue_service.flush`, 30-min throttle)
- **Integration push failed** (Sheets/billing/WhatsApp/sticker — `post_weighment_service`)
- **Deactivated / off-shift sign-in attempt** (`face_verification_notifier`)
- **Gate interlock trip** (`gate_automation_provider`, 1-hour throttle)

Cloud-backup failure is already handled server-side (`notifyBackupResult`), so the
client doesn't double-notify it.

## Server events added (account/security gaps)
operatorArchived, forcePasswordReset, checkPasswordExpiry, updateOperatorEmail
(old+new), operatorRejected (domain-restricted), deactivateInactiveOperators
(admin summary), unregistered-RFID-at-gate (throttled via the alert cooldown),
**operatorDeleted** (new `onOperatorDeleted` trigger — also deletes the orphaned
Firebase Auth account), **operatorRoleChanged** (privilege change → operator).
Blacklisted-vehicle was already wired.

## Config-change notifications (client, audit #3)
- **Integration enable/disable** (`integrations_screen`)
- **Security settings changed** incl. IP allow-list (`security_screen._save`); the
  server still sends the *critical-disable* alerts separately
- **Email-domain restriction changed** (`security_screen._saveDomainRestriction`)
- **Company details changed** — field-level GSTIN/PAN/address diff (`general_settings_screen`)
- **Data restored from backup** (warn — destructive) + **data/settings exported** (info) (`data_backup_screen`)

`onOperatorDeleted` deletes the orphaned Firebase Auth account. Verified safe: the
only two operator-doc deletes (`operators_screen.dart:1593,1767`) are genuine
terminal removals (reject + "delete permanently"), never a move/re-parent.

## Fraud / hardware / compliance (round 3)
- **Manual weight entry** (bypasses live scale — fraud signal) · **post-completion
  weighment reassignment** · **CCTV snapshot capture failed** (no receipt evidence)
- **Vehicle blacklist / un-blacklist** toggle (`onVehicleUpdated` trigger)
- **GSTIN verified** (`verifyGstinOwnership`) · **face-enrollment upload failed**
  (was silently returning success)
- **Scheduled report send failure** — the rendered send is now guarded so one
  failure no longer aborts every other company's report; falls back to plain mail
  and notifies the admin
- **Customer bulk-import** failure/summary (the commit loop was unguarded — could crash)

**Gate fault** (`gateAlertProvider`, symmetric to the scale alert) — a gate that
reports `GateState.error` (didn't actuate) raises a throttled notification.

**Deliberately not notified:** routine operational events (weighment completed,
gate cycles, customer/material CRUD) stay surfaced via UI/audit only.
Also skipped, with reason:
**continuous camera/CCTV offline** (no camera health-stream exists — would need new
infra; the snapshot-capture-failed alert already covers the practical impact),
**AI-sidecar health** (already shown live in the weighment status chip),
material/printing/custom-field config edits, on-demand report failure (error shown
to caller), site/weighbridge delete — **overload / credit-limit / Udyam** (no data model exists),
**void-weighment** (no execution path — permission-only), **AI-sidecar offline**
(a null result is indistinguishable from "no match" + auto-retries, so alerting
risks false positives; cloud fallback keeps auth working), **Aadhaar/DigiLocker
completion** (runs pre-account during onboarding — no stable company/admin target),
**reprint / forced-logout** (audit log already suffices).

**De-duplication:** archiving an operator sets both `isArchived` and `isActive:false`,
firing two triggers — the deactivate notice is suppressed when `after.isArchived`
so only the single archive notice is sent.

## Lifecycle
`cleanupNotifications` (scheduled, daily, IST) deletes **read > 30 days** and
**unread > 90 days** per company.

## ⚠️ Deploy requirements
1. **Indexes** — `firestore deploy --only firestore:indexes`. Three composite
   `notifications` indexes are needed:
   - `(read ASC, createdAt DESC)` — cleanup query
   - `(operatorEmail ASC, createdAt DESC)` — full feed
   - `(read ASC, operatorEmail ASC, createdAt DESC)` — unread feed
   Without them the feed/cleanup queries throw `failed-precondition`.
2. **Migration** — notifications written **before** this change have no
   `operatorEmail` field, so the `in ["*", …]` filter won't return them (they
   silently drop from the feed). New entries are unaffected. Backfill
   `operatorEmail: "*"` on old docs if their history must remain visible.
3. **Rules** — `companies/{c}/notifications` is already client read/write (so the
   app can mark-read and dismiss). The `usage/{period}` counters remain
   server-write-only.
