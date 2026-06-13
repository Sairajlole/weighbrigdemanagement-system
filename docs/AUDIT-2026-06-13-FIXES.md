# Audit Fix Batch — Release Verification (2026-06-13)

**Summary:** 22 units processed against the 2026-06-13 audit. Compile gates are green — `flutter analyze lib` reports **0 errors** (202 issues total: 123 warnings, 79 info — all pre-existing/out-of-scope) and `node --check functions/index.js` **passes**. However, the batch is **NOT shippable as-is**: two units are **BROKEN** by verifier ground truth — `rules` (deploying the current `firestore.rules` causes an app-wide lockout) and `offline` (silent weighment + audit-log data loss after ~3.3 min offline). One additional **release precondition** exists: the rotated `MFA_ENC_KEY` will lock out any pre-existing MFA-enrolled user at login. The working tree is also far larger than the documented fixes (77 files / ~9.8k lines) and commingles unrelated in-flight feature WIP that cannot be cleanly git-isolated from the audit fixes.

> **Verdict source:** The table and notes below use the **verifier's review verdict** (`reviewVerdict` / `issues`), not the fix-agent self-report, wherever the two conflict. The release verifier reports ground truth.

---

## Unit results

| Unit | Files | Verdict | Compile | # changes | Skipped |
|---|---|---|---|---|---|
| functions | `functions/index.js` | minor-issues | clean | 13 | 2 |
| **rules** | `firestore.rules` | **BROKEN** | not-run | 2 *(reported; NOT present in file)* | 2 |
| print | `lib/shared/services/print_service.dart` | good | clean | 2 | 0 |
| **offline** | `offline_queue_service.dart`, `post_weighment_service.dart` *(+ `offline_provider.dart`)* | **BROKEN** | clean | 4 | 0 |
| login | `lib/features/setup/presentation/steps/welcome_step.dart` | minor-issues | clean | 2 | 0 |
| cache | `local_cache_service.dart`, `cloud_functions_service.dart`, `main.dart` | minor-issues | clean | 0 *(skip-only)* | 2 |
| operators | `lib/features/operators/presentation/operators_screen.dart` | minor-issues | clean | 5 | 0 |
| customers | `lib/features/customers/presentation/customers_screen.dart` | minor-issues | clean | 5 | 1 |
| reports | `lib/features/reports/presentation/reports_screen.dart` | good | clean | 5 | 0 |
| weighments | `lib/features/weighments/presentation/weighments_screen.dart` | minor-issues | clean | 3 | 0 |
| dashboard | `lib/features/dashboard/presentation/dashboard_screen.dart` | good | clean | 1 | 1 |
| profile | `lib/features/profile/presentation/profile_screen.dart` | minor-issues | clean | 2 | 1 |
| settings-general | `lib/features/settings/presentation/general_settings_screen.dart` | minor-issues | clean | 1 | 0 |
| settings-scope | `materials_screen.dart`, `custom_fields_screen.dart` | minor-issues | clean | 2 | 0 |
| security-screen | `lib/features/settings/presentation/security_screen.dart` | minor-issues | clean | 2 | 0 |
| backup | `data_backup_screen.dart`, `cloud_backup_service.dart` | minor-issues | clean | 4 | 1 |
| scale-display | `scale_service.dart`, `display_board_service.dart` | good | clean | 2 | 0 |
| sidecar | `ai_sidecar_client.dart`, `face_frames_dialog.dart` | minor-issues | clean | 5 | 2 |
| cameras | `weighbridge_cameras_column.dart`, `multi_camera_service.dart` | minor-issues | clean | 5 | 0 |
| secprov | `lib/shared/providers/security_provider.dart` | good | clean | 1 | 1 |
| faceflow | `face_enroll_step.dart`, `face_verification_notifier.dart`, `license_step.dart`, `review_step.dart` | minor-issues | clean | 4 | 0 |
| form | `vehicle_info_form.dart`, `printing_screen.dart`, `integrations_screen.dart` | minor-issues | clean | 3 | 0 |
| misc | `version_provider.dart`, `voice_guidance_service.dart`, `identity_cameras.dart`, `company_info_step.dart`, `settings_scope_provider.dart`, `account_step.dart`, `tally_service.dart` | good | clean | 8 | 2 |
| deadfiles-lints | `identity_step.dart`, `site_setup_screen.dart`, `camera_carousel.dart`, `camera_feeds_panel.dart`, `analysis_options.yaml` | good | clean | 5 | 0 |

