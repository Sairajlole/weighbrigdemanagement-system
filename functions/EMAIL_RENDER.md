# Rendered email documents (receipt & report) — setup

Receipt and report emails carry a **rendered inline image** (in the body) **and a
PDF attachment** of the designed document. Rendering happens in an **isolated
gen-2 function** so Chromium never taxes the gen-1 OTP/notification cold starts.

```
weighment completed / scheduled report
        │  (gen-1, index.js)
        ▼
  _renderEmailAssets()  ──HTTP──▶  renderEmailDoc  (gen-2, email_render.js)
        │                              · build HTML (email_templates.js)
        │                              · bwip-js PDF417
        │                              · Puppeteer + @sparticuz/chromium
        │                              · .wrap → PNG (Storage → signed URL)
        │                              · page.pdf(printer paperSize) → base64
        ▼
  _sendRenderedEmail():  <img signedUrl> + buildBrandEmail fallback + PDF attachment
```

If rendering fails or is unconfigured, callers **fall back to the existing
`buildBrandEmail` HTML** — nothing breaks.

## Files
- `email_templates.js` — pure, data-driven `buildReceiptHtml` / `buildReportHtml`
  (verified locally against `docs/email-mockups/`).
- `email_render.js` — gen-2 `renderEmailDoc` (Cloud Run, 1 GiB).
- `assets/logo_tile.png` — background watermark tile (embedded as a data URI).
- `index.js` — `_renderEmailAssets`, `_companyDetails`, `_printerPageSize`,
  `_sendRenderedEmail`, `_weighmentToReceiptData`; wired into the weighment-receipt
  trigger and `scheduledEmailReport`.

## Deploy
1. `cd functions && npm install` (adds `puppeteer-core`, `@sparticuz/chromium`, `bwip-js`).
2. `firebase deploy --only functions` — deploys the gen-1 functions **and** the
   gen-2 `renderEmailDoc`. (firebase-functions ^4.5 supports v2; if the deploy
   rejects Node 22 gen-2, bump `firebase-functions` to ^6 and redeploy.)
3. Grab the deployed `renderEmailDoc` URL, then set config and redeploy gen-1:
   ```
   firebase functions:config:set render.url="https://<region>-weighbridge-management.cloudfunctions.net/renderEmailDoc" render.secret="<random-secret>"
   # set the same secret for the renderer's runtime env:
   #   RENDER_SECRET=<random-secret>   (functions/.env or gen-2 env)
   firebase deploy --only functions
   ```

## Config / env
| Key | Where | Purpose |
|---|---|---|
| `render.url` (or `RENDER_URL`) | gen-1 | URL of `renderEmailDoc` |
| `render.secret` (or `RENDER_SECRET`) | gen-1 **and** renderer | shared secret; renderer rejects calls without the `x-render-secret` header |

## Enabling
- **Receipts:** set `sendWeighmentReceipts: true` on
  `companies/{c}/sites/{s}/weighbridges/{w}/settings/general`, and the weighment
  must have a `customerPhone` (+ `customerEmail` for the email).
- **Reports:** existing `companies/{c}/settings/emailSchedule` (enabled + recipient).
- **PDF page size:** read from `companies/{c}/settings/printing` → `normal.paperSize`
  (A4/A5/Letter/Legal; defaults A4).

## ⚠️ Must verify on a real deploy (could not be tested in-session)
1. **Chromium launch** — `@sparticuz/chromium` + `puppeteer-core` under Node 22 in
   gen-2. If it fails, align versions (chromium ↔ puppeteer-core) per @sparticuz docs.
2. **`getSignedUrl` signing** — the function's service account needs the
   **Service Account Token Creator** role (`roles/iam.serviceAccountTokenCreator`),
   or signing 403s. Grant it to the gen-2 runtime SA if signed URLs fail.
3. **Fonts** — cloud Chromium loads Inter from Google Fonts over the network
   (`document.fonts.ready` is awaited). Confirm it renders, not a fallback font.
