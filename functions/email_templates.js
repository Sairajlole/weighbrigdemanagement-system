// Server-side, data-driven email/document templates (receipt + report).
// Pure functions: (data, assets) -> HTML string. The same HTML is used for the
// inline body image (element screenshot of .wrap) and the PDF attachment
// (page.pdf at the printer page size). Rendered by functions/email_render.js.
//
// `assets` = { logoTileUri } (data: URI of the tiled logo for the background),
// plus a per-call `barcodeDataUri` (PDF417 PNG) for the receipt.
//
// Verified locally against the approved mockups in docs/email-mockups/.

const BRAND = { name: "tulanam", teal: "#0d9488" };
const FONT = "<link rel=preconnect href='https://fonts.googleapis.com'><link rel=preconnect href='https://fonts.gstatic.com' crossorigin><link href='https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap' rel=stylesheet>";

function esc(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[c]));
}
const has = (v) => v != null && String(v).trim() !== "";

const COMMON = `*{margin:0;padding:0;box-sizing:border-box}
body{font-family:"Inter",-apple-system,"Segoe UI",sans-serif;background:#eef2f7}
.wrap{padding:52px;background:#eef2f7}
.card{position:relative;border-radius:28px;overflow:hidden;border:1px solid #cdd7e3;background:#fff;box-shadow:0 0 50px -10px rgba(20,40,60,.16)}
.bg{position:absolute;inset:0;background:#0d9488;opacity:.07;-webkit-mask-repeat:repeat;mask-repeat:repeat;-webkit-mask-size:96px;mask-size:96px}
.inner{position:relative;z-index:1}
.head{display:flex;align-items:center;justify-content:space-between;padding:24px 32px;border-bottom:1px solid #eef2f6}
.wm{color:#0f172a;font-weight:800;font-size:25px;letter-spacing:2px}
.auto{font-size:9px;text-transform:uppercase;letter-spacing:1.5px;color:#64748b;border:1px solid #d7dee7;padding:5px 11px;border-radius:999px}
.company{padding:16px 32px;border-top:1px solid #eef2f6;background:#f8fafc}
.company .nm{color:#0f172a;font-size:13px;font-weight:700}
.company .dt{color:#64748b;font-size:11px;line-height:1.65;margin-top:3px}
.foot{padding:15px 32px;border-top:1px solid #eef2f6;display:flex;justify-content:space-between;align-items:center;color:#94a3b8;font-size:11px}
.foot a{color:#0d9488;text-decoration:none;font-weight:600}
.sec2{color:#94a3b8;font-size:11px;letter-spacing:2px;text-transform:uppercase;margin:24px 0 12px}`;

const PERSON = "<svg viewBox='0 0 40 42' fill='#8aa0b8'><circle cx='20' cy='14' r='8'/><path d='M5 42c0-9 7-13 15-13s15 4 15 13z'/></svg>";

function companyBand(c) {
  const bits = [c.gstin && `GSTIN ${esc(c.gstin)}`, c.pan && `PAN ${esc(c.pan)}`, c.address && esc(c.address)]
    .filter(Boolean).join(" &nbsp;·&nbsp; ");
  return `<div class=company><div class=nm>${esc(c.name || "")}</div><div class=dt>${bits}</div></div>`;
}
const FOOT = "<div class=foot><span>This is an automated message — please do not reply.</span>" +
  "<span><a>tulanam.com</a> &nbsp;·&nbsp; <a>support@tulanam.com</a></span></div>";

function shell({ css, pill, body, company, logoTileUri }) {
  const bgStyle = logoTileUri ? `style="-webkit-mask-image:url(${logoTileUri});mask-image:url(${logoTileUri})"` : "";
  return `<!doctype html><html><head><meta charset=utf-8>${FONT}<style>${COMMON}${css || ""}</style></head><body>
<div class=wrap><div class=card><div class=bg ${bgStyle}></div><div class=inner>
<div class=head><span class=wm>${BRAND.name}</span><span class=auto>${esc(pill)}</span></div>
${body}
${companyBand(company || {})} ${FOOT}</div></div></div></body></html>`;
}