**Verdict legend:** good = fixes verified correct/complete · minor-issues = fixes correct but with non-blocking gaps or undisclosed commingled edits · **BROKEN = deliverable does not match report and/or introduces a blocking regression.**

---

## Applied changes (file · finding · what)

### functions — `functions/index.js`
- **[HIGH] Session tokens survive deletion/deactivation/role-demotion (revocation bypass).** Added `_revokeSessionsForEmail(email)` (deletes all `auth_sessions` for an account); wired into `onOperatorDeleted` and the deactivate/archive/role-change branches of `onOperatorUpdated`. `_requireSession` now reloads the LIVE operator/company doc via `_liveAccountState()` and re-checks `isDeleted/isArchived/isActive` + current role on every guarded call (fail-open only on a transient lookup error). `_requireAdminSession` inherits the live role.
- **[HIGH] Password-only MFA re-enrollment takeover.** Added `_verifyCurrentMfaFactor(cred, code)`; `mfaBeginEnroll`/`mfaConfirmEnroll` now require `data.currentCode` to pass when `cred.mfaEnabled===true`, else throw failed-precondition. First-time enrollment unaffected.
- **[MED] `loginUser` no rate-limit on password attempts.** Per-account throttle on the account doc: check `loginLockUntil`; increment `loginFailCount` and set a 15-min lock after 5 fails; clear both on success.
- **[RACE] `loginUser` non-atomic one-time backup-code consume (double-spend).** Rewrote the TOTP/backup branch: consume the backup code inside `db.runTransaction` (re-read, re-find, filter), mirroring `verifyMfaCode`.
- **[MED]/[LOW] `mfaDisable` no throttle + stale state.** Added the `mfaLockUntil`/`mfaFailCount` throttle; on success also delete `mfaBackupCodes`, `mfaPendingAt`, `mfaFailCount`, `mfaLockUntil`.
- **[MED] `sendPasswordResetOTP` leaks account existence + phone last-4.** Track `accountFound`; on no match skip all OTP work and return a single CONSTANT_RESPONSE. Removed `maskedPhone`/`phoneSent` from the response.
- **[MED] `sendReportEmail` mails to any client-supplied recipient.** Added email-regex/length validation + allowlist `_isCompanyReportRecipient(...)` (company contact, an operator of the company, or the signed-in caller). Body uses the session email.
- **[LOW] `generateOTP` used `Math.random()`.** Replaced with `require('crypto').randomInt(...)`.
- **[MED] Failed-login alert not actually consecutive + re-spams in-app channel.** Detect TRUE consecutive failures via two queries that fit the EXISTING auditLog index; per-user 15-min cooldown via a transactional `login_alert_state` doc, deleted on success. No new composite index.
- **[LOW] `_mintSessionToken` non-atomic prior-session invalidation.** Wrapped prior-session delete + new-token create in one `db.runTransaction`.
- **[LOW] `updateCompanyContact` wrote to `audit_log` (trigger fires on `auditLog`).** Changed the write target to `auditLog` (canonical).
- **[MED] Inverted admin check on `bulkUpdateShifts`/`forcePasswordReset`/`registerRfidTag`.** Replaced dead `context.auth.token.admin` claim check with `await _requireAdminSession(data, companyId)`; captured admin session email for audit-log `user` fields.

