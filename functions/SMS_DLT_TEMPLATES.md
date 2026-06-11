# Tulanam SMS — DLT templates & Fast2SMS setup

Every SMS Tulanam sends is **DLT-bound (TRAI mandate)**: the message body is fixed
by a template registered on the DLT portal under the **TULNAM** header. Our code
only injects variables — it cannot change the wording at runtime. **Until each
template ID below is set as an env var, that SMS is logged and skipped (it never
breaks the app).** Email always works without any of this.

## Rules followed here
- Header / sender ID: **TULNAM** (6 chars — DLT limit).
- Each template ≤ **3 variables**, passed **pipe-separated (`|`) in the exact order listed**.
- Static text sits between every `{#var#}` (operators reject adjacent variables).
- OTP uses Fast2SMS's dedicated **OTP API** (`/dev/otp/send`); all others use the
  **DLT bulk route** (`/dev/bulkV2`, `route=dlt`).

## Required environment variables (`functions/.env`)
```
# Channel credentials
GMAIL_EMAIL=...                 # already set — email sender
GMAIL_APP_PASSWORD=...          # already set
FAST2SMS_API_KEY=...            # Fast2SMS API key (all SMS)
FAST2SMS_SENDER_ID=TULNAM       # DLT header (transactional SMS)
FAST2SMS_OTP_ID=...             # Fast2SMS OTP Template ID (OTP only)

# Transactional DLT template IDs (each = one registered template)
FAST2SMS_TPL_PASSWORD_CHANGED=...
FAST2SMS_TPL_SECURITY_ALERT=...
FAST2SMS_TPL_GATE_ALERT=...
FAST2SMS_TPL_LICENSE_EXPIRY=...
FAST2SMS_TPL_LICENSE_EXPIRED=...
FAST2SMS_TPL_ADDRESS_GRACE=...
FAST2SMS_TPL_OPERATOR_INVITE=...
FAST2SMS_TPL_CONTACT_CHANGED=...
FAST2SMS_TPL_WEIGHMENT_RECEIPT=...
FAST2SMS_TPL_MFA_CHANGED=...
FAST2SMS_TPL_BACKUP_FAILED=...
FAST2SMS_TPL_WELCOME=...
FAST2SMS_TPL_LICENSE_ACTIVATED=...
FAST2SMS_TPL_OPERATOR_DEACTIVATED=...
FAST2SMS_TPL_KYC_RESULT=...
FAST2SMS_TPL_DAILY_DIGEST=...
FAST2SMS_TPL_QUOTA_REACHED=...
```

## 1. OTP — Fast2SMS OTP API
Register on DLT, create a Fast2SMS **OTP Template**, put its ID in `FAST2SMS_OTP_ID`.
The single `{#var#}` is the code (we pass our own value so it matches the hash we verify).

```
Tulanam: {#var#} is your verification code. Valid for 10 minutes. Do not share it with anyone.
```

## 2. Transactional templates (bulk DLT route, header TULNAM)
Register each, then set the matching env var to its Template ID.

| Env var | Variables (order) | Template text to register |
|---|---|---|
| `FAST2SMS_TPL_PASSWORD_CHANGED` | name | `Tulanam: Hi {#var#}, your account password was just changed. If this was not you, contact support immediately. - Tulanam` |
| `FAST2SMS_TPL_SECURITY_ALERT` | alert | `Tulanam security alert: {#var#}. Please review your account now. - Tulanam` |
| `FAST2SMS_TPL_GATE_ALERT` | alert | `Tulanam gate alert: {#var#}. Please check the gate control system. - Tulanam` |
| `FAST2SMS_TPL_LICENSE_EXPIRY` | days | `Tulanam: Your subscription expires in {#var#} days. Renew now to avoid interruption. - Tulanam` |
| `FAST2SMS_TPL_LICENSE_EXPIRED` | (none) | `Tulanam: Your subscription has expired. Renew now to restore full access. - Tulanam` |
| `FAST2SMS_TPL_ADDRESS_GRACE` | days | `Tulanam: Verify your business address within {#var#} days to keep your account active. Use the code in the letter we mailed. - Tulanam` |
| `FAST2SMS_TPL_OPERATOR_INVITE` | company | `Tulanam: You have been added as an operator for {#var#}. Open the Tulanam app to sign in. - Tulanam` |
| `FAST2SMS_TPL_CONTACT_CHANGED` | field | `Tulanam: Your account {#var#} was just updated. If this was not you, contact support. - Tulanam` |
| `FAST2SMS_TPL_WEIGHMENT_RECEIPT` | ticket, vehicle, net | `Tulanam: Weighment {#var#} for vehicle {#var#} is recorded. Net weight {#var#} kg. - Tulanam` |
| `FAST2SMS_TPL_MFA_CHANGED` | state | `Tulanam: Two-factor authentication was {#var#} on your account. If this was not you, contact support. - Tulanam` |
| `FAST2SMS_TPL_BACKUP_FAILED` | (none) | `Tulanam: Your scheduled cloud backup failed. Open Settings then Integrations to check. - Tulanam` |
| `FAST2SMS_TPL_WELCOME` | company | `Tulanam: Welcome aboard, {#var#}. Your account is ready. - Tulanam` |
| `FAST2SMS_TPL_LICENSE_ACTIVATED` | tier | `Tulanam: Your {#var#} plan is now active on Tulanam. - Tulanam` |
| `FAST2SMS_TPL_OPERATOR_DEACTIVATED` | (none) | `Tulanam: Your operator access has been deactivated. Contact your administrator. - Tulanam` |
| `FAST2SMS_TPL_KYC_RESULT` | status | `Tulanam: Your identity verification was {#var#}. - Tulanam` |
| `FAST2SMS_TPL_DAILY_DIGEST` | weighments, tonnage | `Tulanam: Daily summary — {#var#} weighments, {#var#} tonnes recorded. - Tulanam` |
| `FAST2SMS_TPL_QUOTA_REACHED` | resource | `Tulanam: You have reached your plan limit for {#var#}. Upgrade to add more. - Tulanam` |