// ── Receipt ──────────────────────────────────────────────────────────────────
function buildReceiptHtml(d, assets = {}) {
  const css = `
.body{padding:30px 32px}
.custcard{display:flex;gap:16px;align-items:stretch;background:linear-gradient(135deg,#f0fdfa,#f6fafc);border:1px solid rgba(13,148,136,.3);border-radius:18px;padding:16px}
.photo{width:96px;height:96px;border-radius:14px;background:linear-gradient(150deg,#d4e1ef,#aebfd2);display:flex;align-items:flex-end;justify-content:center;overflow:hidden;flex-shrink:0}
.photo svg{width:68px;height:68px}.photo img{width:100%;height:100%;object-fit:cover}
.custinfo{flex:1;min-width:0}
.clabel{color:#0d9488;font-size:10px;letter-spacing:2px;text-transform:uppercase;font-weight:700}
.cname{color:#0f172a;font-size:21px;font-weight:800;margin-top:3px}
.cmeta{color:#64748b;font-size:12px;line-height:1.65;margin-top:5px}
.rstbox{text-align:right;flex-shrink:0;display:flex;flex-direction:column;align-items:flex-end;justify-content:space-between}
.rl{color:#94a3b8;font-size:9px;letter-spacing:2px;text-transform:uppercase}
.rstbox b{color:#0f172a;font-size:24px;font-weight:800;line-height:1.1}
.rdate{color:#64748b;font-size:11px;margin-top:2px}
.stat{background:#0d9488;color:#fff;font-size:10px;font-weight:700;padding:4px 10px;border-radius:999px}
.vehrow{display:flex;align-items:center;gap:12px;margin:22px 0 2px}
.vl{color:#94a3b8;font-size:11px;text-transform:uppercase;letter-spacing:2px}
.vv{color:#0f172a;font-size:20px;font-weight:800}
.mchip{margin-left:auto;background:#f0fdfa;border:1px solid rgba(13,148,136,.4);color:#0d9488;font-size:12px;font-weight:600;padding:5px 12px;border-radius:999px}
.nlabel{color:#94a3b8;font-size:11px;text-transform:uppercase;letter-spacing:2px;margin-top:16px}
.net{display:flex;align-items:baseline;gap:9px;margin:5px 0 18px}
.net .n{font-size:54px;font-weight:800;line-height:1;letter-spacing:-1px;background:linear-gradient(180deg,#0d9488,#14b8a6);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.net .u{font-size:19px;color:#0d9488;font-weight:700}
.gt{display:flex;gap:14px}
.cell{flex:1;background:#f8fafc;border:1px solid #e2e8f0;border-radius:14px;padding:13px 16px}
.cell .l{color:#94a3b8;font-size:11px;text-transform:uppercase;letter-spacing:1.5px}
.cell .v{color:#0f172a;font-size:19px;font-weight:700;margin-top:4px}
.cell .t{color:#94a3b8;font-size:11px;margin-top:4px}
.oprow{display:flex;align-items:center;gap:13px;padding:13px 15px;border:1px solid #e2e8f0;border-radius:14px}
.opav{width:46px;height:46px;border-radius:50%;background:linear-gradient(150deg,#d4e1ef,#aebfd2);display:flex;align-items:flex-end;justify-content:center;overflow:hidden;flex-shrink:0}
.opav svg{width:36px;height:36px}.opav img{width:100%;height:100%;object-fit:cover}
.opname{color:#0f172a;font-size:16px;font-weight:700}
.opmeta{color:#64748b;font-size:12px;margin-top:3px}
.cflist{border:1px solid #e2e8f0;border-radius:14px;overflow:hidden}
.cfrow{display:flex;justify-content:space-between;align-items:center;padding:12px 16px;border-bottom:1px solid #eef2f6}
.cfrow:last-child{border-bottom:none}
.cfrow .k{color:#94a3b8;font-size:11px;text-transform:uppercase;letter-spacing:1px}
.cfrow .v{color:#0f172a;font-size:14px;font-weight:600}
.cctv2{display:flex;gap:14px}.col{flex:1}
.colh{color:#475569;font-size:12px;font-weight:700;margin-bottom:9px;text-align:center;text-transform:uppercase;letter-spacing:1px}
.frame{position:relative;aspect-ratio:16/9;border-radius:10px;overflow:hidden;background:linear-gradient(135deg,#243345,#0f1a26);display:flex;align-items:center;justify-content:center;margin-bottom:10px}
.frame img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.frame:before{content:"";position:absolute;inset:6px;border:1px solid rgba(255,255,255,.13);border-radius:6px}
.frame .t1{position:absolute;top:7px;left:9px;color:#cbd8e6;font-size:8px;letter-spacing:.5px;font-weight:600;z-index:1}
.frame .ts{position:absolute;bottom:7px;right:9px;color:#9fb3c8;font-size:9px;font-family:monospace;z-index:1}
.bc417{text-align:center;padding:6px 0}
.bc417 img{display:block;height:auto;max-width:100%;margin:0 auto}
.bc417 .bc{color:#475569;font-size:11px;font-weight:600;letter-spacing:3px;margin-top:10px}`;

  const cust = d.customer || {};
  const photo = cust.photo
    ? `<div class=photo><img src="${cust.photo}"></div>`
    : `<div class=photo>${PERSON}</div>`;
  const custMeta = [has(cust.phone) && esc(cust.phone), has(cust.address) && esc(cust.address)]
    .filter(Boolean).join("<br>");

  const op = d.operator || {};
  const opPhoto = op.photo ? `<div class=opav><img src="${op.photo}"></div>` : `<div class=opav>${PERSON}</div>`;
  const opMeta = [has(op.shift) && `Shift ${esc(op.shift)}`, has(op.weighbridge) && `Weighbridge ${esc(op.weighbridge)}`,
    has(op.port) && `Port ${esc(op.port)}`, has(op.pc) && `PC ${esc(op.pc)}`].filter(Boolean).join(" &nbsp;·&nbsp; ");

  const cf = Array.isArray(d.customFields) ? d.customFields.filter((f) => has(f.k) && has(f.v)) : [];
  const cfHtml = cf.length ? `<div class=sec2>Custom fields</div><div class=cflist>${
    cf.map((f) => `<div class=cfrow><span class=k>${esc(f.k)}</span><span class=v>${esc(f.v)}</span></div>`).join("")}</div>` : "";

  // CCTV — render only present snapshots; up to 3 per column.
  const frame = (s) => `<div class=frame>${s.img ? `<img src="${s.img}">` : ""}` +
    `${has(s.cam) ? `<span class=t1>${esc(s.cam)}</span>` : ""}${has(s.ts) ? `<span class=ts>${esc(s.ts)}</span>` : ""}</div>`;
  const tare = (d.cctv && d.cctv.tare || []).slice(0, 3);
  const gross = (d.cctv && d.cctv.gross || []).slice(0, 3);
  const cctvHtml = (tare.length || gross.length) ? `<div class=sec2>CCTV snapshots</div><div class=cctv2>
    <div class=col><div class=colh>Tare</div>${tare.map(frame).join("")}</div>
    <div class=col><div class=colh>Gross</div>${gross.map(frame).join("")}</div></div>` : "";

  const barcode = assets.barcodeDataUri
    ? `<div class=sec2>Ticket barcode · PDF417</div><div class=bc417><img src="${assets.barcodeDataUri}"><div class=bc>${esc(d.rst)}</div></div>`
    : "";

  const body = `<div class=body>
<div class=custcard>${photo}
 <div class=custinfo><div class=clabel>Customer</div><div class=cname>${esc(cust.name || "")}</div><div class=cmeta>${custMeta}</div></div>
 <div class=rstbox><div><span class=rl>RST No.</span><br><b>${esc(d.rst)}</b>${has(d.date) ? `<div class=rdate>${esc(d.date)}</div>` : ""}</div>${has(d.status) ? `<span class=stat>● ${esc(d.status)}</span>` : ""}</div></div>
${has(d.vehicle) ? `<div class=vehrow><span class=vl>Vehicle</span><span class=vv>${esc(d.vehicle)}</span>${has(d.material) ? `<span class=mchip>● ${esc(d.material)}</span>` : ""}</div>` : ""}
${has(d.net) ? `<div class=nlabel>Net weight</div><div class=net><span class=n>${esc(d.net)}</span><span class=u>kg</span></div>` : ""}
<div class=gt>
 <div class=cell><div class=l>Gross</div><div class=v>${esc(d.gross && d.gross.weight || "—")} kg</div>${has(d.gross && d.gross.time) ? `<div class=t>${esc(d.gross.time)}</div>` : ""}</div>
 <div class=cell><div class=l>Tare</div><div class=v>${esc(d.tare && d.tare.weight || "—")} kg</div>${has(d.tare && d.tare.time) ? `<div class=t>${esc(d.tare.time)}</div>` : ""}</div></div>
<div class=sec2>Operator</div>
<div class=oprow>${opPhoto}<div><div class=opname>${esc(op.name || "—")}</div>${opMeta ? `<div class=opmeta>${opMeta}</div>` : ""}</div></div>
${cfHtml}
${cctvHtml}
${barcode}
</div>`;

  return shell({ css, pill: "Weighment ticket", body, company: d.company || {}, logoTileUri: assets.logoTileUri });
}