### rules — `firestore.rules` — ⚠️ REPORTED BUT **NOT PRESENT IN THE WORKING FILE**
- **[CRITICAL] `operatorUpdateSafe()` does not block `passwordHash` (auth bypass).** *Reported:* appended `passwordHash`, `emailVerified`, `hasPin` to the blocklist. **Verifier: ABSENT.** The actual blocklist is `['role','pinHash','activeSessionId','uid','isAdmin','isCompanyAdmin','mfaRequired']` — none of the three are present. The prescribed fix is not in the deliverable.
- **[MED] `notifications write: if true` (cross-tenant inject/tamper).** *Reported:* decomposed into `create:if false` + `update hasOnly(['read'])` + `delete:if true`. **Verifier: ABSENT.** The working file has `notifications: allow read, write: if belongs(companyId)` (company-scoped) and `if false` for the legacy-flat block.
- **Root cause:** the working `firestore.rules` is **byte-identical to the staging multi-tenant `belongs(companyId)` rewrite** (the file's own header lines 1-8 say STAGING / NOT DEPLOYED / first deploy failed permission-denied). See the BLOCKING section.

### print — `lib/shared/services/print_service.dart`
- **[HIGH] PowerShell command injection via printer name.** Added `_psSingleQuote(String)` (strips U+2018–U+201B smart quotes, doubles ASCII single-quote, wraps in `'...'`). Rewired all three interpolation sites (`_sendBinaryRawToLpr`, `_sendPdfToLpr`, `_tryBackupPrinter`). Default-printer (Get-CimInstance) branch already safe.
- **[info] Placeholder re-substitution.** `_substitutePlaceholders` now does a single-pass alternation `RegExp` (keys longest-first, `RegExp.escape`d) via `replaceAllMapped`, so a substituted value can't be re-matched as another token.

### offline — `offline_queue_service.dart`, `post_weighment_service.dart` (+ `offline_provider.dart`)
- **[HIGH] Integration-retry payloads queued as weighments create phantom duplicates.** Added dedicated `sheets_retry`/`billing_retry` queue types with `enqueueSheetsRetry`/`enqueueBillingRetry` + `_flushSheetsRetries`/`_flushBillingRetries` that replay the real integration (`GoogleSheetsService.appendRow` / `BillingService.postWeighment`) and never call `weighments.add`. `_flushWeighments` defensively re-routes legacy `_retryType`-tagged files (stripping the tag first). *(This part verified correct.)*
- **[HIGH] Producers tag payloads with `_retryType` through `enqueueWeighment`.** `post_weighment_service.dart`: all four producer calls replaced with `enqueueSheetsRetry`/`enqueueBillingRetry`. *(Verified correct.)*
- **Required wiring (`offline_provider.dart`, outside owned files):** wired `sheets`/`billing` services into the flushing `OfflineQueueService` so replays actually re-call the integration (without it, retries would be silently dropped). *(Verified required and present.)*
- **[LOW] ⚠️ Poison-record cap / dead-letter — INTRODUCES A BLOCKING REGRESSION.** Added `_recordFailure(File)` bumping a `_attempts` counter and moving files to `dead_letter` after `_maxAttempts` (20). **Verifier: this was wired into EVERY flush handler's network-failure catch — including `_flushWeighments` and `_flushAuditLogs` — not just the integration-retry queues.** See the BLOCKING section.

### login — `lib/features/setup/presentation/steps/welcome_step.dart`
- **[HIGH] Windows login bypasses TOTP 2FA + single-session (`loginUser` never called).** Inserted the authoritative `loginUserWithMfa(context, email, password, getCode: _inlineGetCode)` block into `_submitWindows` (after the Firebase Auth sign-in + FirebaseAuthException gate + `if (!mounted) return`, before company/operator resolution). Fails closed (signOut + invalid-credentials error) on any failure. *(Verified correct.)*
- **[MED] AUTH_DIAG writes uid + claims to `error_reports` on every login.** Outcome satisfied — no `error_reports`/`AUTH_DIAG` write ships. *(Note: verifier could not evidence a deletion hunk; HEAD never contained it. Security outcome met.)*

### operators — `lib/features/operators/presentation/operators_screen.dart`
- **[MED] Firebase Auth email-update failure swallowed → Auth/Firestore divergence.** `_verifyAndApplyChange` now sets `emailAuthFailed` on a real attempted-and-failed Auth update; the Firestore write parks the value in `pendingEmail` (not `email`) and shows a warning toast. Uid-less custom-auth operators still write `email` normally. *(See SKIPPED/flagged: `pendingEmail` is write-only.)*
- **[MED] setState after await in contact-change apply (disposed `_phoneCtrl`).** Added `if (!mounted) return;` before the success setState and `if (mounted)` around the catch/finally setStates.
- **[MED] Unguarded setState after awaits in `_FaceEnrollmentWidget._validatePhase`.** Added `if (!mounted) return;` after `enrollFromImages` and `validateFaceConsistency` and at the top of both catch blocks.
- **[LOW] Restore-from-archive re-activates while wiping KYC (active+verified, no ID).** Added `'isVerified': false` to the restore update map.
- **[LOW] Reject-dialog `customCtrl` never disposed.** Appended `.whenComplete(customCtrl.dispose)`.

### customers — `lib/features/customers/presentation/customers_screen.dart`
- **[MED] Merge reassigns weighments by `customerName` only (cross-site name collision).** `_performMerge` adds an in-memory phone-disambiguation filter (reassign only when other's phone empty, doc's phone empty, or they match). *(Schema note: weighments carry no `customerId`/`siteId`; site scoping is structural via the path. Phone disambiguation is the feasible faithful fix.)*
- **[data-loss] Rename path reassigned by name only.** Same phone filter applied to the rename cascade (`_saveChanges`).
- **[LOW] Reverification controller (`passC`) leaked + post-await setState missing mounted.** `try/finally` + dispose `passC`; `if (verified == true && mounted) onVerified()`.
- **[LOW] Add-customer phone uniqueness global, inconsistent with per-site reads.** Single-field `where('phone')` query + in-Dart `siteId` filter (avoids composite index) in `_save` and `_saveChanges`.
- **[MED] Per-row O(weighments) double full-scan (quadratic).** Added `_PeriodAgg` + `_buildPeriodAggregate(...)` single-pass aggregation; `_buildPeriodCell` is now O(1).

### reports — `lib/features/reports/presentation/reports_screen.dart`
- **[MED] CSV `_esc` allows formula injection + embedded-newline row breaking.** Prefix `'` when field starts with `= + - @`; quoting now also fires on `\n`/`\r`.
- **[MED] Loaded previous-period data goes stale on date-range change.** Added `_prevData = []` to both `_dateRange`-mutating setState blocks (preset + custom picker).
- **[MED] PDF/print export truncates rows while header reports full count.** PDF header appends `(showing first 200)` when >200; print header `(showing first 500)` when >500. Caps and totals unchanged.
- **[LOW] Customer/vehicle filter ignored for 1-2 char inputs.** Hints changed to `Customer (3+)...` / `Vehicle (3+)...` to make the existing 3-char guard honest.
- **[LOW] Audit tab builds Firestore `.get()` inline in `build()`.** Cached into `Future<QuerySnapshot>? _auditFuture` via `??=`.

### weighments — `lib/features/weighments/presentation/weighments_screen.dart`
- **[unbounded stream] Weighments list streams entire collection.** Pushed `createdAt` range + `.limit(1000)` + `orderBy(createdAt desc)` server-side via a file-local `_dateRangeProvider` (single-field, no composite index). Bounding only — not load-more pagination (out of surgical scope).
- **[N+1] All-weighbridges view does sequential unbounded reads.** Replaced nested loops with `Future.wait` fan-out, each per-bridge read bounded by the same range+limit. `collectionGroup` deliberately avoided (weighment docs carry no tenant fields → would be cross-tenant).
- **[platform] Save/Share PDF reveal macOS-only, unhandled `ProcessException`.** Per-platform branch (macOS `open -R` / Windows `explorer /select` / Linux `xdg-open`) wrapped in try/catch; success message now platform-correct.

### dashboard — `lib/features/dashboard/presentation/dashboard_screen.dart`
- **[platform-divergence] Concurrent-stream workaround Windows-only here vs Windows‖Linux in app_shell.** Changed both deferral guards from `if (Platform.isWindows)` to `if (Platform.isWindows || Platform.isLinux)` + comment update, matching `app_shell.dart:42`.

### profile — `lib/features/profile/presentation/profile_screen.dart`
- **[MED]/[LOW] Cooldown/OTP-resend Timer fires setState on unmounted StatefulBuilder when barrier-dismissed.** Appended `.whenComplete(() => cooldownTimer?.cancel())` to the change-password `showDialog` future (covers barrier-tap + back/escape; StatefulBuilder has no `mounted`).
- **[LOW] `HttpClient` leaked on `_getPublicIp` failure path (retried every 30s).** Hoisted `HttpClient? client;` and close in `finally { client?.close(); }`.

### settings-general — `lib/features/settings/presentation/general_settings_screen.dart`
- **[MED] Cross-Site Customers toggle never persisted yet snapshot marks it saved.** Added `'crossSiteCustomers': _crossSiteCustomers,` to the `db.generalSettings.set({...})` payload in `_save()`.

### settings-scope — `materials_screen.dart`, `custom_fields_screen.dart`
- **[MED] Scope change copies source docs into destination without cleanup (ghost/duplicate entries).** `_changeMaterialsScope` now queries the destination collection and batch-deletes existing dest docs before the copy loop (delete-then-set in one batch). *(See SKIPPED note re: 2x batch op count.)*
- **[LOW/race] Scope change doesn't cancel pending autosave debounce.** `_changeScope` adds `_saveDebounce?.cancel();` after the no-op guard and before the dialog `await`. *(See SKIPPED/flagged: this can discard the most recent unsaved edit — flush-then-read would be the data-preserving fix.)*

### security-screen — `lib/features/settings/presentation/security_screen.dart`
- **[MED] Inline `TextEditingController` for audit-retention leaks + resets cursor.** Promoted to state field `_auditRetentionController`; seeded in initState; disposed; re-synced from async-loaded value via `addPostFrameCallback` in `_loadData`.
- **[MED] Unguarded `WidgetRef` after save await; failed save flips in-memory override.** Added `if (!mounted) return;` after `await _saveLocally(data)`; moved the override set + `ref.invalidate` into the success branch only.

### backup — `data_backup_screen.dart`, `cloud_backup_service.dart`
- **[MED] "Force Sync" reports success + zeroes pending without flushing the real queue.** `_forceSync()` now calls `offlineQueueProvider.flush()`, then drives UI from `queue.pendingCount` / `queue.lastSyncSuccess`; two `if (!mounted) return;` guards; error toast with remaining-pending count.
- **[MED] Company restore silently merge-overwrites despite "Ask before overwriting" UI.** Corrected the label to `Restore merges & overwrites existing records` (no stored toggle exists; full conflict-prompt is a feature build).
- **[LOW] Backup manifest `weighbridgeCount` hard-coded to 0 by a no-op fold.** Added a real accumulator over the sites loop.
- **[MED] GDrive upload sets `parents` to a folder NAME not an ID.** Added `_resolveGDriveFolderId(...)` (Drive `files.list` → ID, `files.create` if absent, null on failure); threaded into `_gdriveUpload(..., folderId)` (uploads to root on null); re-resolved after 401 refresh; `HttpClient` closed in finally.

### scale-display — `scale_service.dart`, `display_board_service.dart`
- **[LOW] Weight regex without capture group silently drops every reading (RangeError swallowed).** Guarded `groupCount` before `group(1)`: `(match.groupCount >= 1 ? match.group(1) : null) ?? match.group(0)`. Surfaced parse failures via `_lastError`. Connection state machine untouched.
- **[LOW/MED] Modbus RTU CRC computed over wrong byte range (every frame malformed).** CRC now computed over the full frame body `[0x01, 0x06, ...payload]`; `_crc16` byte order unchanged.

### sidecar — `ai_sidecar_client.dart`, `face_frames_dialog.dart`
- **[url] Unencoded query params in `identifyFace` / `submitAnprCorrection` / `submitAnprFrame`.** Replaced string interpolation with `Uri.parse(...).replace(queryParameters: {...})`; `sessionId` kept as a path segment.
- **[type] `enrollFromImages` strict `.cast<double>()` defers TypeError.** Changed to `.map((e) => (e as num).toDouble()).toList()` matching sibling parsers.
- **[state] Re-enroll syncs `is_active:true` hardcoded (re-activates deactivated operator in FAISS).** Reads the operator doc and passes the real `isActive` boolean to `syncEnrollments`. *(Used `isActive` over the audit's literal `status=="active"` — operator docs carry no `status` field.)*

### cameras — `weighbridge_cameras_column.dart`, `multi_camera_service.dart`
- **[platform] macOS-only `multi_camera` MethodChannel invoked unguarded.** Wrapped `listDevices()` in try/catch returning `[]` (MissingPluginException → empty list on Windows/Linux).
- **[race/arch] `dispose()` calls global `stopAll()` killing other widgets' sessions.** Replaced with a per-key `MultiCameraService.stop(key)` loop over the widget-owned `_activeNativeKeys`; IP feeds left to the global provider.
- **[lifecycle] Snapshot timer touches ref/files with no mounted guard.** Added `_capturing` field + early return on `!mounted || _capturing` + try/finally + `if (!mounted) return;` after each await.
- **[race] Concurrent JPEG path write if capture stalls >3s.** Same `_capturing` in-flight guard prevents overlapping writes to `live_<key>.jpg`.
- **[correctness] Unguarded `base64Decode`/`int.parse` of sidecar data red-screens panel.** Added `_tryDecodeBase64` + try/catch around `int.parse('FF$hex',...)`; decode-to-local + null-gated render for plate crop and face snapshot.

### secprov — `lib/shared/providers/security_provider.dart`
- **[MED] `restrictUsb` inert on non-macOS yet toggle shown on Windows (false security).** Added `bool get supported => Platform.isMacOS;` to `UsbMonitorService`; refactored the two platform guards to consume it; exposed `usbMonitorProvider.supported` for the UI to gate. *(See SKIPPED: UI toggle gating in unowned `security_screen.dart`.)*

### faceflow — `face_enroll_step.dart`, `face_verification_notifier.dart`, `license_step.dart`, `review_step.dart`
- **[lifecycle] setState after `validateFaceConsistency` await, no mounted guard.** Added `if (!mounted) return;` after the await and at the top of both catch blocks.
- **[lifecycle] StateNotifier mutates state after autoDispose.family disposed (post-delay reset).** Added `if (!mounted) return;` after EVERY `await Future.delayed` before the subsequent `state =` (8 sites incl. the two `_handleMatch` sites outside the cited range). *(Residual: the pre-await cloud call gap is still unguarded — pre-existing, partially closed.)*
- **[lifecycle] `license_step.dart` setState after activation awaits (file had zero mounted refs).** `_save()` returns `Future<bool>`, so `if (!mounted) return false;` after `db.get()` and after each license-activation await. No activation bypass.
- **[lifecycle] `review_step.dart` submit catch / early-branch setState not all guarded.** `_completeOperator` catch: `if (!mounted) return;` before setState (removed redundant inner `if (mounted)`). `_completeSetup`: guard now precedes the `sessionLoggedInProvider` mutation + `context.go` (previously the provider mutation ran unguarded).

### form — `vehicle_info_form.dart`, `printing_screen.dart`, `integrations_screen.dart`
- **[leak] `addListener` inside Autocomplete `fieldViewBuilder` accumulates a focus listener every rebuild.** Added `_customerFocusNode` field + named `_onCustomerFocusChange()`; attach once guarded by `!identical(...)`; removeListener in dispose.
- **[leak/cursor] ⚠️ Inline `TextEditingController` in `_buildNumberInput`/`_buildDoubleInput` build helpers.** Keyed `_numberInputCtrls` map via `putIfAbsent` (created once, never re-seeded from `value`); 12 call sites given unique `fieldKey`s; disposed/cleared at scope-switch + Cancel. *(See SKIPPED/flagged: introduces a stale-display regression on the Cut-Length dropdown and Reset-Config paths that mutate state fields without clearing the map.)*
- **[leak/cursor] Per-rebuild `TextEditingController(text: board['name'])` for display-board name.** Identity-keyed `_boardNameCtrls` map keyed by the stable board Map reference (not list index — `removeAt()` shifts indices); disposed in dispose.

### misc — `version_provider.dart`, `voice_guidance_service.dart`, `identity_cameras.dart`, `company_info_step.dart`, `settings_scope_provider.dart`, `account_step.dart`, `tally_service.dart`
- **[collision] Lossy radix-100 version→int packing (`1.0.100 == 1.1.0`).** Widened base to `*1000000 + *1000 + *1` in `_versionToInt`. *(Residual: still collides for any segment ≥ 1000 — realistic semver safe.)*
- **[perf] Blocking `Process.runSync('killall', -9)` on voice-stop.** Replaced the 3 calls with `Process.run(...).ignore()`; `stop()` stays `void`; tracked `_activeProcess` still killed first.
- **[obs] Fire-and-forget face-embedding update swallows write errors.** `.catchError((_) {})` → `.catchError((e) => debugPrint(...))`.
- **[PII] GSTIN lookup logs PAN/address via `debugPrint`.** Deleted the raw-response `debugPrint`; benign status line kept.
- **[deadcode] `setSettingScope` helper is dead code.** Deleted (zero call sites); `scopedSettingDoc` + import retained.
- **[leak] Redirect-countdown Timer not stored in a field.** Added `Timer? _redirectTimer;`, assign + cancel-prior, cancel in dispose.
- **[deadcode] Dead id-verify code can set `_idVerified=true` on non-Aadhaar/name-mismatch.** Deleted the dead `_acceptCorrectedName` method (zero call sites). Live mismatch setState blocks untouched.
- **[injection] Tally XML/voucher injection via unescaped free-text.** Added `_xmlEscape` (`&` first, then `< > " '`) applied to all interpolated free-text fields in `_buildVoucherXml`/`_buildLedgerXml` (incl. the `NAME="..."` attribute). Date/numeric left unescaped.

### deadfiles-lints — `identity_step.dart`, `site_setup_screen.dart`, `camera_carousel.dart`, `camera_feeds_panel.dart`, `analysis_options.yaml`
- **[deadfile] Orphaned in-scope files (re-introduction hazard).** Deleted `identity_step.dart`, `site_setup_screen.dart`, `camera_carousel.dart`, `camera_feeds_panel.dart` (each verified 0 external references; post-deletion analyze 0 errors).
- **[§E lints] Enable defect-class lints going forward.** `analysis_options.yaml`: enabled `cancel_subscriptions`, `close_sinks`, `unawaited_futures`, `use_build_context_synchronously`, each mapped to `warning` (not error) so they surface without failing the build.

---

## SKIPPED / flagged — items the user must still do

### 🚫 BLOCKING — do NOT ship/deploy without resolving

1. **`firestore.rules` is the staging LOCKOUT file — DO NOT `firebase deploy` it.** The working `firestore.rules` is byte-identical to the multi-tenant `belongs(companyId)` rewrite, whose own header (lines 1-8) states STAGING / NOT DEPLOYED and that the first 2026-06-13 deploy failed `permission-denied` because the `companyId` claim is set server-side but **not carried in the live token**. Every company-scoped path is gated on `request.auth.token.companyId`, which is absent under this app's custom SHA-256/Firestore auth (`request.auth` may be null entirely). **Deploying it denies all client reads/writes app-wide.** The two reported surgical fixes (`passwordHash`/`emailVerified`/`hasPin` blocklist; notifications `create:if false`+`update hasOnly(['read'])`) are **NOT present in this file** and must be re-applied to the currently-deployed (non-tightened) ruleset before any rules deploy.

2. **`offline` dead-letter cap causes silent weighment + audit-log data loss.** `_recordFailure`/`_maxAttempts=20` is wired into the network-failure catch of EVERY flush handler (including `_flushWeighments` and `_flushAuditLogs`), not just the integration-retry queues it was meant for. On desktop targets (`lib/main.dart:49,53` sets `persistenceEnabled = !isDesktopNative`, so Windows/Linux Firestore persistence is OFF and writes throw promptly when offline), ~20 flush cycles at the 10s cadence (~3.3 min of routine offline operation) silently rename a legitimate, fully-syncable weighment AND its audit-log entry into `$_basePath/dead_letter` and drop them from the active queue. The loss is also **silent**: `dead_letter` is excluded from `pendingBreakdown`, so the status panel shows 0 pending and `_lastSyncSuccess` flips back to green. **Fix before release:** restrict dead-lettering to genuinely-poison conditions (e.g. JSON-parse/malformed-payload), or apply the attempt cap ONLY to `sheets_retry`/`billing_retry`; never silently drop weighments/audit on transient Firestore write failures; at minimum keep dead-lettered core records visible.

3. **`MFA_ENC_KEY` rotation will lock out pre-existing MFA-enrolled users.** `_mfaKey()` removed the old hardcoded fallback (`tulanam-mfa-default-key`) and now requires `MFA_ENC_KEY`. `functions/.env` sets it, but to a NEW value (`e3a53a78...`), not the old default. AES-256-GCM is authenticated, so any TOTP secret encrypted under the old key throws an auth-tag mismatch in `_decryptSecret` — and in `loginUser` `_decryptSecret(...)` runs BEFORE the backup-code branch, so an affected user is **locked out at login with no backup-code escape hatch**. **Fix before release:** re-encrypt existing MFA secrets under the new key, or force MFA re-enrollment for any account enrolled before this change. Also: `MFA_ENC_KEY` and `LICENSE_ADMIN_SECRET` are **not documented in `functions/.env.example`**.

### Required post-merge deploys (user action)

4. **`firebase deploy --only functions`** — all 13 `functions/index.js` security fixes (session revocation, MFA re-enroll gate, login throttle, atomic backup-code consume, recipient allowlist, etc.) are inert until deployed. **Note:** all exports were also migrated to `functions.region('asia-south1')` and the storage bucket renamed to `tulanam.firebasestorage.app` — confirm the target project/region/bucket before deploy.
5. **`firebase deploy --only firestore:rules`** — only AFTER item #1 is resolved (re-apply the two surgical fixes to the deployed ruleset; do not deploy the staging tightened file).

### Excluded migration / deferred items (per audit §C and DO-NOT list — out of scope for this batch)

6. **`cache` — session-token restore deliberately NOT wired.** `getCachedSessionToken()` exists but is intentionally never called: `main.dart:58 clearCurrentUser()` forces fresh login on every cold start, which is currently the ONLY session-revocation checkpoint. Wiring restore would resurrect a deactivated/deleted/demoted user's cached token (aggravates the functions HIGH revocation finding). *Footgun:* the unused getter should be deleted or annotated so a future dev doesn't wire it.
7. **`cache` — Linux ships zero Firebase plugins but `Firebase.initializeApp` is called unconditionally.** §C deferred build-hygiene defect; Linux not a shipping target; root is `linux/generated_plugins.cmake` (unowned). Left untouched.
8. **`misc`/`account_step` — macOS fabricates operator/admin `uid` from `email.hashCode`.** Excluded by DO-NOT item #3 (server-issued id is another track's wiring).
9. **`misc`/`account_step` — client writes unsalted SHA-256 `passwordHash`/`pinHash` to Firestore.** Excluded by DO-NOT item #2 (removal is a lockout risk needing `registerCredential` wiring). The exploit it feeds is meant to be closed by the rules `operatorUpdateSafe` `passwordHash` blocklist — which is currently ABSENT (see item #1).
10. **`backup` — `.wbk` KDF is bare unsalted SHA-256.** §C documented-deferred; left unchanged for decrypt compatibility.

### Non-blocking gaps & flagged residuals (verifier `issues`)

- **functions — `mfaDisable` now requires the 2nd factor and DROPS the password path** (intended hardening). Tradeoff: a user who loses BOTH authenticator and backup codes can no longer self-disable 2FA — recovery depends entirely on the email-OTP/`verifyMfaCode` reset path.
- **functions — login throttle counters (`loginFailCount`/`loginLockUntil`) live on the client-writable operator/company doc**, so an attacker can reset their own counter. Accepted limitation for an online-brute-force throttle.
- **operators — `pendingEmail` is WRITE-ONLY.** Nothing reads/reconciles/retries/clears it, and a later successful email edit won't clear a stale value. The Auth/Firestore divergence is fixed but the parked email is orphaned and the "try again later" toast has no backing machinery.
- **settings-scope — `custom_fields` scope change can silently DISCARD the most recent unsaved edit.** `_changeScope` cancels the pending debounce, then copies from the PERSISTED doc, so an edit armed within 600ms of a scope change is lost. The data-preserving fix is FLUSH-then-read, not cancel.
- **form — `printing_screen` number/double inputs now show STALE values** after programmatic state mutations that don't clear the controller map: the Cut-Length dropdown (`_dmLogoHeight = 10`) and Reset-Config button (`_normalMargin*`). The displayed field diverges from state; the old leaky controller always reflected the latest value.
- **customers — narrow new-orphaning edge:** a weighment under the merged/renamed name with a present-but-different phone is now skipped while the source customer doc is still deleted (dirty-data/typo cases with no surviving same-named customer).
- **sidecar — `compareFaces`/`verifyBurst` still build unencoded query URLs** (low-risk: numeric threshold, fixed-enum collection — out of named scope). `ai_provider.dart:169 data['status'] ?? 'active'` is a latent always-active no-op worth a separate ticket.
- **secprov — UI residual:** `security_screen.dart` should hide/label the `restrictUsb` toggle when `!usbMonitorProvider.supported` (unowned file; provider half done).
- **dashboard / secprov — DRY residual:** `Platform.isWindows || Platform.isLinux` and the `restrictUsb` capability are duplicated; centralizing a `PlatformService.isDesktopNative` predicate is deferred to a unit owning the shared files.

### ⚠️ SCOPE — working tree is far larger than the documented fixes

The diff is **77 files / +4,879 / −4,991 (~9.8k lines)** — far beyond the 22 documented units. Multiple unit reviews independently flagged **commingled in-flight feature WIP** that cannot be git-isolated from the audit fixes (the working tree was already dirty with no clean baseline). Examples surfaced by verifiers: region migration of all functions to `asia-south1` + storage-bucket rename + custom-claims minting (functions); GPS/map feature removal (settings-general); screensaver feature (security-screen/secprov); `AppUpdateCard` → `_VersionUpdateFooter` (profile); large weigh-screen / `vehicle_info_form` redesign (form); customer-face CCTV tile (cameras); numerous notification copy edits. **The committer cannot cleanly separate audit fixes from feature WIP** — review the full diff before committing, and do not assume "compile-clean" equals "reviewed."

---

## Compile gate results (final)

- **`flutter analyze lib`:** **0 errors** (202 issues total: 123 warnings + 79 info — all pre-existing or newly-surfaced by the `analysis_options.yaml` lint enablement; none error-severity, none in scope to fix). No errors required fixing.
- **`node --check functions/index.js`:** **PASS** (parses; ESLint is not installed in `functions/`, so `node --check` is the correct syntax gate).