4. **Field mappings in `_weighmentToReceiptData`** — the CCTV snapshot shape
   (`firstWeightSnapshots`/`secondWeightSnapshots`), `customFields`, and the
   operator `port`/`pc`/`shift` fields are best-effort guesses; verify against a
   real weighment document and adjust.
5. **Renderer exposure** — `renderEmailDoc` is `onRequest` (HTTP). Keep
   `RENDER_SECRET` set; optionally restrict ingress to internal-only.
6. **Storage cleanup** — rendered PNGs land in `email_renders/`; add a bucket
   lifecycle rule (e.g. delete after 30 days) so they don't accumulate.
7. **Gmail/Outlook image display** — the inline `<img>` uses a private signed URL.
   Gmail proxies images through Google's cache; usually fine, but confirm the hero
   image actually shows in a real Gmail **and** Outlook client (a 403 there means
   only the fallback text shows — still readable, but not the design).
8. **Blocking latency** — `onWeighmentUpdated` calls the renderer **inline** and
   waits for Chromium cold-start + PNG+PDF before returning. Confirm the gen-1
   trigger's `timeoutSeconds` comfortably exceeds that. If receipts get heavy or
   bursty, decouple via a task/queue (enqueue, render+send async) so the trigger
   returns immediately.
9. **Concurrency ceiling** — `renderEmailDoc` is `concurrency: 1`, so N concurrent
   renders = N Cloud Run instances each cold-starting Chromium. Fine at low volume;
   revisit (warm instances / higher concurrency + more memory) under bursts.

## Per-company spend caps (cost guard)
Each company has a **monthly email and SMS cap**. Once a month's cap is hit,
further sends of that kind are skipped (and a `*Blocked` counter is bumped). This
bounds spend per company.

- **Configure per company:** `companies/{c}/settings/limits`
  `{ emailMonthly: <n>, smsMonthly: <n> }`. A key set to **0 (or unset)** = unlimited
  for that key.
- **Global defaults:** env `DEFAULT_EMAIL_MONTHLY` (default **5000**) and
  `DEFAULT_SMS_MONTHLY` (default **1000**), or `functions.config().limits.email_monthly` /
  `.sms_monthly`.
- **Translate a budget → caps** (rough unit costs): `smsMonthly ≈ ₹budget_sms / 0.25`,
  `emailMonthly ≈ ₹budget_email / 0.02`. SMS is the real cost, so the **SMS cap is
  the main budget lever**. Example: cap a company at ~₹250/mo of SMS → `smsMonthly: 1000`.
- **Usage** is tracked server-side in `companies/{c}/usage/{YYYY-MM}`
  `{ email, sms, emailBlocked, smsBlocked }` (Firestore rule: client-readable,
  **server-write-only** so the counter can't be tampered). Resets each calendar
  month (IST) — a new period doc.
- **Never capped (always send, still counted toward usage):** OTP/auth mail, and
  **critical security messages** — security/gate alerts, password-changed, MFA-changed,
  contact-changed (these pass `critical: true`, i.e. `_consumeQuota(..., {force:true})`).
  A cost cap must never suppress a safety/security message.
- **Capped (discretionary):** welcome, operator-invite, licence, quota, KYC,
  address-grace, backup-failed, **receipts, reports**.
- **90% warning:** when a company's monthly usage crosses 90% of a cap, the admin
  gets a **one-time in-app notification** (free/uncapped — written to
  `companies/{c}/notifications`), so hitting the cap isn't a surprise.
- **Best-effort:** a small over-count is possible under heavy concurrency (no
  transaction) — fine for a budget guard. A transient Firestore error **fails open**
  (sends rather than drops mail).

## Recommended hardening (before/at deploy)
- **Embed Inter as base64 `@font-face`** in `email_templates.js` instead of the
  Google Fonts `<link>`. It removes the one network dependency from the render
  (already bounded to 3s, but embedding guarantees the font and avoids any
  fallback), at the cost of a larger template string. Highest-value follow-up.