// ── Daily report ─────────────────────────────────────────────────────────────
function buildReportHtml(d, assets = {}) {
  const css = `
.body{padding:30px 32px}
.title{color:#0f172a;font-size:23px;font-weight:800;letter-spacing:-.4px}
.tt{color:#94a3b8;font-size:12px;margin:5px 0 22px}
.kpis{display:flex;gap:14px;margin-bottom:30px}
.kpi{flex:1;border-radius:18px;padding:20px;background:#f8fafc;border:1px solid #e2e8f0}
.kpi .l{color:#94a3b8;font-size:11px;text-transform:uppercase;letter-spacing:1.5px}
.kpi .v{color:#0f172a;font-size:34px;font-weight:800;margin-top:8px;letter-spacing:-1px}
.kpi .v small{font-size:16px;color:#0d9488;font-weight:700;margin-left:4px}
.kpi.accent{background:linear-gradient(160deg,#f0fdfa,#e6fbf6);border-color:rgba(13,148,136,.35)}.kpi.accent .v{color:#0d9488}
.sec{color:#94a3b8;font-size:12px;letter-spacing:2px;text-transform:uppercase;margin-bottom:15px}
.panel{border:1px solid #e2e8f0;border-radius:16px;padding:18px 18px 12px;margin-bottom:26px}
.hours{display:flex;align-items:flex-end;gap:5px;height:120px}
.hbar{flex:1;display:flex;align-items:flex-end;height:100%}
.hbar span{display:block;width:100%;border-radius:4px 4px 0 0;background:linear-gradient(180deg,#14b8a6,#0d9488)}
.hlabels{display:flex;justify-content:space-between;color:#94a3b8;font-size:9px;margin-top:9px}
.bar{display:flex;align-items:center;gap:14px;margin-bottom:14px}
.bar .name{width:86px;color:#334155;font-size:13px;font-weight:600}
.bar .track{flex:1;height:13px;border-radius:999px;background:#eef2f6;overflow:hidden}
.bar .fill{display:block;height:100%;border-radius:999px;background:linear-gradient(90deg,#0d9488,#14b8a6)}
.bar .val{width:60px;text-align:right;color:#0f172a;font-size:13px;font-weight:700}`;

  const hours = Array.isArray(d.hours) ? d.hours : [];
  const hmax = Math.max(1, ...hours.map((h) => h.count || 0));
  const hoursHtml = hours.length ? `<div class=sec>Weighments by hour</div><div class=panel><div class=hours>${
    hours.map((h) => `<div class=hbar><span style="height:${Math.round((h.count || 0) / hmax * 100)}%"></span></div>`).join("")
  }</div><div class=hlabels>${(d.hourLabels || []).map((l) => `<span>${esc(l)}</span>`).join("")}</div></div>` : "";

  const mats = Array.isArray(d.materials) ? d.materials : [];
  const mmax = Math.max(1, ...mats.map((m) => m.tonnes || 0));
  const matsHtml = mats.length ? `<div class=sec>Top materials</div>${
    mats.map((m) => `<div class=bar><span class=name>${esc(m.name)}</span><span class=track><span class=fill style="width:${Math.round((m.tonnes || 0) / mmax * 100)}%"></span></span><span class=val>${esc(m.tonnes)} T</span></div>`).join("")
  }` : "";

  const k = d.kpis || {};
  const body = `<div class=body>
<div class=title>Weighment report</div>
<div class=tt>${esc(d.subtitle || "")}</div>
<div class=kpis>
 <div class=kpi><div class=l>Weighments</div><div class=v>${esc(k.weighments)}</div></div>
 <div class=kpi><div class=l>Vehicles</div><div class=v>${esc(k.vehicles)}</div></div>
 <div class="kpi accent"><div class=l>Net tonnage</div><div class=v>${esc(k.tonnage)}<small>T</small></div></div></div>
${hoursHtml}
${matsHtml}
</div>`;

  return shell({ css, pill: "Daily report", body, company: d.company || {}, logoTileUri: assets.logoTileUri });
}

