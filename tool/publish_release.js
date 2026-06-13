#!/usr/bin/env node
/*
 * Publish a desktop release: upload the package zip to Firebase Storage and
 * update the `global/app_version` feed so installed apps auto-update.
 *
 * Auth (one-time): `gcloud auth application-default login`
 *   — or set GOOGLE_APPLICATION_CREDENTIALS to a service-account key that has
 *     Storage Object Admin + Cloud Datastore User on the project.
 *
 * Usage:
 *   node tool/publish_release.js <windows|macos|linux> <version> <zipPath> [--required]
 *
 *   --required  also sets minimumVersion = <version>, forcing every client to update.
 *
 * Reuses the firebase-admin already installed under functions/ (no extra install).
 */
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const BUCKET = 'tulanam.firebasestorage.app';

(async () => {
  const [platform, version, zipPath, ...flags] = process.argv.slice(2);
  if (!['windows', 'macos', 'linux'].includes(platform) || !version || !zipPath) {
    console.error('usage: node tool/publish_release.js <windows|macos|linux> <version> <zipPath> [--required]');
    process.exit(1);
  }
  if (!fs.existsSync(zipPath)) { console.error(`file not found: ${zipPath}`); process.exit(1); }

  admin.initializeApp({ storageBucket: BUCKET });
  const bucket = admin.storage().bucket();

  const buf = fs.readFileSync(zipPath);
  const sha256 = crypto.createHash('sha256').update(buf).digest('hex');
  const size = buf.length;
  const dest = `releases/${version}/${path.basename(zipPath)}`;

  console.log(`Uploading ${zipPath} (${(size / 1e6).toFixed(1)} MB) -> gs://${BUCKET}/${dest} ...`);
  await bucket.upload(zipPath, {
    destination: dest,
    metadata: { contentType: 'application/zip', cacheControl: 'public,max-age=300' },
  });

  // Prefer a clean public URL; fall back to a long-lived signed URL if the bucket
  // uses uniform access (object ACLs disabled).
  let url;
  try {
    await bucket.file(dest).makePublic();
    url = `https://storage.googleapis.com/${BUCKET}/${dest}`;
  } catch (e) {
    console.warn('makePublic failed (uniform bucket access?) -> using a signed URL.');
    const [signed] = await bucket.file(dest).getSignedUrl({ action: 'read', expires: '2099-01-01' });
    url = signed;
  }

  const update = {
    latestVersion: version,
    platforms: { [platform]: { url, sha256, size } }, // merge keeps other platforms
  };
  if (flags.includes('--required')) update.minimumVersion = version;

  await admin.firestore().doc('global/app_version').set(update, { merge: true });

  console.log('\nPublished:');
  console.log(`  platform : ${platform}`);
  console.log(`  version  : ${version}${flags.includes('--required') ? '   (REQUIRED — forces update)' : ''}`);
  console.log(`  url      : ${url}`);
  console.log(`  sha256   : ${sha256}`);
  console.log(`  size     : ${size}`);
  console.log('\nInstalled apps auto-update within ~6h (or instantly via Profile -> Check for updates).');
  process.exit(0);
})().catch((e) => { console.error('publish failed:', e); process.exit(1); });
