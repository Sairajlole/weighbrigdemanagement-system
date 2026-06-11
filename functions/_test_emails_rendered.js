// One-off: render every Tulanam email in the NEW design (functions/email_templates.js)
// to a PNG via local Chrome (same .wrap element-screenshot the cloud renderer uses)
// and send it image-only — plus a PDF for receipt/report. Mirrors the production
// "designed email" path. Usage: node _test_emails_rendered.js [recipient]
const fs = require("fs");
const path = require("path");
const nodemailer = require("nodemailer");
const puppeteer = require("puppeteer-core");
const bwipjs = require("bwip-js");
const { buildReceiptHtml, buildReportHtml, buildOtpHtml, buildNotificationHtml } = require("./email_templates");

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

// ── creds from .env ───────────────────────────────────────────────────────────
const env = {};
for (const line of fs.readFileSync(path.join(__dirname, ".env"), "utf8").split("\n")) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
  if (m) env[m[1]] = m[2].trim();
}
const TO = process.argv[2] || "yashjain2681@gmail.com";

// ── assets ────────────────────────────────────────────────────────────────────
const logoTileUri = `data:image/png;base64,${fs.readFileSync(path.join(__dirname, "assets/logo_tile.png")).toString("base64")}`;
async function pdf417(text) {
  const png = await bwipjs.toBuffer({ bcid: "pdf417", text, columns: 10, scale: 3, backgroundcolor: "FFFFFF", paddingwidth: 2, paddingheight: 2 });
  return `data:image/png;base64,${png.toString("base64")}`;
}

const company = { name: "ABC Weighbridge Pvt Ltd", gstin: "27ABCDE1234F1Z5", pan: "ABCDE1234F", address: "Plot 14, MIDC Industrial Area, Pune 411019" };
const S = "support@tulanam.com";

async function buildFormats() {
  const barcodeDataUri = await pdf417("TULANAM|RST:RST-1042|MH12AB1234|NET:28000");
  const n = (data) => buildNotificationHtml({ ...data, company }, { logoTileUri });
  const otp = (data) => buildOtpHtml({ ...data, company }, { logoTileUri });

  return [
    ["Tulanam verification code: 428170", "otp", false,
      otp({ heading: "Verify your email address", intro: "Use the code below to confirm this email address for your Tulanam account.", otp: "428170", securityNote: "If you didn't request this, you can safely ignore this email. Tulanam will never ask you to share this code." })],
    ["Tulanam password reset code: 903514", "otp", false,
      otp({ eyebrow: "Password reset", heading: "Reset your password", intro: "Hi Yash, use the code below to reset your Tulanam password.", otp: "903514", securityNote: "If you didn't request a password reset, ignore this email — your password stays unchanged." })],
    ["Tulanam security alert: EMERGENCY LOCKDOWN ACTIVATED", "notification", false,
      n({ accent: "danger", heading: "Emergency lockdown activated", intro: "All operator sessions have been locked. Only admin access remains.", note: `If you did not expect this alert, secure your account and contact ${S}.` })],
    ["Tulanam: your password was changed", "notification", false,
      n({ accent: "danger", heading: "Your password was changed", intro: "The password for your Tulanam account was just changed. If this was you, no further action is needed.", note: `If you did NOT do this, contact ${S} immediately — your account may be at risk.` })],
    ["Welcome to Tulanam", "notification", false,
      n({ heading: "Welcome to Tulanam", intro: "Your Tulanam account for ABC Weighbridge is ready. We've mailed a verification code to your registered address; enter it within 30 days to keep your account active.", rows: [["Company", "ABC Weighbridge"], ["Address verification", "30-day window"]], note: `Questions? Reach us at ${S}.` })],
    ["Tulanam: your pro plan is active", "notification", false,
      n({ heading: "Your plan is active", intro: "Your Tulanam license has been activated — you're all set to run your weighbridge operations.", rows: [["Plan", "pro"], ["Weighbridges", "Unlimited"], ["Valid until", "No expiry"]], note: "Manage your subscription anytime at tulanam.com." })],
    ["Tulanam: your subscription expires in 3 days", "notification", false,
      n({ accent: "warn", heading: "Your subscription is expiring", intro: "Your Tulanam subscription expires in 3 days. Renew to avoid interruption to weighbridge operations.", rows: [["Expires in", "3 days"]], ctaText: "Renew subscription", ctaUrl: "https://tulanam.com/billing", note: `Need help? Contact ${S}.` })],
    ["Tulanam: identity verification approved", "notification", false,
      n({ heading: "Identity verified", intro: "Hi Ravi, your identity has been verified on Tulanam. You're all set.", note: "Questions? Contact your Tulanam administrator." })],
    ["Tulanam: cloud backup failed", "notification", false,
      n({ accent: "warn", heading: "Your cloud backup failed", intro: "A scheduled Tulanam cloud backup did not complete. Your data is safe locally, but the off-site copy was not updated.", rows: [["Status", "Failed"], ["Reason", "GDrive: no access token"]], note: "Open Settings → Integrations to check your backup configuration." })],
    ["Tulanam: two-factor authentication disabled", "notification", false,
      n({ accent: "danger", heading: "Two-factor authentication disabled", intro: "Two-factor authentication was just disabled on your Tulanam account.", note: `If you did NOT disable 2FA, contact ${S} immediately.` })],
    ["Tulanam: weighbridge limit reached", "notification", false,
      n({ accent: "warn", heading: "You've reached your weighbridge limit", intro: "Your Tulanam plan allows 2 weighbridges and you've now reached that limit. Upgrade your plan to add more.", rows: [["Plan limit", "2"], ["In use", "2"]], ctaText: "Upgrade plan", ctaUrl: "https://tulanam.com/billing", note: `Need a higher limit? Contact ${S}.` })],
    ["Tulanam: weighment receipt RST-1042", "receipt", true,
      buildReceiptHtml({
        rst: "RST-1042", date: "10 Jun 2026, 14:32", status: "Completed",
        customer: { name: "Coal Traders Co", phone: "+91 98765 43210", address: "Market Yard, Pune 411037" },
        vehicle: "MH12AB1234", material: "Coal",
        net: "28,000", gross: { weight: "42,000", time: "14:30" }, tare: { weight: "14,000", time: "14:02" },
        operator: { name: "Ravi Kumar", shift: "A", weighbridge: "WB-1", port: "COM3", pc: "PC-01" },
        customFields: [{ k: "PO Number", v: "PO-99812" }, { k: "Driver", v: "Suresh Patil" }, { k: "Source", v: "Mine 4" }],
        cctv: { tare: [{ cam: "CAM-1 · Tare", ts: "14:02:11" }], gross: [{ cam: "CAM-1 · Gross", ts: "14:30:44" }] },
        company,
      }, { logoTileUri, barcodeDataUri })],
    ["Tulanam Report — Yesterday (148 weighments, 1,247 T)", "report", true,
      buildReportHtml({
        subtitle: "Yesterday · generated 10 Jun 2026", company,
        kpis: { weighments: "148", vehicles: "92", tonnage: "1,247" },
        hours: [0, 0, 0, 0, 0, 1, 3, 6, 11, 14, 16, 13, 9, 12, 15, 17, 14, 10, 6, 3, 1, 0, 0, 0].map((c) => ({ count: c })),
        hourLabels: ["12a", "4a", "8a", "12p", "4p", "8p", "12a"],
        materials: [{ name: "Coal", tonnes: 642 }, { name: "M-Sand", tonnes: 318 }, { name: "Gravel", tonnes: 171 }, { name: "Cement", tonnes: 84 }, { name: "Iron", tonnes: 32 }],
      }, { logoTileUri })],
  ];
}

