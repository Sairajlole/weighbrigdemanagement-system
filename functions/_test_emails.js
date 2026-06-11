// One-off: send a test of every Tulanam email template to a recipient.
// Builders below are copied verbatim from index.js (post tagline-removal).
const fs = require("fs");
const path = require("path");
const nodemailer = require("nodemailer");

// ── load GMAIL creds from .env ───────────────────────────────────────────────
const env = {};
for (const line of fs.readFileSync(path.join(__dirname, ".env"), "utf8").split("\n")) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
  if (m) env[m[1]] = m[2].trim();
}
const GMAIL_EMAIL = env.GMAIL_EMAIL;
const GMAIL_APP_PASSWORD = env.GMAIL_APP_PASSWORD;
const TO = process.argv[2] || "yashjain2681@gmail.com";

const OTP_EXPIRY_MINUTES = 10;
const BRAND = {
  name: "Tulanam", glyph: "⚖", website: "tulanam.com", support: "support@tulanam.com",
  noreply: "noreply@tulanam.com", teal: "#0D9488", tealTint: "#F0FDFA", navy: "#1E3A5F",
  slate: "#94A3B8", ink: "#0F172A", muted: "#64748B", border: "#E2E8F0", pageBg: "#F4F6F8",
};
const _EMAIL_FONT = "'Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";
const _EMAIL_MONO = "'SFMono-Regular',Consolas,'Liberation Mono',Menlo,monospace";

function _emailShell(innerHtml) {
  const f = _EMAIL_FONT;
  return `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:${BRAND.pageBg};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND.pageBg};padding:32px 12px;">
    <tr><td align="center">
      <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="width:480px;max-width:100%;background:#ffffff;border:1px solid ${BRAND.border};border-radius:12px;overflow:hidden;">
        <tr><td style="background:${BRAND.navy};padding:22px 32px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
            <td style="font-family:${f};color:#ffffff;font-size:19px;font-weight:700;letter-spacing:0.3px;">
              <span style="display:inline-block;width:26px;height:26px;background:${BRAND.teal};border-radius:6px;text-align:center;line-height:26px;font-size:15px;vertical-align:middle;margin-right:10px;">${BRAND.glyph}</span>${BRAND.name}
            </td>
          </tr></table>
        </td></tr>
        <tr><td style="height:3px;background:${BRAND.teal};line-height:3px;font-size:0;">&nbsp;</td></tr>
        <tr><td style="padding:32px;">${innerHtml}</td></tr>
        <tr><td style="border-top:1px solid ${BRAND.border};padding:16px 32px;">
          <p style="margin:0 0 6px;font-family:${f};color:${BRAND.slate};font-size:11px;line-height:1.55;">Automated message from ${BRAND.name}.</p>
          <p style="margin:0;font-family:${f};color:${BRAND.slate};font-size:11px;line-height:1.55;">Need help? <a href="mailto:${BRAND.support}" style="color:${BRAND.teal};text-decoration:none;">${BRAND.support}</a> &nbsp;·&nbsp; <a href="https://${BRAND.website}" style="color:${BRAND.teal};text-decoration:none;">${BRAND.website}</a></p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

function buildOtpEmail({ heading, intro, otp, securityNote }) {
  const f = _EMAIL_FONT, mono = _EMAIL_MONO;
  const expiry = `${OTP_EXPIRY_MINUTES} minute${OTP_EXPIRY_MINUTES === 1 ? "" : "s"}`;
  return _emailShell(
    `<h1 style="margin:0 0 8px;font-family:${f};color:${BRAND.ink};font-size:20px;font-weight:700;">${heading}</h1>
          <p style="margin:0 0 24px;font-family:${f};color:${BRAND.muted};font-size:14px;line-height:1.55;">${intro}</p>
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
            <td align="center" style="background:${BRAND.tealTint};border:1px solid ${BRAND.teal};border-radius:10px;padding:20px 16px;">
              <div style="font-family:${f};color:${BRAND.muted};font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:1.5px;margin-bottom:10px;">Verification Code</div>
              <div style="font-family:${mono};color:${BRAND.teal};font-size:34px;font-weight:700;letter-spacing:10px;line-height:1;">${otp}</div>
            </td>
          </tr></table>
          <p style="margin:20px 0 0;font-family:${f};color:${BRAND.ink};font-size:13px;line-height:1.55;">This code is valid for <strong>${expiry}</strong> and can be used once.</p>
          <p style="margin:8px 0 0;font-family:${f};color:${BRAND.muted};font-size:12px;line-height:1.55;">${securityNote}</p>`);
}

function buildBrandEmail({ heading, intro, rows = [], note, ctaText, ctaUrl, accent }) {
  const f = _EMAIL_FONT;
  const chipColor = accent === "danger" ? "#DC2626" : accent === "warn" ? "#D97706" : BRAND.teal;
  let inner = "";
  if (accent === "danger" || accent === "warn") {
    const label = accent === "danger" ? "Security alert" : "Action required";
    inner += `<div style="display:inline-block;background:${chipColor};color:#ffffff;font-family:${f};font-size:10px;font-weight:700;letter-spacing:1px;text-transform:uppercase;padding:4px 10px;border-radius:4px;margin-bottom:14px;">${label}</div>`;
  }
  inner += `<h1 style="margin:0 0 8px;font-family:${f};color:${BRAND.ink};font-size:20px;font-weight:700;">${heading}</h1>`;
  if (intro) inner += `<p style="margin:0 0 20px;font-family:${f};color:${BRAND.muted};font-size:14px;line-height:1.55;">${intro}</p>`;
  if (rows.length) {
    inner += `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND.pageBg};border:1px solid ${BRAND.border};border-radius:10px;margin:0 0 20px;">`;
    rows.forEach(([label, value], i) => {
      const top = i === 0 ? "" : `border-top:1px solid ${BRAND.border};`;
      inner += `<tr><td style="${top}padding:11px 16px;font-family:${f};color:${BRAND.muted};font-size:12px;">${label}</td>` +
        `<td align="right" style="${top}padding:11px 16px;font-family:${f};color:${BRAND.ink};font-size:13px;font-weight:600;">${value}</td></tr>`;
    });
    inner += "</table>";
  }
  if (ctaText && ctaUrl) {
    inner += `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 16px;"><tr><td style="background:${BRAND.teal};border-radius:8px;"><a href="${ctaUrl}" style="display:inline-block;padding:11px 22px;font-family:${f};color:#ffffff;font-size:14px;font-weight:600;text-decoration:none;">${ctaText}</a></td></tr></table>`;
  }
  if (note) inner += `<p style="margin:0;font-family:${f};color:${BRAND.muted};font-size:12px;line-height:1.55;">${note}</p>`;
  return _emailShell(inner);
}

