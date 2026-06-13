// Firebase-native release publishing.
//
// Drop a desktop package at  releases/{version}/{file}.zip  in Cloud Storage
// (via CI, gsutil, the console, or tool/publish_release.js) and this trigger
// computes its sha256 + size and writes global/app_version.platforms.{os} — so
// installed apps auto-update. No manual feed editing.
//
// Platform is inferred from the filename: "win" -> windows, "mac"/"osx"/"darwin"
// -> macos, "linux" -> linux.
const { onObjectFinalized } = require("firebase-functions/v2/storage");
const admin = require("firebase-admin");
const crypto = require("crypto");

if (!admin.apps.length) admin.initializeApp();

exports.onReleaseUploaded = onObjectFinalized({ region: "asia-south1", memory: "512MiB", timeoutSeconds: 300 }, async (event) => {
  const obj = event.data;
  const name = obj.name || "";
  const m = name.match(/^releases\/([^/]+)\/(.+\.zip)$/i);
  if (!m) return; // not a release object
  const version = m[1];
  const file = m[2].toLowerCase();

  let platform;
  if (file.includes("win")) platform = "windows";
  else if (file.includes("mac") || file.includes("osx") || file.includes("darwin")) platform = "macos";
  else if (file.includes("linux")) platform = "linux";
  else { console.warn(`onReleaseUploaded: can't infer platform from "${name}"`); return; }

  const bucket = admin.storage().bucket(obj.bucket);
  const fileRef = bucket.file(name);

  // Stream through sha256 so large packages don't blow memory.
  const hash = crypto.createHash("sha256");
  await new Promise((resolve, reject) => {
    fileRef.createReadStream()
      .on("data", (d) => hash.update(d))
      .on("end", resolve)
      .on("error", reject);
  });
  const sha256 = hash.digest("hex");
  const size = Number(obj.size || 0);

  // Clean public URL; fall back to a long-lived signed URL on uniform-access buckets.
  let url;
  try {
    await fileRef.makePublic();
    url = `https://storage.googleapis.com/${obj.bucket}/${name.split("/").map(encodeURIComponent).join("/")}`;
  } catch (e) {
    const [signed] = await fileRef.getSignedUrl({ action: "read", expires: "2099-01-01" });
    url = signed;
  }

  await admin.firestore().doc("global/app_version").set({
    latestVersion: version,
    platforms: { [platform]: { url, sha256, size } },
  }, { merge: true });

  console.log(`onReleaseUploaded: published ${platform} v${version} (${size} bytes, sha256 ${sha256.slice(0, 12)}…)`);
});