(async () => {
  if (!fs.existsSync(CHROME)) { console.error("Chrome not found at", CHROME); process.exit(1); }
  const formats = await buildFormats();
  const browser = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox"] });
  const transporter = nodemailer.createTransport({ service: "gmail", auth: { user: env.GMAIL_EMAIL, pass: env.GMAIL_APP_PASSWORD } });

  let ok = 0;
  for (let i = 0; i < formats.length; i++) {
    const [subject, kind, wantPdf, html] = formats[i];
    try {
      const page = await browser.newPage();
      await page.setViewport({ width: 704, height: 900, deviceScaleFactor: 2 });
      await page.setContent(html, { waitUntil: "load", timeout: 20000 });
      await page.evaluate(() => Promise.race([document.fonts.ready, new Promise((r) => setTimeout(r, 3000))]));
      const el = await page.$(".wrap");
      const png = await el.screenshot({ type: "png" });
      const pdf = wantPdf ? await page.pdf({ format: "A4", printBackground: true }) : null;
      await page.close();

      const attachments = [{ filename: "email.png", content: png, cid: "render@tulanam" }];
      if (pdf) attachments.push({ filename: `${kind}.pdf`, content: pdf });
      await transporter.sendMail({
        from: `"Tulanam" <${env.GMAIL_EMAIL}>`, replyTo: S, to: TO,
        subject: `[NEW ${i + 1}/${formats.length}] ${subject}`,
        html: `<div style="margin:0;background:#eef2f7"><img src="cid:render@tulanam" alt="${subject}" style="display:block;width:100%;max-width:600px;border:0"></div>`,
        attachments,
      });
      ok++;
      console.log(`✓ ${i + 1}/${formats.length}  [${kind}]  ${subject}`);
    } catch (e) {
      console.log(`✗ ${i + 1}/${formats.length}  ${subject} — ${e.message}`);
    }
  }
  await browser.close();
  console.log(`\nDone: ${ok}/${formats.length} rendered + sent to ${TO}`);
})();