function buildReportEmailHtml(periodLabel, totalWeighments, vehicleCount, totalNet, materialTotals) {
  const rows = [
    ["Period", periodLabel], ["Total weighments", String(totalWeighments)],
    ["Unique vehicles", String(vehicleCount)], ["Net tonnage", `${(totalNet / 1000).toFixed(1)} T`],
  ];
  Object.entries(materialTotals).sort((a, b) => b[1] - a[1]).slice(0, 5)
    .forEach(([m, v]) => rows.push([`Material · ${m}`, `${(v / 1000).toFixed(1)} T`]));
  return buildBrandEmail({
    heading: `Weighment report — ${periodLabel}`,
    intro: `Here is your ${BRAND.name} operations summary.`, rows,
    note: `Automated report from ${BRAND.name}.`,
  });
}

// ── all templates ────────────────────────────────────────────────────────────
const S = BRAND.support;
const emails = [
  ["Tulanam verification code: 428170", buildOtpEmail({ heading: "Verify your email address", intro: "Use the code below to confirm this email address for your Tulanam account.", otp: "428170", securityNote: `If you didn't request this, you can safely ignore this email. ${BRAND.name} will never ask you to share this code.` })],
  ["Tulanam password reset code: 903514", buildOtpEmail({ heading: "Reset your password", intro: "Hi Yash, use the code below to reset your Tulanam password.", otp: "903514", securityNote: `If you didn't request a password reset, ignore this email — your password stays unchanged.` })],
  ["Tulanam security alert: EMERGENCY LOCKDOWN ACTIVATED", buildBrandEmail({ heading: "EMERGENCY LOCKDOWN ACTIVATED", intro: "All operator sessions have been locked. Only admin access remains.", accent: "danger", note: `If you did not expect this alert, secure your account and contact ${S}.` })],
  ["Tulanam: your password was changed", buildBrandEmail({ accent: "danger", heading: "Your password was changed", intro: "The password for your Tulanam account was just changed. If this was you, no further action is needed.", note: `If you did NOT do this, contact ${S} immediately — your account may be at risk.` })],
  ["Tulanam: your email was updated", buildBrandEmail({ accent: "warn", heading: "Your account email address was updated", intro: "Hi Yash, the email address on your Tulanam account was just changed.", rows: [["Updated field", "email address"], ["New value", "yash@example.com"]], note: `If you did not make this change, contact ${S} immediately.` })],
  ["Welcome to Tulanam", buildBrandEmail({ heading: "Welcome to Tulanam", intro: "Your Tulanam account for ABC Weighbridge is ready. We've mailed a verification code to your registered address; enter it within 30 days to keep your account active.", rows: [["Company", "ABC Weighbridge"], ["Address verification", "30-day window"]], note: `Questions? Reach us at ${S}.` })],
  ["You've been added to ABC Weighbridge on Tulanam", buildBrandEmail({ heading: "Welcome to Tulanam", intro: "Hi Ravi, you've been added as an operator for ABC Weighbridge. Open the Tulanam desktop app and sign in with this email to get started.", rows: [["Company", "ABC Weighbridge"], ["Your role", "Operator"], ["Sign-in email", "ravi@example.com"]], note: `If you weren't expecting this, ignore this message or contact ${S}.` })],
  ["Tulanam: your pro plan is active", buildBrandEmail({ heading: "Your plan is active", intro: "Your Tulanam license has been activated — you're all set to run your weighbridge operations.", rows: [["Plan", "pro"], ["Weighbridges", "Unlimited"], ["Valid until", "No expiry"]], note: "Manage your subscription anytime at tulanam.com." })],
  ["Tulanam: your subscription expires in 3 days", buildBrandEmail({ accent: "warn", heading: "Your subscription is expiring", intro: "Your Tulanam subscription expires in 3 days. Renew to avoid interruption to weighbridge operations.", rows: [["Expires in", "3 days"]], ctaText: "Renew subscription", ctaUrl: "https://tulanam.com/billing", note: `Need help? Contact ${S}.` })],
  ["Tulanam: your subscription has expired", buildBrandEmail({ accent: "warn", heading: "Your subscription has expired", intro: "Your Tulanam subscription has expired. Renew now to restore full access to your weighbridge operations.", ctaText: "Renew subscription", ctaUrl: "https://tulanam.com/billing", note: `Need help renewing? Contact ${S}.` })],
  ["Tulanam: verify your business address (5 days left)", buildBrandEmail({ accent: "warn", heading: "Verify your business address", intro: "To keep your Tulanam account active, enter the verification code from the letter we mailed to your registered address. You have 5 days left.", rows: [["Time left", "5 days"]], note: `Didn't receive the letter? Contact ${S} for a reissue.` })],
  ["Tulanam: identity verification approved", buildBrandEmail({ heading: "Identity verified", intro: "Hi Ravi, your identity has been verified on Tulanam. You're all set.", note: "Questions? Contact your Tulanam administrator." })],
  ["Tulanam: identity verification needs attention", buildBrandEmail({ accent: "warn", heading: "Identity verification not approved", intro: "Hi Ravi, your identity verification was not approved. Please re-submit your documents or contact your administrator.", note: "Questions? Contact your Tulanam administrator." })],
  ["Tulanam: your operator access was deactivated", buildBrandEmail({ accent: "warn", heading: "Your operator access was deactivated", intro: "Hi Ravi, your operator access on Tulanam has been deactivated, so you will no longer be able to sign in.", note: "If you believe this is a mistake, contact your Tulanam administrator." })],
  ["Tulanam: cloud backup failed", buildBrandEmail({ accent: "warn", heading: "Your cloud backup failed", intro: "A scheduled Tulanam cloud backup did not complete. Your data is safe locally, but the off-site copy was not updated.", rows: [["Status", "Failed"], ["Reason", "GDrive: no access token"]], note: `Open Settings → Integrations to check your backup configuration, or contact ${S}.` })],
  ["Tulanam: two-factor authentication disabled", buildBrandEmail({ accent: "danger", heading: "Two-factor authentication disabled", intro: "Two-factor authentication was just disabled on your Tulanam account.", note: `If you did NOT disable 2FA, contact ${S} immediately — your account may be at risk.` })],
  ["Tulanam: weighbridge limit reached", buildBrandEmail({ accent: "warn", heading: "You've reached your weighbridge limit", intro: "Your Tulanam plan allows 2 weighbridges and you've now reached that limit. Upgrade your plan to add more.", rows: [["Plan limit", "2"], ["In use", "2"]], ctaText: "Upgrade plan", ctaUrl: "https://tulanam.com/billing", note: `Need a higher limit? Contact ${S}.` })],
  ["Tulanam: weighment receipt RST-1042", buildBrandEmail({ heading: "Weighment receipt", intro: "Your weighment for vehicle MH12AB1234 has been recorded and confirmed.", rows: [["Ticket", "RST-1042"], ["Vehicle", "MH12AB1234"], ["Material", "M-Sand"], ["Gross", "42000 kg"], ["Tare", "14000 kg"], ["Net weight", "28000 kg"]], note: "Questions about this weighment? Contact the weighbridge operator." })],
  ["Tulanam Report — Yesterday (148 weighments, 1247.3T)", buildReportEmailHtml("Yesterday", 148, 92, 1247300, { Coal: 642000, "M-Sand": 318000, Gravel: 171000, Cement: 84000, Iron: 32300 })],
];

(async () => {
  const transporter = nodemailer.createTransport({
    service: "gmail", auth: { user: GMAIL_EMAIL, pass: GMAIL_APP_PASSWORD },
  });
  let ok = 0;
  for (let i = 0; i < emails.length; i++) {
    const [subject, html] = emails[i];
    try {
      await transporter.sendMail({
        from: `"${BRAND.name}" <${GMAIL_EMAIL}>`, replyTo: BRAND.support, to: TO,
        subject: `[TEST ${i + 1}/${emails.length}] ${subject}`, html,
      });
      ok++;
      console.log(`✓ ${i + 1}/${emails.length}  ${subject}`);
    } catch (e) {
      console.log(`✗ ${i + 1}/${emails.length}  ${subject} — ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, 700));
  }
  console.log(`\nDone: ${ok}/${emails.length} sent to ${TO}`);
})();
