#!/usr/bin/env node
'use strict';

/**
 * create_workspace_user.js — Tulanam Google Workspace user provisioning CLI.
 *
 * Creates a new Workspace user under tulanam.com and sets their Google account
 * profile photo to the brand avatar. The photo is auto-applied to EVERY user
 * created through this script — and only through this script (there is no
 * domain-wide trigger; scoping lives here).
 *
 * Auth: gcloud Application Default Credentials (ADC), run as the super-admin.
 * One-time setup (the default gcloud login does NOT carry the directory scope):
 *
 *   gcloud auth application-default login \
 *     --scopes=openid,\
 * https://www.googleapis.com/auth/cloud-platform,\
 * https://www.googleapis.com/auth/admin.directory.user
 *
 * Then run as tech@tulanam.com (a Workspace super admin).
 *
 * Usage:
 *   node tool/create_workspace_user.js <email> "<Full Name>" [options]
 *
 * Options:
 *   --password <pw>        Initial password (default: random, printed once)
 *   --given <name>         Override given name (else parsed from Full Name)
 *   --family <name>        Override family name (else parsed from Full Name)
 *   --photo <path>         Avatar file (default: brand/tulanam_avatar_light_1024.png)
 *   --quota-project <id>   ADC quota/billing project (default: from ADC, else tulanam)
 *   --no-photo             Create the user but skip the photo
 *   --photo-only           Skip creation; only (re)set the photo on an existing user
 *   --no-force-pw-change   Don't require a password change at next login
 *   --dry-run              Show what would happen; make no changes, hit no API
 *   --check                Read-only: GET <email> to confirm the token + scope work
 *                          (run this once after ADC setup, before creating anyone)
 *   -h, --help             Show this help
 *
 * Examples:
 *   node tool/create_workspace_user.js priya@tulanam.com "Priya Sharma"
 *   node tool/create_workspace_user.js ops@tulanam.com "Ops Desk" --photo brand/tulanam_avatar_dark_1024.png
 *   node tool/create_workspace_user.js priya@tulanam.com "Priya Sharma" --photo-only
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const ADMIN_BASE = 'https://admin.googleapis.com/admin/directory/v1';
const DIRECTORY_SCOPE = 'https://www.googleapis.com/auth/admin.directory.user';
const REPO_ROOT = path.resolve(__dirname, '..');
const DEFAULT_PHOTO = path.join(REPO_ROOT, 'brand', 'tulanam_avatar_light_1024.png');
const EXPECTED_DOMAIN = 'tulanam.com';
const DEFAULT_PROJECT = 'tulanam';

// User-credential ADC requires a quota project, sent as X-Goog-User-Project.
// Resolved in main(); the Google client libraries do this automatically, but
// our raw REST calls have to forward it ourselves.
let QUOTA_PROJECT = null;

function fail(msg) {
  console.error(`\n✖ ${msg}\n`);
  process.exit(1);
}

function printHelp() {
  // Print the leading block comment as help text.
  const src = fs.readFileSync(__filename, 'utf8');
  const block = src.slice(src.indexOf('/**'), src.indexOf('*/') + 2);
  console.log(block.replace(/^\/\*\*?/, '').replace(/\*\/$/, '').replace(/^ \* ?/gm, '').trim());
}

function parseArgs(argv) {
  const opts = {
    photo: DEFAULT_PHOTO,
    setPhoto: true,
    createUser: true,
    forcePwChange: true,
    dryRun: false,
  };
  const positional = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case '-h': case '--help': printHelp(); process.exit(0); break;
      case '--password': opts.password = argv[++i]; break;
      case '--given': opts.given = argv[++i]; break;
      case '--family': opts.family = argv[++i]; break;
      case '--photo': opts.photo = path.resolve(process.cwd(), argv[++i]); break;
      case '--quota-project': opts.quotaProject = argv[++i]; break;
      case '--no-photo': opts.setPhoto = false; break;
      case '--photo-only': opts.createUser = false; break;
      case '--no-force-pw-change': opts.forcePwChange = false; break;
      case '--dry-run': opts.dryRun = true; break;
      case '--check': opts.check = true; break;
      default:
        if (a.startsWith('--')) fail(`Unknown option: ${a}  (try --help)`);
        positional.push(a);
    }
  }
  opts.email = positional[0];
  opts.fullName = positional[1];
  return opts;
}