// ── OTP (verification / password reset) ──────────────────────────────────────
function buildOtpHtml(d, assets = {}) {
  const css = `
.body{padding:40px 32px}
.eyebrow{color:#94a3b8;font-size:12px;letter-spacing:3px;text-transform:uppercase;margin-bottom:11px}
h1{color:#0f172a;font-size:27px;font-weight:800;letter-spacing:-.5px;margin-bottom:9px}
.sub{color:#64748b;font-size:14px;line-height:1.55;margin-bottom:30px}
.codecard{border-radius:22px;padding:30px;text-align:center;background:#f0fdfa;border:1px solid rgba(13,148,136,.35)}
.codelabel{color:#0d9488;font-size:11px;letter-spacing:3px;text-transform:uppercase;margin-bottom:16px}
.code{font-weight:800;font-size:54px;letter-spacing:14px;text-indent:14px;background:linear-gradient(180deg,#0d9488,#14b8a6);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.timer{display:inline-flex;align-items:center;gap:9px;margin-top:20px;color:#64748b;font-size:12px}
.dot{width:7px;height:7px;border-radius:50%;background:#0d9488}
.note{margin-top:26px;color:#64748b;font-size:12px;line-height:1.6;border-left:2px solid rgba(13,148,136,.4);padding-left:14px}`;
  const body = `<div class=body>
<div class=eyebrow>${esc(d.eyebrow || "Verification")}</div><h1>${esc(d.heading)}</h1>
<div class=sub>${esc(d.intro)}</div>
<div class=codecard><div class=codelabel>Verification code</div><div class=code>${esc(d.otp)}</div>
<div class=timer><span class=dot></span>${esc(d.expiry || "Expires in 10 minutes · one-time use")}</div></div>
<div class=note>${esc(d.securityNote || "")}</div></div>`;
  return shell({ css, pill: d.pill || "Automated", body, company: d.company || {}, logoTileUri: assets.logoTileUri });
}