> The template text and variable order here are the single source of truth and
> mirror `DLT_TEMPLATES` / `FAST2SMS_OTP_TEMPLATE_TEXT` in `functions/index.js`.
> If you edit one, edit both.

## Notification catalogue (where each fires)
| Event | Email | SMS template | Trigger |
|---|---|---|---|
| Email verification code | ✅ | OTP API | `sendEmailOTP` (email only) |
| Phone verification code | — | OTP API | `sendPhoneOTP` |
| Password reset code | ✅ | OTP API | `sendPasswordResetOTP` |
| Password changed | ✅ | passwordChanged | `resetUserPassword` + `notifyPasswordChanged` (client) |
| Repeated failed logins | ✅ | securityAlert | `onAuditLogCreated` |
| Emergency lockdown | ✅ | securityAlert | `onAuditLogCreated` |
| IP whitelist / encryption / audit disabled | ✅ | securityAlert | `onSecurityCriticalChange` |
| Gate control / emergency-stop / interlock disabled | ✅ | gateAlert | `onGateSettingsChanged` |
| Blacklisted vehicle at gate | ✅ | gateAlert | `validateRfidTag` |
| Subscription expiring (7/3/1 d) | ✅ | licenseExpiry | `licenseExpiryReminders` (daily) |
| Subscription expired | ✅ | licenseExpired | `checkExpiredLicenses` |
| Address-verification grace (7/3/1 d) | ✅ | addressGrace | `addressGraceReminders` (daily) |
| Welcome / account created | ✅ | welcome | `onCompanyCreated` |
| Operator invited | ✅ | operatorInvite | `onOperatorCreated` |
| Contact (email/phone) changed | ✅ | contactChanged | `updateCompanyContact` |
| MFA enabled / disabled | ✅ | mfaChanged | `notifyMfaChanged` (client) |
| Cloud backup failed | ✅ | backupFailed | `notifyBackupResult` (client) |
| Weighment receipt to customer | ✅ | weighmentReceipt | `onWeighmentUpdated` — **opt-in**, see below |
| License activated (paid key) | ✅ | licenseActivated | `activateLicense` |
| License activated (trial/free) | ✅ | licenseActivated | `notifyLicenseActivated` (client, after trial/free activation) |
| Operator access deactivated | ✅ | operatorDeactivated | `onOperatorUpdated` |
| Identity (KYC) verified / rejected | ✅ | kycResult | `onOperatorUpdated` |
| Daily/weekly summary digest | (email report) | dailyDigest | `scheduledEmailReport` — SMS **opt-in** via `emailSchedule.smsDigest` |
| Weighbridge plan limit reached | ✅ | quotaReached | `onWeighbridgeCreated` |

### Weighment receipts are OFF by default
They fire only when, for that weighbridge,
`companies/{c}/sites/{s}/weighbridges/{w}/settings/general.sendWeighmentReceipts == true`
**and** the weighment has a `customerPhone`. This avoids per-SMS cost on every
weighment until you deliberately enable it.

## Operational notes
- **Alert SMS throttle:** security/gate alert **SMS** is rate-limited to one per
  `(company, template)` per 20 min (`notification_cooldowns` collection,
  server-only) so a brute-force login storm or a re-scanned blacklisted vehicle
  can't trigger an SMS flood. In-app + email are **not** throttled.
- **Index:** the licence-expiry queries need the composite index
  `licenses (status ASC, expiresAt ASC)` — added to `firestore.indexes.json`;
  run `firebase deploy --only firestore:indexes`.
- **Failure visibility:** `_sendOtpSms` / `_sendDltSms` return the Fast2SMS
  `return` flag, so a rejected send surfaces in logs (and `phoneSent` stays
  truthful in the password-reset response).
- **Targeted push (FCM) is macOS-only.** Security/gate alerts also push to a
  company admin's registered devices (`operators.fcmTokens`, populated by the
  `registerFcmToken` callable). `firebase_messaging` has **no Windows/Linux**
  implementation, so push delivers only to macOS clients; everyone is still
  covered by in-app + email + SMS. The client (`FcmService`) is fully guarded —
  a no-op off macOS and on macOS until you add **APNs entitlements** (Apple
  Developer program) in Xcode. Until then nothing fails; push just stays off.