function splitName(fullName, given, family) {
  if (given || family) return { givenName: given || '-', familyName: family || '-' };
  const parts = (fullName || '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return null;
  if (parts.length === 1) return { givenName: parts[0], familyName: '-' };
  return { givenName: parts[0], familyName: parts.slice(1).join(' ') };
}

function genPassword() {
  // 20 url-safe random chars, plus a guaranteed upper/lower/digit/symbol so it
  // always satisfies the Workspace password policy.
  const raw = crypto.randomBytes(24).toString('base64url').replace(/[-_]/g, '');
  return `${raw.slice(0, 18)}aA7!`;
}

// Google's UserPhoto.photoData wants URL-safe Base64 (+ -> -, / -> _), padding
// retained — the exact encoding GAM uses in production, and what the live API
// accepts today. FALLBACK: if the photo PUT ever returns HTTP 400, the encoding
// is suspect #1 — older Google docs specified a quirkier variant (= -> *, and
// '.' for padding). Try that map before assuming the image itself is bad.
function webSafeBase64(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_');
}

function getAccessToken() {
  let token;
  try {
    token = execFileSync('gcloud', ['auth', 'application-default', 'print-access-token'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
  } catch (e) {
    fail(
      'Could not get an access token from gcloud ADC.\n  ' +
      'Run the one-time setup as a Workspace super admin (tech@tulanam.com):\n\n  ' +
      'gcloud auth application-default login \\\n    ' +
      '--scopes=openid,https://www.googleapis.com/auth/cloud-platform,' + DIRECTORY_SCOPE +
      '\n\n  Original error: ' + (e.stderr || e.message || e).toString().trim()
    );
  }
  if (!token) fail('gcloud returned an empty access token.');
  return token;
}

function resolveQuotaProject(explicit) {
  if (explicit) return explicit;
  if (process.env.GOOGLE_CLOUD_QUOTA_PROJECT) return process.env.GOOGLE_CLOUD_QUOTA_PROJECT;
  // Read quota_project_id straight from the ADC file gcloud wrote.
  try {
    const adcPath = process.env.GOOGLE_APPLICATION_CREDENTIALS ||
      path.join(os.homedir(), '.config', 'gcloud', 'application_default_credentials.json');
    if (fs.existsSync(adcPath)) {
      const adc = JSON.parse(fs.readFileSync(adcPath, 'utf8'));
      if (adc.quota_project_id) return adc.quota_project_id;
    }
  } catch { /* fall through */ }
  try {
    const p = execFileSync('gcloud', ['config', 'get-value', 'project'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    if (p && p !== '(unset)') return p;
  } catch { /* fall through */ }
  return DEFAULT_PROJECT;
}

async function api(token, method, urlPath, body) {
  const headers = {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  };
  if (QUOTA_PROJECT) headers['X-Goog-User-Project'] = QUOTA_PROJECT;
  const res = await fetch(`${ADMIN_BASE}${urlPath}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
  return { ok: res.ok, status: res.status, json };
}

function apiError(label, r) {
  const e = r.json && r.json.error;
  const detail = e ? `${e.code} ${e.message}` : `HTTP ${r.status}`;
  const msg = (e && e.message) || '';
  const hint = (() => {
    if (/quota project/i.test(msg)) {
      return `\n  → No quota project on the request. Set one with --quota-project <id>, ` +
        `GOOGLE_CLOUD_QUOTA_PROJECT, or:\n  gcloud auth application-default set-quota-project ${DEFAULT_PROJECT}`;
    }
    if (/has not been used in project|is disabled|SERVICE_DISABLED|accessNotConfigured/i.test(msg)) {
      return `\n  → The Admin SDK API isn't enabled on the quota project. Enable it:\n  ` +
        `gcloud services enable admin.googleapis.com --project ${QUOTA_PROJECT || DEFAULT_PROJECT}`;
    }
    if (r.status === 401 || r.status === 403) {
      return `\n  → The token is missing the directory scope or the account isn't a super admin. Re-run:\n  ` +
        `gcloud auth application-default login ` +
        `--scopes=openid,https://www.googleapis.com/auth/cloud-platform,${DIRECTORY_SCOPE}`;
    }
    return '';
  })();
  return `${label} failed: ${detail}${hint}`;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (!opts.email) fail('Missing <email>. Try --help.');
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(opts.email)) fail(`Not a valid email: ${opts.email}`);

  QUOTA_PROJECT = resolveQuotaProject(opts.quotaProject);

  // Read-only auth smoke test — confirms the token carries the directory scope
  // and the account can read the directory, before any mutating call is made.
  if (opts.check) {
    const token = getAccessToken();
    const r = await api(token, 'GET', `/users/${encodeURIComponent(opts.email)}`);
    if (r.ok) {
      console.log(`✓ Auth OK — read ${opts.email} (${r.json.name && r.json.name.fullName || 'no name'}, ` +
        `admin=${r.json.isAdmin === true}). Token + directory scope work.`);
      return;
    }
    if (r.status === 404) {
      console.log(`✓ Auth OK — token + directory scope work (no user ${opts.email} yet; 404 is expected).`);
      return;
    }
    fail(apiError('Auth check', r));
  }

  if (!opts.email.toLowerCase().endsWith('@' + EXPECTED_DOMAIN)) {
    console.warn(`⚠  ${opts.email} is not on @${EXPECTED_DOMAIN} — continuing anyway.`);
  }

  // Resolve the photo up front so we fail fast on a bad path.
  let photoBuf = null;
  if (opts.setPhoto) {
    if (!fs.existsSync(opts.photo)) fail(`Photo not found: ${opts.photo}`);
    photoBuf = fs.readFileSync(opts.photo);
    if (photoBuf.length > 10 * 1024 * 1024) fail('Photo exceeds 10 MB.');
  }

  let name = null;
  if (opts.createUser) {
    name = splitName(opts.fullName, opts.given, opts.family);
    if (!name) fail('Missing "<Full Name>" (or pass --given/--family). Try --help.');
  }

  const password = opts.password || genPassword();
  const generatedPw = !opts.password;

  console.log(`\nTulanam · Workspace user provisioning`);
  console.log(`  user:   ${opts.email}`);
  if (opts.createUser) console.log(`  name:   ${name.givenName} / ${name.familyName}`);
  if (opts.setPhoto) console.log(`  photo:  ${path.relative(REPO_ROOT, opts.photo)} (${photoBuf.length} bytes)`);
  console.log(`  mode:   ${opts.createUser ? 'create' : 'photo-only'}${opts.dryRun ? ' · DRY RUN' : ''}\n`);

  if (opts.dryRun) {
    if (opts.createUser) {
      console.log('Would POST /users with:');
      console.log(JSON.stringify({
        primaryEmail: opts.email,
        name,
        password: generatedPw ? '<generated>' : '<provided>',
        changePasswordAtNextLogin: opts.forcePwChange,
      }, null, 2));
    }
    if (opts.setPhoto) {
      const encoded = webSafeBase64(photoBuf);
      console.log(`\nWould PUT /users/${opts.email}/photos/thumbnail`);
      console.log(`  photoData: ${encoded.length} url-safe-base64 chars`);
    }
    console.log('\nDry run — no changes made.');
    return;
  }

  const token = getAccessToken();

  // 1) Create the user (idempotent: a pre-existing user is treated as success).
  if (opts.createUser) {
    const r = await api(token, 'POST', '/users', {
      primaryEmail: opts.email,
      name,
      password,
      changePasswordAtNextLogin: opts.forcePwChange,
    });
    if (r.ok) {
      console.log(`✓ Created user ${opts.email}`);
      if (generatedPw) {
        console.log(`\n  ┌─ Temporary password (shown once) ───────────────`);
        console.log(`  │  ${password}`);
        console.log(`  └─ User must change it at first sign-in.\n`);
      }
    } else if (r.status === 409 || (r.json.error && /already exists|entityExists|duplicate/i.test(r.json.error.message || ''))) {
      console.log(`• User ${opts.email} already exists — leaving the account as-is, updating the photo.`);
    } else {
      fail(apiError('Create user', r));
    }
  }

  // 2) Set the brand profile photo.
  if (opts.setPhoto) {
    const r = await api(token, 'PUT', `/users/${encodeURIComponent(opts.email)}/photos/thumbnail`, {
      photoData: webSafeBase64(photoBuf),
    });
    if (!r.ok) fail(apiError('Set photo', r));
    console.log(`✓ Uploaded profile photo`);

    // 3) Read it back so a silent failure can't masquerade as success.
    const v = await api(token, 'GET', `/users/${encodeURIComponent(opts.email)}/photos/thumbnail`);
    if (v.ok && v.json.photoData) {
      const dims = v.json.width && v.json.height ? ` (${v.json.width}×${v.json.height}, ${v.json.mimeType || 'image'})` : '';
      console.log(`✓ Verified photo is set${dims}`);
    } else {
      console.warn(`⚠  Upload returned ${r.status} but read-back didn't confirm a photo — check the Admin console.`);
    }
  }

  console.log(`\nDone.\n`);
}

main().catch((e) => fail(e && e.stack ? e.stack : String(e)));