// ── Generic notification (welcome, licence, security alert, KYC, …) ──────────
function buildNotificationHtml(d, assets = {}) {
  const accent = d.accent;
  const chipColor = accent === "danger" ? "#dc2626" : accent === "warn" ? "#d97706" : "#0d9488";
  const css = `
.body{padding:34px 32px}
.chip{display:inline-block;color:#fff;font-size:10px;font-weight:700;letter-spacing:1px;text-transform:uppercase;padding:4px 10px;border-radius:4px;margin-bottom:14px}
h1{color:#0f172a;font-size:24px;font-weight:800;letter-spacing:-.4px;margin-bottom:9px}
.intro{color:#64748b;font-size:14px;line-height:1.55;margin-bottom:20px}
.rows{border:1px solid #e2e8f0;border-radius:14px;overflow:hidden;margin-bottom:20px}
.rw{display:flex;justify-content:space-between;padding:12px 16px;border-bottom:1px solid #eef2f6}
.rw:last-child{border-bottom:none}
.rw .k{color:#94a3b8;font-size:12px}.rw .v{color:#0f172a;font-size:13px;font-weight:600}
.callout{background:#f0fdfa;border:1px solid rgba(13,148,136,.3);border-radius:14px;padding:16px 18px;margin-bottom:20px}
.callout .ct{color:#0d9488;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:1px}
.callout .cx{color:#0f172a;font-size:13px;line-height:1.55;margin-top:5px}
.cta{display:inline-block;background:#0d9488;color:#fff;font-size:14px;font-weight:600;text-decoration:none;padding:11px 22px;border-radius:8px;margin-bottom:16px}
.note{color:#64748b;font-size:12px;line-height:1.55}`;
  const rows = Array.isArray(d.rows) ? d.rows.filter((r) => Array.isArray(r) && r.length === 2) : [];
  const callout = d.callout && d.callout.text
    ? `<div class=callout>${d.callout.title ? `<div class=ct>${esc(d.callout.title)}</div>` : ""}<div class=cx>${esc(d.callout.text)}</div></div>`
    : "";
  const body = `<div class=body>
${accent ? `<div class=chip style="background:${chipColor}">${accent === "danger" ? "Security alert" : "Action required"}</div>` : ""}
<h1>${esc(d.heading)}</h1>
${d.intro ? `<div class=intro>${esc(d.intro)}</div>` : ""}
${callout}
${rows.length ? `<div class=rows>${rows.map(([k, v]) => `<div class=rw><span class=k>${esc(k)}</span><span class=v>${esc(v)}</span></div>`).join("")}</div>` : ""}
${d.ctaText && d.ctaUrl ? `<a class=cta href="${esc(d.ctaUrl)}">${esc(d.ctaText)}</a>` : ""}
${d.note ? `<div class=note>${esc(d.note)}</div>` : ""}</div>`;
  return shell({ css, pill: d.pill || (accent === "danger" ? "Security alert" : "Automated"), body, company: d.company || {}, logoTileUri: assets.logoTileUri });
}

module.exports = { buildReceiptHtml, buildReportHtml, buildOtpHtml, buildNotificationHtml };
