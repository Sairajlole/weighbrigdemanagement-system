// Gen-2 (Cloud Run-backed) email document renderer.
//
// Isolated from index.js so Chromium's weight never taxes the cold start of the
// gen-1 OTP/notification functions. Chromium + Puppeteer are required LAZILY
// inside the handler, so merely importing this file (to re-export the function
// from index.js) stays lightweight — only THIS function's own instances load
// the browser, and only when invoked.
//
// Renders an email document HTML (functions/email_templates.js) to:
//   • a PNG  → uploaded to Storage, returned as a signed URL  (inline body image)
//   • a PDF  → returned base64                                (email attachment)
// The PDF page size mirrors the company's normal-printer paperSize (A4/A5/…).

const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const bwipjs = require("bwip-js");
const { buildReceiptHtml, buildReportHtml, buildOtpHtml, buildNotificationHtml } = require("./email_templates");

if (!admin.apps.length) admin.initializeApp();

/* global document */ // used inside page.evaluate() (runs in the browser context)

const BUCKET = "tulanam.firebasestorage.app";
const RENDER_SECRET = process.env.RENDER_SECRET || "";

let _logoTileUri;
function logoTileUri() {
  if (_logoTileUri !== undefined) return _logoTileUri;
  try {
    _logoTileUri = `data:image/png;base64,${fs.readFileSync(path.join(__dirname, "assets/logo_tile.png")).toString("base64")}`;
  } catch (e) {
    console.warn("logo_tile asset missing:", e.message);
    _logoTileUri = "";
  }
  return _logoTileUri;
}

async function pdf417DataUri(text) {
  try {
    const png = await bwipjs.toBuffer({ bcid: "pdf417", text, columns: 10, scale: 3, backgroundcolor: "FFFFFF", paddingwidth: 2, paddingheight: 2 });
    return `data:image/png;base64,${png.toString("base64")}`;
  } catch (e) {
    console.warn("pdf417 generation failed:", e.message);
    return "";
  }
}

const ALLOWED_SIZES = ["A4", "A5", "Letter", "Legal"];

exports.renderEmailDoc = onRequest({ region: "asia-south1", memory: "1GiB", timeoutSeconds: 120, concurrency: 1 }, async (req, res) => {
  let browser;
  try {
    // Public (allUsers) endpoint — the secret is the only gate, so fail CLOSED:
    // an unset/empty RENDER_SECRET rejects everything rather than opening up.
    const provided = req.get("x-render-secret") || "";
    const okSecret = RENDER_SECRET.length > 0 &&
      provided.length === RENDER_SECRET.length &&
      crypto.timingSafeEqual(Buffer.from(provided), Buffer.from(RENDER_SECRET));
    if (!okSecret) {
      res.status(403).send("forbidden");
      return;
    }
    const { kind, data, pageSize } = req.body || {};
    if (!kind || !data) {
      res.status(400).send("kind and data required");
      return;
    }

    const assets = { logoTileUri: logoTileUri() };
    let html;
    if (kind === "receipt") {
      assets.barcodeDataUri = data.rst
        ? await pdf417DataUri(`TULANAM|RST:${data.rst}|${data.vehicle || ""}|NET:${data.net || ""}`)
        : "";
      html = buildReceiptHtml(data, assets);
    } else if (kind === "report") {
      html = buildReportHtml(data, assets);
    } else if (kind === "otp") {
      html = buildOtpHtml(data, assets);
    } else if (kind === "notification") {
      html = buildNotificationHtml(data, assets);
    } else {
      res.status(400).send("unknown kind");
      return;
    }
    const wantPdf = kind === "receipt" || kind === "report"; // documents get a PDF attachment

    // Lazy-load the browser only here (keeps import cheap for index.js re-export).
    const chromium = require("@sparticuz/chromium");
    const puppeteer = require("puppeteer-core");
    browser = await puppeteer.launch({
      args: chromium.args,
      executablePath: await chromium.executablePath(),
      headless: chromium.headless,
    });
    const page = await browser.newPage();
    page.setDefaultTimeout(25000);
    await page.setViewport({ width: 704, height: 900, deviceScaleFactor: 2 });
    await page.setContent(html, { waitUntil: "load", timeout: 20000 });
    // Bound the font wait — a slow/hung Google Fonts fetch must not deadlock the
    // render (networkidle0 would). Worst case we render with the fallback stack.
    await page.evaluate(() => Promise.race([document.fonts.ready, new Promise((r) => setTimeout(r, 3000))]));

    const el = await page.$(".wrap");
    const pngBuf = await el.screenshot({ type: "png" });               // inline body image
    let pdfBase64 = null;
    if (wantPdf) {
      const fmt = ALLOWED_SIZES.includes(pageSize) ? pageSize : "A4";
      pdfBase64 = (await page.pdf({ format: fmt, printBackground: true })).toString("base64"); // attachment
    }

    await browser.close();
    browser = null;

    // Upload PNG → time-limited signed URL for the email <img>.
    const bucket = admin.storage().bucket(BUCKET);
    const pngPath = `email_renders/${kind}_${Date.now()}.png`;
    const file = bucket.file(pngPath);
    await file.save(pngBuf, { contentType: "image/png", metadata: { cacheControl: "private,max-age=2592000" } });
    const [imageUrl] = await file.getSignedUrl({ action: "read", expires: Date.now() + 30 * 24 * 60 * 60 * 1000 });

    res.json({ imageUrl, pdfBase64 });
  } catch (e) {
    console.error("renderEmailDoc failed:", e);
    try { if (browser) await browser.close(); } catch (_) { /* ignore */ }
    res.status(500).json({ error: String((e && e.message) || e) });
  }
});
