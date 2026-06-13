const functions = require("firebase-functions");
// All gen-1 triggers run in asia-south1 (Mumbai), co-located with Firestore.
// (functions.https.HttpsError / functions.config / functions.logger stay on the
// base import — only the trigger BUILDERS use this regional one.)
const fns = functions.region("asia-south1");
const admin = require("firebase-admin");

// functions.config() THROWS in the gen-2 runtime (it's removed there) and is
// deprecated everywhere. index.js is the shared entry for the gen-2 renderEmailDoc
// container too, so any module-scope functions.config() call crashes its startup.
// Guard every read: real config when available (gen-1), {} otherwise, so callers
// fall through to their process.env fallbacks.
function _fnConfig() {
  try {
    return functions.config() || {};
  } catch (_) {
    return {};
  }
}

admin.initializeApp();
const db = admin.firestore();
const bucket = admin.storage().bucket("tulanam.firebasestorage.app");

// ─── Operator Created: Set defaults ─────────────────────────────────────────

exports.onOperatorCreated = fns.firestore
  .document("companies/{companyId}/operators/{operatorId}")
  .onCreate(async (snap, context) => {
    const { companyId } = context.params;
    const data = snap.data();
    const defaults = {};

    if (!data.createdAt) defaults.createdAt = admin.firestore.FieldValue.serverTimestamp();
    if (!data.isActive) defaults.isActive = true;
    if (!data.isVerified) defaults.isVerified = false;
    if (!data.idStatus) defaults.idStatus = "not_submitted";
    if (!data.loginCount) defaults.loginCount = 0;
    if (data.mustChangePassword === undefined) defaults.mustChangePassword = true;
    if (!data.shiftRestricted) defaults.shiftRestricted = false;

    // Email domain restriction enforcement (supports multiple domains)
    if (data.email && data.role !== "companyAdmin") {
      const companyDoc = await db.collection("companies").doc(companyId).get();
      if (companyDoc.exists) {
        const companyData = companyDoc.data();
        const restrictions = companyData.emailDomainRestrictions || [];
        const legacySingle = companyData.emailDomainRestriction;
        const allowedDomains = restrictions.length > 0
          ? restrictions.map(d => d.toLowerCase())
          : legacySingle ? [legacySingle.toLowerCase()] : [];

        if (allowedDomains.length > 0) {
          const userDomain = data.email.split("@").pop().toLowerCase();
          if (!allowedDomains.includes(userDomain)) {
            await snap.ref.delete();
            await db.collection(`companies/${companyId}/auditLog`).add({
              event: "operatorRejected",
              description: `Operator ${data.email} rejected: domain @${userDomain} not allowed (requires @${allowedDomains.join(" or @")})`,
              user: "system",
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
              success: false,
              metadata: { email: data.email, allowedDomains, actualDomain: userDomain },
            });
            await _writeInApp({
              companyId, category: "security", severity: "warn", link: "/operators",
              title: "Invite rejected",
              body: `${data.email} couldn't be added — domain @${userDomain} isn't in your allowed list (@${allowedDomains.join(", @")}).`,
            });
            return;
          }
        }
      }
    }

    if (Object.keys(defaults).length > 0) {
      await snap.ref.update(defaults);
    }

    // Auto-create Firebase Auth account for the operator
    if (data.email) {
      try {
        await admin.auth().getUserByEmail(data.email);
      } catch (err) {
        if (err.code === "auth/user-not-found") {
          try {
            const crypto = require("crypto");
            const tempPassword = crypto.randomBytes(16).toString("hex");
            const newUser = await admin.auth().createUser({
              email: data.email,
              password: data.passwordHash ? undefined : tempPassword,
              emailVerified: true,
            });
            await snap.ref.update({ uid: newUser.uid });
          } catch (_) {}
        }
      }
    }

    // Notify a newly-added operator (best-effort). Skip the company admin (who
    // receives the welcome email) and the rejected paths that returned above.
    if (data.role !== "companyAdmin" && (data.email || data.phone)) {
      let companyName = "your company";
      try {
        const cd = await db.collection("companies").doc(companyId).get();
        if (cd.exists) companyName = (cd.data() || {}).name || companyName;
      } catch (_) { /* best-effort */ }
      await notifyContact({
        to: { email: data.email || null, phone: data.phone || null, name: data.name || "there" },
        companyId,
        subject: `You've been added to ${companyName} on ${BRAND.name}`,
        notif: ({
          category: "operator",
          link: "/operators",
          operatorEmail: data.email || null,
          heading: `Welcome to ${BRAND.name}`,
          intro: `Hi ${data.name || "there"}, you've been added as an operator for ${companyName}. ` +
            `Open the ${BRAND.name} desktop app and sign in with this email to get started.`,
          rows: [["Company", companyName], ["Your role", "Operator"], ["Sign-in email", data.email || "—"]],
          note: `If you weren't expecting this, ignore this message or contact ${BRAND.support}.`,
        }),
      });
    }
  });

// ─── Ensure Firebase Auth: callable to migrate existing operators ────────────

// Resolve the {companyId, role} a Firebase Auth user belongs to, for custom
// claims that future Firestore rules will scope per-company access on. Prefers
// an operator doc (carries role); falls back to the company doc (admin owner).
async function _resolveCompanyClaims(email) {
  const opSnap = await db.collectionGroup("operators").where("email", "==", email).limit(1).get();
  if (!opSnap.empty) {
    const d = opSnap.docs[0];
    const companyId = d.data().companyId || (d.ref.parent.parent ? d.ref.parent.parent.id : null);
    if (companyId) return { companyId, role: d.data().role || "operator" };
  }
  const compSnap = await db.collection("companies").where("email", "==", email).limit(1).get();
  if (!compSnap.empty) return { companyId: compSnap.docs[0].id, role: "admin" };
  return null;
}

// Mint the per-company custom claims on a uid AND return a Firebase custom token
// that embeds those claims, so the client can signInWithCustomToken and have the
// companyId claim carried deterministically in its session (the email/password
// sign-in did NOT reliably surface Admin-SDK claims). setCustomUserClaims keeps
// the claim across token refreshes; the custom token carries it for this session.
// claims is null mid-setup (before the company doc exists) — token still issued so
// the client gets an authenticated session for the bootstrap company-create.
async function _mintCompanyClaims(uid, email) {
  const claims = await _resolveCompanyClaims(email);
  const tokenClaims = claims ? { companyId: claims.companyId, role: claims.role } : {};
  if (claims) {
    await admin.auth().setCustomUserClaims(uid, tokenClaims);
  }
  let customToken = null;
  try {
    customToken = await admin.auth().createCustomToken(uid, tokenClaims);
  } catch (e) {
    functions.logger.warn("createCustomToken failed:", e.message);
  }
  return { companyId: claims ? claims.companyId : null, role: claims ? claims.role : null, customToken };
}

exports.ensureFirebaseAuth = fns.https.onCall(async (data, context) => {
  const email = (data.email || "").trim().toLowerCase();
  const password = data.password || "";
  if (!email) throw new functions.https.HttpsError("invalid-argument", "Email required");
  // Only the account owner (a valid post-login session) may sync/create their
  // Firebase Auth account — blocks the takeover where anyone could overwrite the
  // password of an existing account by email.
  {
    const _s = await _requireSession(data);
    if (_s.email !== email) {
      throw new functions.https.HttpsError("permission-denied", "Not authorized for this account.");
    }
  }

  try {
    const userRecord = await admin.auth().getUserByEmail(email);
    // User exists — update password if provided
    if (password) {
      await admin.auth().updateUser(userRecord.uid, { password });
      await _writeCredential(email, password);
      const opSnap = await db.collectionGroup("operators").where("email", "==", email).limit(1).get();
      if (!opSnap.empty) {
        await opSnap.docs[0].ref.update({ uid: userRecord.uid, passwordHash: admin.firestore.FieldValue.delete() });
      }
      const companySnap = await db.collection("companies").where("email", "==", email).limit(1).get();
      if (!companySnap.empty) {
        await companySnap.docs[0].ref.update({ passwordHash: admin.firestore.FieldValue.delete() });
      }
    }
    const c = await _mintCompanyClaims(userRecord.uid, email);
    return { uid: userRecord.uid, created: false, companyId: c.companyId, role: c.role, customToken: c.customToken };
  } catch (err) {
    if (err.code !== "auth/user-not-found") {
      throw new functions.https.HttpsError("internal", err.message);
    }
    // Create new Firebase Auth account
    if (!password) throw new functions.https.HttpsError("invalid-argument", "Password required for new account");
    const newUser = await admin.auth().createUser({
      email,
      password,
      emailVerified: true,
    });
    await _writeCredential(email, password);
    const opSnap = await db.collectionGroup("operators").where("email", "==", email).limit(1).get();
    if (!opSnap.empty) {
      await opSnap.docs[0].ref.update({ uid: newUser.uid, passwordHash: admin.firestore.FieldValue.delete() });
    }
    const companySnap = await db.collection("companies").where("email", "==", email).limit(1).get();
    if (!companySnap.empty) {
      await companySnap.docs[0].ref.update({ passwordHash: admin.firestore.FieldValue.delete() });
    }
    const c = await _mintCompanyClaims(newUser.uid, email);
    return { uid: newUser.uid, created: true, companyId: c.companyId, role: c.role, customToken: c.customToken };
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// ─── Server-side credentials (salted scrypt) ────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════
// Passwords are verified ONLY on the server and stored salted in the server-only
// `credentials/{normalizedEmail}` collection (denied to clients by firestore.rules).
// Legacy unsalted SHA-256 `passwordHash` fields on company/operator docs are
// verified once and upgraded to scrypt on next login, then stripped from the doc.

function _scryptHash(password, salt) {
  return require("crypto").scryptSync(String(password), salt, 64).toString("hex");
}

function _makeCredential(password) {
  const salt = require("crypto").randomBytes(16).toString("hex");
  return {
    algo: "scrypt",
    salt,
    hash: _scryptHash(password, salt),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function _verifyCredential(password, cred) {
  if (!cred || cred.algo !== "scrypt" || !cred.salt || !cred.hash) return false;
  const computed = Buffer.from(_scryptHash(password, cred.salt), "hex");
  const stored = Buffer.from(cred.hash, "hex");
  return computed.length === stored.length &&
    require("crypto").timingSafeEqual(computed, stored);
}

function _legacySha256(password) {
  return require("crypto").createHash("sha256").update(String(password)).digest("hex");
}

async function _writeCredential(normalizedEmail, password) {
  // merge:true so rewriting the password (login legacy-upgrade, re-register,
  // password reset) never clobbers the MFA fields (mfaEnabled/mfaSecret/backup
  // codes) that live on the same credentials doc.
  await db.collection("credentials").doc(normalizedEmail).set(_makeCredential(password), { merge: true });
}

// ─── TOTP (RFC 6238) two-factor auth ────────────────────────────────────────
// Secrets live (AES-256-GCM encrypted) on the server-only credentials doc and
// are never sent to the client except the one-time base32 shown at enrollment.

const _B32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

function _base32Encode(buf) {
  let bits = 0, value = 0, out = "";
  for (const b of buf) {
    value = (value << 8) | b; bits += 8;
    while (bits >= 5) { out += _B32[(value >>> (bits - 5)) & 31]; bits -= 5; }
  }
  if (bits > 0) out += _B32[(value << (5 - bits)) & 31];
  return out;
}

function _base32Decode(str) {
  const clean = String(str).toUpperCase().replace(/[^A-Z2-7]/g, "");
  let bits = 0, value = 0; const out = [];
  for (const c of clean) {
    value = (value << 5) | _B32.indexOf(c); bits += 5;
    if (bits >= 8) { out.push((value >>> (bits - 8)) & 0xff); bits -= 8; }
  }
  return Buffer.from(out);
}

function _totpCode(secretB32, counter) {
  const crypto = require("crypto");
  const buf = Buffer.alloc(8);
  buf.writeBigInt64BE(BigInt(counter));
  const hmac = crypto.createHmac("sha1", _base32Decode(secretB32)).update(buf).digest();
  const offset = hmac[hmac.length - 1] & 0xf;
  const code = ((hmac[offset] & 0x7f) << 24) | ((hmac[offset + 1] & 0xff) << 16) |
    ((hmac[offset + 2] & 0xff) << 8) | (hmac[offset + 3] & 0xff);
  return (code % 1000000).toString().padStart(6, "0");
}

// Accepts the current 30s code ± `window` steps to tolerate clock drift.
function _verifyTotp(secretB32, token, window = 1) {
  if (!secretB32 || !/^\d{6}$/.test(String(token || ""))) return false;
  const counter = Math.floor(Date.now() / 1000 / 30);
  for (let w = -window; w <= window; w++) {
    if (_totpCode(secretB32, counter + w) === String(token)) return true;
  }
  return false;
}

// Enrollment check: requires two codes from CONSECUTIVE 30s windows, proving the
// authenticator is generating a correct, time-synced sequence (not a one-off luck).
function _verifyTotpConsecutive(secretB32, c1, c2, window = 3) {
  if (!secretB32 || !/^\d{6}$/.test(String(c1 || "")) || !/^\d{6}$/.test(String(c2 || ""))) return false;
  if (String(c1) === String(c2)) return false; // same window pasted twice
  const counter = Math.floor(Date.now() / 1000 / 30);
  for (let w = -window; w <= window; w++) {
    if (_totpCode(secretB32, counter + w) === String(c1) &&
        _totpCode(secretB32, counter + w + 1) === String(c2)) {
      return true;
    }
  }
  return false;
}

function _generateTotpSecret() {
  return _base32Encode(require("crypto").randomBytes(20));
}

// One-time recovery codes (so a lost authenticator can't brick the account).
// High-entropy, so a plain SHA-256 of the normalized code is enough.
function _normalizeBackup(code) {
  return String(code || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
}
function _hashBackup(code) {
  return require("crypto").createHash("sha256").update(_normalizeBackup(code)).digest("hex");
}
function _generateBackupCodes(n = 8) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const b32 = _base32Encode(require("crypto").randomBytes(7)).slice(0, 10);
    out.push(`${b32.slice(0, 5)}-${b32.slice(5, 10)}`); // shown as XXXXX-XXXXX
  }
  return out;
}

function _mfaKey() {
  // Fail CLOSED — no hardcoded fallback, or anyone with the source could decrypt
  // every stored TOTP secret. MFA_ENC_KEY must be set in the functions env.
  const src = process.env.MFA_ENC_KEY;
  if (!src) throw new functions.https.HttpsError("failed-precondition", "MFA_ENC_KEY is not configured.");
  return require("crypto").createHash("sha256").update(src).digest();
}

function _encryptSecret(plain) {
  const crypto = require("crypto");
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", _mfaKey(), iv);
  const enc = Buffer.concat([cipher.update(String(plain), "utf8"), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), enc]).toString("base64");
}

function _decryptSecret(blob) {
  const crypto = require("crypto");
  const buf = Buffer.from(String(blob), "base64");
  const decipher = crypto.createDecipheriv("aes-256-gcm", _mfaKey(), buf.subarray(0, 12));
  decipher.setAuthTag(buf.subarray(12, 28));
  return Buffer.concat([decipher.update(buf.subarray(28)), decipher.final()]).toString("utf8");
}

function _companyIdFromPath(path) {
  const m = String(path).match(/companies\/([^/]+)/);
  return m ? m[1] : null;
}

// ─── Server-issued session tokens ────────────────────────────────────────────
// loginUser mints one; sensitive callables validate it. Stored in the server-only
// `auth_sessions` collection (default-deny rules). Closes the unauthenticated-
// callable IDOR (anon clients can't act on another company/operator).
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

async function _mintSessionToken(email, companyId, role) {
  // Invalidate this account's prior session tokens (newest login wins — matches
  // the single-active-session model), then issue a fresh one. Done in a single
  // transaction so a concurrent login can't leave two live tokens behind.
  const token = require("crypto").randomBytes(32).toString("hex");
  const q = db.collection("auth_sessions").where("email", "==", email);
  await db.runTransaction(async (tx) => {
    const prior = await tx.get(q);
    prior.forEach((d) => tx.delete(d.ref));
    tx.set(db.collection("auth_sessions").doc(token), {
      email, companyId, role: role || "operator",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + SESSION_TTL_MS),
    });
  });
  return token;
}

// Revokes ALL server-issued session tokens for an account (by email) — used
// when an operator is deleted/deactivated/archived/demoted so an already-issued
// token can't outlive the account-state change for up to the 30-day TTL.
async function _revokeSessionsForEmail(email) {
  const e = (email || "").trim().toLowerCase();
  if (!e) return;
  const snap = await db.collection("auth_sessions").where("email", "==", e).get();
  if (snap.empty) return;
  const batch = db.batch();
  snap.forEach((d) => batch.delete(d.ref));
  await batch.commit().catch((err) => console.warn("session revoke failed:", err.message));
}

// Validates data.sessionToken → { email, companyId, role }. Throws if missing/
// invalid/expired.
async function _requireSession(data) {
  const token = (data && data.sessionToken) || "";
  if (!token) throw new functions.https.HttpsError("unauthenticated", "Please sign in again to continue.");
  const snap = await db.collection("auth_sessions").doc(String(token)).get();
  if (!snap.exists) throw new functions.https.HttpsError("unauthenticated", "Your session expired. Sign in again.");
  const s = snap.data();
  const exp = (s.expiresAt && s.expiresAt.toMillis) ? s.expiresAt.toMillis() : 0;
  if (exp < Date.now()) {
    await snap.ref.delete().catch(() => {});
    throw new functions.https.HttpsError("unauthenticated", "Your session expired. Sign in again.");
  }
  // Re-validate against LIVE account state — a token minted before the account
  // was deleted/deactivated/archived/demoted must not keep working for the full
  // 30-day TTL. Use the current operator/company role, not the mint-time value.
  const live = await _liveAccountState(s.email, s.companyId);
  // Fail-CLOSED only on a definitive negative (the doc is genuinely gone /
  // deactivated / archived). On a transient lookup error (errored, no answer)
  // fail-OPEN with the mint-time role so a network blip can't log a valid user
  // out — security goal (revoke deleted accounts) is still met because deletion
  // returns "empty", not "error".
  if (live.errored && !live.exists) {
    return { email: s.email, companyId: s.companyId, role: s.role };
  }
  if (!live.exists || live.isDeleted || live.isArchived || live.isActive === false) {
    await snap.ref.delete().catch(() => {});
    throw new functions.https.HttpsError("permission-denied", "This account is no longer active. Sign in again.");
  }
  return { email: s.email, companyId: s.companyId, role: live.role || s.role };
}

// Loads the current operator/company doc for {email, companyId} and reports the
// account's live state + role. Operator first (scoped to the company), then the
// company-admin doc. Returns {exists:false} when neither is found. `errored` is
// set when a lookup threw, so the caller can fail-open instead of locking out a
// valid user on a transient infrastructure error.
async function _liveAccountState(email, companyId) {
  const e = (email || "").trim().toLowerCase();
  if (!e) return { exists: false };
  let errored = false;
  if (companyId) {
    try {
      const opSnap = await db.collection(`companies/${companyId}/operators`)
        .where("email", "==", e).limit(1).get();
      if (!opSnap.empty) {
        const d = opSnap.docs[0].data() || {};
        return {
          exists: true,
          isDeleted: d.isDeleted === true,
          isArchived: d.isArchived === true,
          isActive: d.isActive,
          role: d.role || "operator",
        };
      }
    } catch (e2) {
      errored = true;
      console.warn("live operator lookup failed:", e2.message);
    }
    try {
      const coSnap = await db.doc(`companies/${companyId}`).get();
      if (coSnap.exists) {
        const d = coSnap.data() || {};
        if ((d.email || "").trim().toLowerCase() === e) {
          return {
            exists: true,
            isDeleted: d.isDeleted === true,
            isArchived: d.isArchived === true,
            isActive: d.isActive,
            role: d.role || "companyAdmin",
          };
        }
      }
    } catch (e3) {
      errored = true;
      console.warn("live company lookup failed:", e3.message);
    }
  }
  // Fallback: locate the operator anywhere by email (handles a missing/stale
  // companyId on the session).
  try {
    const opSnap = await db.collectionGroup("operators").where("email", "==", e).limit(1).get();
    if (!opSnap.empty) {
      const d = opSnap.docs[0].data() || {};
      return {
        exists: true,
        isDeleted: d.isDeleted === true,
        isArchived: d.isArchived === true,
        isActive: d.isActive,
        role: d.role || "operator",
      };
    }
  } catch (e4) {
    errored = true;
    console.warn("live operator group lookup failed:", e4.message);
  }
  return { exists: false, errored };
}

// Requires the session to be an admin of [companyId] (when given).
async function _requireAdminSession(data, companyId) {
  const s = await _requireSession(data);
  if (s.role !== "admin" && s.role !== "companyAdmin") {
    throw new functions.https.HttpsError("permission-denied", "Admin access required.");
  }
  if (companyId && s.companyId !== companyId) {
    throw new functions.https.HttpsError("permission-denied", "Not authorized for this company.");
  }
  return s;
}

/**
 * loginUser - Server-side password verification. Replaces the old client-side
 * hash compare so clients never read `passwordHash`. Verifies against the
 * salted credential, falling back to (and upgrading from) the legacy unsalted
 * hash on first login. Returns identity (never the hash) or throws.
 */
exports.loginUser = fns.https.onCall(async (data, context) => {
  const email = (data.email || "").trim().toLowerCase();
  const password = data.password || "";
  if (!email || !password) {
    throw new functions.https.HttpsError("invalid-argument", "Email and password required");
  }

  // Locate the account: operator (collectionGroup) first, then company admin.
  let docRef = null;
  let docData = null;
  let kind = null;
  const opSnap = await db.collectionGroup("operators").where("email", "==", email).limit(1).get();
  if (!opSnap.empty) {
    docRef = opSnap.docs[0].ref;
    docData = opSnap.docs[0].data();
    kind = "operator";
  } else {
    const coSnap = await db.collection("companies").where("email", "==", email).limit(1).get();
    if (!coSnap.empty) {
      docRef = coSnap.docs[0].ref;
      docData = coSnap.docs[0].data();
      kind = "company";
    }
  }
  if (!docRef) {
    throw new functions.https.HttpsError("not-found", "No account found with this email.");
  }

  // Per-account password lockout — throttle online brute-force. Counters live on
  // the account doc (always present, unlike the credential doc for legacy users).
  const pwNowMs = Date.now();
  const pwLockMs = (docData.loginLockUntil && docData.loginLockUntil.toMillis)
    ? docData.loginLockUntil.toMillis() : 0;
  if (pwLockMs > pwNowMs) {
    throw new functions.https.HttpsError("resource-exhausted",
      "Too many failed sign-in attempts. Wait a few minutes and try again.");
  }

  const credSnap = await db.collection("credentials").doc(email).get();
  let ok = false;
  if (credSnap.exists) {
    ok = _verifyCredential(password, credSnap.data());
  } else if (docData.passwordHash) {
    // Legacy account — verify the unsalted hash, then upgrade + strip.
    ok = _legacySha256(password) === docData.passwordHash;
    if (ok) {
      await _writeCredential(email, password);
      await docRef.update({ passwordHash: admin.firestore.FieldValue.delete() });
    }
  } else {
    throw new functions.https.HttpsError(
      "failed-precondition", "No password set for this account. Use 'Forgot password' to set one.");
  }

  if (!ok) {
    const fails = (docData.loginFailCount || 0) + 1;
    await docRef.update(fails >= 5
      ? { loginFailCount: 0, loginLockUntil: admin.firestore.Timestamp.fromMillis(pwNowMs + 15 * 60 * 1000) }
      : { loginFailCount: fails }).catch(() => {});
    throw new functions.https.HttpsError("permission-denied", "Invalid email or password.");
  }
  // Password verified — clear any password-attempt throttle.
  if (docData.loginFailCount || docData.loginLockUntil) {
    await docRef.update({
      loginFailCount: admin.firestore.FieldValue.delete(),
      loginLockUntil: admin.firestore.FieldValue.delete(),
    }).catch(() => {});
  }
  if (docData.isDeleted) throw new functions.https.HttpsError("permission-denied", "This account has been deleted.");
  if (docData.isArchived) throw new functions.https.HttpsError("permission-denied", "This account has been archived.");

  // Two-factor (TOTP) gate: if enabled, the password alone is not enough.
  const credForMfa = credSnap.exists ? credSnap.data() : {};
  if (credForMfa.mfaEnabled === true && credForMfa.mfaSecret) {
    const nowMs = Date.now();
    const lockMs = (credForMfa.mfaLockUntil && credForMfa.mfaLockUntil.toMillis)
      ? credForMfa.mfaLockUntil.toMillis() : 0;
    if (lockMs > nowMs) {
      throw new functions.https.HttpsError("resource-exhausted",
        "Too many incorrect codes. Wait a few minutes and try again.");
    }
    const code = String(data.totpCode || "").replace(/\s/g, "");
    if (!code) {
      // Password was correct — tell the client to collect the code.
      return { mfaRequired: true };
    }
    // Accept the 6-digit TOTP, or a one-time recovery code (consumed on use).
    // Tolerate a decrypt failure (MFA_ENC_KEY rotated / corrupt secret blob) so a
    // valid backup code still works as the recovery path it exists to be.
    let totpOk = false;
    try { totpOk = _verifyTotp(_decryptSecret(credForMfa.mfaSecret), code); } catch (_) { totpOk = false; }
    const backupAvailable = !totpOk && Array.isArray(credForMfa.mfaBackupCodes)
      && credForMfa.mfaBackupCodes.indexOf(_hashBackup(code)) >= 0;
    const credRef = db.collection("credentials").doc(email);
    if (!totpOk && !backupAvailable) {
      const fails = (credForMfa.mfaFailCount || 0) + 1;
      await credRef.update(fails >= 5
        ? { mfaFailCount: 0, mfaLockUntil: admin.firestore.Timestamp.fromMillis(nowMs + 15 * 60 * 1000) }
        : { mfaFailCount: fails });
      throw new functions.https.HttpsError("permission-denied", "Invalid authentication code.");
    }
    if (backupAvailable) {
      // Consume the one-time backup code ATOMICALLY — two concurrent logins with
      // the same backup code must not both succeed (double-spend).
      await db.runTransaction(async (tx) => {
        const s = await tx.get(credRef);
        const codes = Array.isArray(s.data() && s.data().mfaBackupCodes) ? s.data().mfaBackupCodes : [];
        const idx = codes.indexOf(_hashBackup(code));
        if (idx < 0) throw new functions.https.HttpsError("permission-denied", "Invalid authentication code.");
        tx.update(credRef, {
          mfaBackupCodes: codes.filter((_, i) => i !== idx),
          mfaFailCount: admin.firestore.FieldValue.delete(),
          mfaLockUntil: admin.firestore.FieldValue.delete(),
        });
      });
    } else {
      // TOTP success — just clear the throttle.
      await credRef.update({
        mfaFailCount: admin.firestore.FieldValue.delete(),
        mfaLockUntil: admin.firestore.FieldValue.delete(),
      });
    }
  }

  // Re-authentication on the SAME device (e.g. unlocking a locked session):
  // password/MFA is now verified, but we must NOT rotate the active session —
  // doing so would change activeSessionId and make the single-session guard
  // sign this very device out to the welcome page ("another device").
  if (data.reauth === true) {
    return { ok: true, reauth: true };
  }

  // Single active session: mint a new session id and stamp it on the user doc.
  // Any other device watching this doc sees the id change and signs itself out
  // (newest login wins). Applies to admins and operators alike.
  const sessionId = require("crypto").randomBytes(24).toString("hex");
  await docRef.update({
    activeSessionId: sessionId,
    activeSessionAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const companyId = kind === "company" ? docRef.id : (docData.companyId || _companyIdFromPath(docRef.path));
  const role = docData.role || (kind === "company" ? "companyAdmin" : "operator");

  // Server-issued session token — bound to {email, companyId, role}, stored in a
  // server-only collection. Sensitive callables require + validate it so an
  // anonymous client can't act on another company/operator (closes IDOR).
  const sessionToken = await _mintSessionToken(email, companyId, role);

  return {
    ok: true,
    kind,
    uid: docData.uid || null,
    companyId,
    role,
    name: docData.name || "",
    mustChangePassword: docData.mustChangePassword === true,
    isVerified: docData.isVerified === true,
    isActive: docData.isActive !== false,
    activeSessionId: sessionId,
    sessionToken,
    // Server-authoritative address-verification gate — uses server time, so a
    // tampered device clock can't bypass the 30-day deadline.
    addressLocked: await _addressGateLocked(companyId),
  };
});

// ─── MFA management (opt-in TOTP) ───────────────────────────────────────────

/**
 * mfaStatus - Returns whether TOTP 2FA is enabled for an account.
 */
exports.mfaStatus = fns.https.onCall(async (data) => {
  const email = (data.email || "").trim().toLowerCase();
  if (!email) throw new functions.https.HttpsError("invalid-argument", "Email required");
  const snap = await db.collection("credentials").doc(email).get();
  const d = snap.exists ? snap.data() : {};
  return {
    enabled: d.mfaEnabled === true,
    backupCodesRemaining: Array.isArray(d.mfaBackupCodes) ? d.mfaBackupCodes.length : 0,
  };
});

/**
 * mfaRegenerateBackupCodes - Verifies the password and replaces the recovery
 * codes with a fresh set (the old ones stop working). Returns the new plaintext
 * codes once.
 */
exports.mfaRegenerateBackupCodes = fns.https.onCall(async (data) => {
  const email = (data.email || "").trim().toLowerCase();
  const password = data.password || "";
  if (!email || !password) throw new functions.https.HttpsError("invalid-argument", "Email and password required");
  const credRef = db.collection("credentials").doc(email);
  const snap = await credRef.get();
  if (!snap.exists || !_verifyCredential(password, snap.data())) {
    throw new functions.https.HttpsError("permission-denied", "Incorrect password.");
  }
  if (snap.data().mfaEnabled !== true) {
    throw new functions.https.HttpsError("failed-precondition", "Two-factor authentication is not enabled.");
  }
  const backupCodes = _generateBackupCodes(8);
  await credRef.set({ mfaBackupCodes: backupCodes.map(_hashBackup) }, { merge: true });
  return { ok: true, backupCodes };
});

// Verifies a code against the account's CURRENTLY-ACTIVE second factor (live
// TOTP or an unused backup code). Used to gate operations that overwrite an
// already-active MFA secret so a stolen password alone can't rebind it.
function _verifyCurrentMfaFactor(cred, rawCode) {
  const code = String(rawCode || "").replace(/\s/g, "");
  if (!code) return false;
  // Decrypt failure (key rotated/corrupt) must fall through to the backup code,
  // not throw — otherwise the second-factor gate can never be satisfied.
  try {
    if (cred.mfaSecret && _verifyTotp(_decryptSecret(cred.mfaSecret), code)) return true;
  } catch (_) { /* fall through to backup code */ }
  if (Array.isArray(cred.mfaBackupCodes) && cred.mfaBackupCodes.includes(_hashBackup(code))) return true;
  return false;
}

/**
 * mfaBeginEnroll - Verifies the password, generates a fresh TOTP secret, stores
 * it as a PENDING (not-yet-active) encrypted secret, and returns the base32 +
 * otpauth URI so the client can show a QR. Requires the password so only the
 * account owner can start enrollment.
 */
exports.mfaBeginEnroll = fns.https.onCall(async (data) => {
  const email = (data.email || "").trim().toLowerCase();
  const password = data.password || "";
  if (!email || !password) throw new functions.https.HttpsError("invalid-argument", "Email and password required");
  const credRef = db.collection("credentials").doc(email);
  const snap = await credRef.get();
  if (!snap.exists || !_verifyCredential(password, snap.data())) {
    throw new functions.https.HttpsError("permission-denied", "Incorrect password.");
  }
  // Re-enrollment guard: if 2FA is already on, the password alone must NOT be
  // able to rebind the secret to an attacker's authenticator. Require the CURRENT
  // second factor (live TOTP or an unused backup code) before re-enrolling, or
  // disable 2FA first. Prevents password-only MFA takeover via re-binding.
  if (snap.data().mfaEnabled === true) {
    if (!_verifyCurrentMfaFactor(snap.data(), data.currentCode)) {
      throw new functions.https.HttpsError("failed-precondition",
        "Two-factor authentication is already enabled. Enter a current authenticator or backup code to re-enroll, or disable it first.");
    }
  }
  const secret = _generateTotpSecret();
  await credRef.set({
    mfaPendingSecret: _encryptSecret(secret),
    mfaPendingAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  const issuer = "Tulanam";
  const otpauth = `otpauth://totp/${encodeURIComponent(`${issuer}:${email}`)}` +
    `?secret=${secret}&issuer=${encodeURIComponent(issuer)}&algorithm=SHA1&digits=6&period=30`;
  return { secret, otpauth };
});

/**
 * mfaConfirmEnroll - Verifies a code against the pending secret and, on success,
 * activates 2FA (promotes pending → active secret).
 */
exports.mfaConfirmEnroll = fns.https.onCall(async (data) => {
  const email = (data.email || "").trim().toLowerCase();
  const code = String(data.code || data.code1 || "").replace(/\s/g, "");
  if (!email) throw new functions.https.HttpsError("invalid-argument", "Email required");
  const credRef = db.collection("credentials").doc(email);
  const snap = await credRef.get();
  const cred = snap.exists ? snap.data() : {};
  // Re-enrollment guard (defense in depth with mfaBeginEnroll): never promote a
  // pending secret over an already-active one without the CURRENT second factor.
  if (cred.mfaEnabled === true && !_verifyCurrentMfaFactor(cred, data.currentCode)) {
    throw new functions.https.HttpsError("failed-precondition",
      "Two-factor authentication is already enabled. Enter a current authenticator or backup code to re-enroll, or disable it first.");
  }
  const pending = cred.mfaPendingSecret || null;
  if (!pending) throw new functions.https.HttpsError("failed-precondition", "No pending enrollment. Start again.");
  // The QR / pending secret expires 10 minutes after it was generated, so an
  // abandoned enrollment can't be completed later.
  const pendingAt = (cred.mfaPendingAt && cred.mfaPendingAt.toMillis) ? cred.mfaPendingAt.toMillis() : 0;
  if (!pendingAt || Date.now() - pendingAt > 10 * 60 * 1000) {
    await credRef.set({
      mfaPendingSecret: admin.firestore.FieldValue.delete(),
      mfaPendingAt: admin.firestore.FieldValue.delete(),
    }, { merge: true });
    throw new functions.https.HttpsError("deadline-exceeded", "This QR code has expired. Start enrollment again to get a fresh one.");
  }
  if (!_verifyTotp(_decryptSecret(pending), code)) {
    throw new functions.https.HttpsError("permission-denied", "Incorrect code. Check your authenticator app.");
  }
  const backupCodes = _generateBackupCodes(8);
  await credRef.set({
    mfaEnabled: true,
    mfaSecret: pending,
    mfaPendingSecret: admin.firestore.FieldValue.delete(),
    mfaEnabledAt: admin.firestore.FieldValue.serverTimestamp(),
    mfaBackupCodes: backupCodes.map(_hashBackup), // store hashes only
    mfaFailCount: admin.firestore.FieldValue.delete(),
    mfaLockUntil: admin.firestore.FieldValue.delete(),
  }, { merge: true });
  _notifyMfaChanged(email, true).catch((e) => console.warn("mfa-enabled notice failed:", e.message));
  // Plaintext codes are returned exactly once for the user to save.
  return { ok: true, backupCodes };
});

/**
 * mfaDisable - Turns off 2FA. Requires a current authenticator or backup code
 * (the second factor) — a stolen password alone cannot disable it.
 */
exports.mfaDisable = fns.https.onCall(async (data) => {
  const email = (data.email || "").trim().toLowerCase();
  const code = String(data.code || "").replace(/\s/g, "");
  if (!email) throw new functions.https.HttpsError("invalid-argument", "Email required");
  const credRef = db.collection("credentials").doc(email);
  const snap = await credRef.get();
  if (!snap.exists) throw new functions.https.HttpsError("not-found", "Account not found.");
  const cred = snap.data();
  // Throttle code attempts (same lockout the other MFA callables use) so a
  // stolen password can't be paired with an unbounded brute-force of TOTP codes
  // to strip a victim's 2FA.
  const nowMs = Date.now();
  const lockMs = (cred.mfaLockUntil && cred.mfaLockUntil.toMillis) ? cred.mfaLockUntil.toMillis() : 0;
  if (lockMs > nowMs) {
    throw new functions.https.HttpsError("resource-exhausted", "Too many incorrect codes. Wait a few minutes and try again.");
  }
  // Disabling 2FA requires the SECOND factor (authenticator or backup code) — a
  // stolen password alone must not be able to turn MFA off.
  let allowed = false;
  // Decrypt failure (key rotated/corrupt) must not throw — the backup code below
  // has to remain a valid way to disable 2FA.
  try {
    if (code && cred.mfaSecret && _verifyTotp(_decryptSecret(cred.mfaSecret), code)) allowed = true;
  } catch (_) { /* fall through to backup code */ }
  if (!allowed && code && Array.isArray(cred.mfaBackupCodes) && cred.mfaBackupCodes.includes(_hashBackup(code))) allowed = true;
  if (!allowed) {
    const fails = (cred.mfaFailCount || 0) + 1;
    await credRef.update(fails >= 5
      ? { mfaFailCount: 0, mfaLockUntil: admin.firestore.Timestamp.fromMillis(nowMs + 15 * 60 * 1000) }
      : { mfaFailCount: fails });
    throw new functions.https.HttpsError("permission-denied", "A valid authenticator or backup code is required to disable 2FA.");
  }
  // Tear down ALL 2FA state — leaving stale backup codes / throttle counters
  // behind would let them apply to a future re-enrollment.
  await credRef.set({
    mfaEnabled: admin.firestore.FieldValue.delete(),
    mfaSecret: admin.firestore.FieldValue.delete(),
    mfaPendingSecret: admin.firestore.FieldValue.delete(),
    mfaPendingAt: admin.firestore.FieldValue.delete(),
    mfaBackupCodes: admin.firestore.FieldValue.delete(),
    mfaFailCount: admin.firestore.FieldValue.delete(),
    mfaLockUntil: admin.firestore.FieldValue.delete(),
  }, { merge: true });
  _notifyMfaChanged(email, false).catch((e) => console.warn("mfa-disabled notice failed:", e.message));
  return { ok: true };
});

/**
 * verifyMfaCode - Verifies a TOTP (or one-time backup) code for an account.
 * Used as an ALTERNATIVE to an email/SMS OTP for step-up re-verification (face
 * re-enrollment, profile/settings changes, …) whenever the account has 2FA on.
 * Same TOTP/backup/lockout logic loginUser uses.
 */
exports.verifyMfaCode = fns.https.onCall(async (data) => {
  const email = (data.email || "").trim().toLowerCase();
  const code = String(data.code || data.otp || "").replace(/\s/g, "");
  if (!email || !code) {
    throw new functions.https.HttpsError("invalid-argument", "Email and code required");
  }
  const credRef = db.collection("credentials").doc(email);
  const snap = await credRef.get();
  const cred = snap.exists ? snap.data() : null;
  if (!cred || cred.mfaEnabled !== true || !cred.mfaSecret) {
    throw new functions.https.HttpsError("failed-precondition", "Two-factor authentication is not enabled for this account.");
  }
  const nowMs = Date.now();
  const lockMs = (cred.mfaLockUntil && cred.mfaLockUntil.toMillis) ? cred.mfaLockUntil.toMillis() : 0;
  if (lockMs > nowMs) {
    throw new functions.https.HttpsError("resource-exhausted", "Too many incorrect codes. Wait a few minutes and try again.");
  }
  // Decrypt failure (key rotated/corrupt) → fall through to the backup-code path.
  let totpOk = false;
  try { totpOk = _verifyTotp(_decryptSecret(cred.mfaSecret), code); } catch (_) { totpOk = false; }
  const backupIdx = (!totpOk && Array.isArray(cred.mfaBackupCodes))
    ? cred.mfaBackupCodes.indexOf(_hashBackup(code)) : -1;

  if (!totpOk && backupIdx < 0) {
    const fails = (cred.mfaFailCount || 0) + 1;
    await credRef.update(fails >= 5
      ? { mfaFailCount: 0, mfaLockUntil: admin.firestore.Timestamp.fromMillis(nowMs + 15 * 60 * 1000) }
      : { mfaFailCount: fails });
    throw new functions.https.HttpsError("permission-denied", "Invalid authentication code.");
  }

  if (backupIdx >= 0) {
    // Consume the one-time backup code ATOMICALLY — two concurrent requests with
    // the same backup code must not both succeed (and both mint a reset token).
    await db.runTransaction(async (tx) => {
      const s = await tx.get(credRef);
      const codes = Array.isArray(s.data() && s.data().mfaBackupCodes) ? s.data().mfaBackupCodes : [];
      const idx = codes.indexOf(_hashBackup(code));
      if (idx < 0) throw new functions.https.HttpsError("permission-denied", "Invalid authentication code.");
      tx.update(credRef, {
        mfaBackupCodes: codes.filter((_, i) => i !== idx),
        mfaFailCount: admin.firestore.FieldValue.delete(),
        mfaLockUntil: admin.firestore.FieldValue.delete(),
      });
    });
  } else {
    await credRef.update({
      mfaFailCount: admin.firestore.FieldValue.delete(),
      mfaLockUntil: admin.firestore.FieldValue.delete(),
    });
  }
  const out = { success: true, verified: true };
  // For password reset: issue the same one-time reset token verifyPasswordResetOTP
  // mints, so an authenticator code can stand in for the email reset OTP.
  if (data.mintResetToken === true) out.verificationToken = await _mintPasswordResetToken(email);
  return out;
});

/**
 * registerCredential - Stores a salted credential for a new/updated account and
 * strips any legacy `passwordHash` from the doc. Called by the client during
 * registration instead of writing `passwordHash` into Firestore directly.
 */
exports.registerCredential = fns.https.onCall(async (data, context) => {
  const email = (data.email || "").trim().toLowerCase();
  const password = data.password || "";
  if (!email || !password) {
    throw new functions.https.HttpsError("invalid-argument", "Email and password required");
  }
  if (password.length < 6) {
    throw new functions.https.HttpsError("invalid-argument", "Password must be at least 6 characters");
  }
  // Overwriting an EXISTING credential requires proof of ownership — a valid
  // session for this email (the force-change flow has one right after loginUser).
  // A brand-new account (no credential yet) may bootstrap. Closes the takeover
  // where anyone could reset any account's password by email.
  const _existing = await db.collection("credentials").doc(email).get();
  if (_existing.exists) {
    const _s = await _requireSession(data);
    if (_s.email !== email) {
      throw new functions.https.HttpsError("permission-denied", "Not authorized to change this account's password.");
    }
  }
  await _writeCredential(email, password);
  // Best-effort: remove any legacy hash that may have been written to the doc.
  try {
    const opSnap = await db.collectionGroup("operators").where("email", "==", email).limit(1).get();
    if (!opSnap.empty) {
      await opSnap.docs[0].ref.update({ passwordHash: admin.firestore.FieldValue.delete() });
    }
    const coSnap = await db.collection("companies").where("email", "==", email).limit(1).get();
    if (!coSnap.empty) {
      await coSnap.docs[0].ref.update({ passwordHash: admin.firestore.FieldValue.delete() });
    }
  } catch (_) {}
  return { ok: true };
});

// ─── Operator Updated: Audit trail for KYC status changes ───────────────────

exports.onOperatorUpdated = fns.firestore
  .document("companies/{companyId}/operators/{operatorId}")
  .onUpdate(async (change, context) => {
    const { companyId } = context.params;
    const before = change.before.data();
    const after = change.after.data();

    // Log KYC status change
    if (before.idStatus !== after.idStatus) {
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "kycStatusChange",
        description: `Operator ${after.name || after.email} ID status changed: ${before.idStatus} → ${after.idStatus}`,
        user: after.idVerifiedBy || "system",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
        metadata: {
          operatorId: context.params.operatorId,
          oldStatus: before.idStatus,
          newStatus: after.idStatus,
        },
      });

      // Notify the operator on a terminal KYC result (best-effort).
      if (after.idStatus === "verified" || after.idStatus === "rejected") {
        const ok = after.idStatus === "verified";
        await notifyContact({
          to: { email: after.email || null, phone: after.phone || null, name: after.name || "there" },
          companyId,
          subject: `${BRAND.name}: identity verification ${ok ? "approved" : "needs attention"}`,
          notif: ({
            category: "kyc",
            link: "/operators",
            operatorEmail: after.email || null,
            accent: ok ? undefined : "warn",
            heading: ok ? "Identity verified" : "Identity verification not approved",
            intro: ok
              ? `Hi ${after.name || "there"}, your identity has been verified on ${BRAND.name}. You're all set.`
              : `Hi ${after.name || "there"}, your identity verification was not approved. Please re-submit your documents or contact your administrator.`,
            note: `Questions? Contact your ${BRAND.name} administrator.`,
          }),
        });
      }
    }

    // Log shift change
    if (before.shiftStart !== after.shiftStart ||
        before.shiftEnd !== after.shiftEnd ||
        JSON.stringify(before.shiftDays) !== JSON.stringify(after.shiftDays)) {
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "settingChange",
        description: `Shift updated for ${after.name || after.email}`,
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
        metadata: {
          operatorId: context.params.operatorId,
          shiftBefore: `${before.shiftStart || ""}–${before.shiftEnd || ""}`,
          shiftAfter: `${after.shiftStart || ""}–${after.shiftEnd || ""}`,
        },
      });
    }

    // Revoke live session tokens when access is removed (deactivated/archived) so
    // a still-valid token can't outlive the change for the 30-day TTL.
    if (after.email &&
        ((before.isActive === true && after.isActive === false) ||
         (before.isArchived !== true && after.isArchived === true))) {
      await _revokeSessionsForEmail(after.email);
    }

    // Log deactivation
    if (before.isActive === true && after.isActive === false) {
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "operatorDeactivated",
        description: `Operator ${after.name || after.email} deactivated`,
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
        metadata: { operatorId: context.params.operatorId },
      });

      // Notify the operator their access was revoked (best-effort). Skip when
      // this deactivation is part of an archive — onOperatorLifecycle sends the
      // archive notice, so we avoid a duplicate (archive sets both flags).
      if (!after.isArchived) {
        await notifyContact({
          to: { email: after.email || null, phone: after.phone || null, name: after.name || "there" },
          companyId,
          subject: `${BRAND.name}: your operator access was deactivated`,
          notif: ({
            category: "operator",
            link: "/operators",
            operatorEmail: after.email || null,
            accent: "warn",
            heading: "Access deactivated",
            intro: `Hi ${after.name || "there"}, your operator access on ${BRAND.name} has been deactivated, so you will no longer be able to sign in.`,
            note: `If you believe this is a mistake, contact your ${BRAND.name} administrator.`,
          }),
        });
      }
    }

    // Role / privilege change — notify the affected operator (security).
    if (before.role !== after.role && (after.email || after.phone)) {
      // Revoke live tokens so a demoted admin can't keep ADMIN rights on a token
      // whose role was frozen at mint time; re-login mints one with the new role.
      if (after.email) await _revokeSessionsForEmail(after.email);
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "operatorRoleChanged",
        description: `Role for ${after.name || after.email} changed: ${before.role || "none"} → ${after.role || "none"}`,
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
        metadata: { operatorId: context.params.operatorId, from: before.role || null, to: after.role || null },
      });
      await notifyContact({
        to: { email: after.email || null, phone: after.phone || null, name: after.name || "there" },
        companyId,
        critical: true,
        subject: `${BRAND.name}: your access level changed`,
        notif: ({
          category: "account",
          link: "/operators",
          operatorEmail: after.email || null,
          accent: "warn",
          heading: "Access level changed",
          intro: `Your role on ${BRAND.name} was changed to "${after.role || "none"}". Your permissions may be different now.`,
          note: "If you didn't expect this change, contact your administrator.",
        }),
      });
    }
  });

// ─── Operator deleted: clean up the Auth account + notify ───────────────────
exports.onOperatorDeleted = fns.firestore
  .document("companies/{companyId}/operators/{operatorId}")
  .onDelete(async (snap, context) => {
    const { companyId } = context.params;
    const op = snap.data() || {};
    // Remove the orphaned Firebase Auth account (best-effort) so a deleted
    // operator can't keep authenticating.
    try {
      if (op.uid) {
        await admin.auth().deleteUser(op.uid);
      } else if (op.email) {
        const u = await admin.auth().getUserByEmail(op.email);
        await admin.auth().deleteUser(u.uid);
      }
    } catch (e) {
      console.warn("operator auth cleanup failed:", e.message);
    }
    // Revoke any live server-issued session tokens so a deleted operator can't
    // keep calling session-guarded APIs until the 30-day TTL expires.
    if (op.email) await _revokeSessionsForEmail(op.email);
    // Remove the operator's enrolled face frames from Storage — otherwise they
    // orphan forever. Cover BOTH key schemes: storeFaceFrames writes under the
    // operatorId, the legacy enrollOperatorFace writes under the email.
    try {
      await bucket.deleteFiles({ prefix: `face-enrollment/${companyId}/${context.params.operatorId}/` });
      if (op.email) {
        await bucket.deleteFiles({ prefix: `face-enrollment/${companyId}/${op.email}/` });
      }
    } catch (e) {
      console.warn("operator face-frame cleanup failed:", e.message);
    }
    await db.collection(`companies/${companyId}/auditLog`).add({
      event: "operatorDeleted",
      description: `Operator deleted: ${op.name || op.email || context.params.operatorId}`,
      user: "admin",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      success: true,
      metadata: { email: op.email || null, role: op.role || null },
    });
    // Admin record (company-wide) + a courtesy notice to the removed operator.
    await _writeInApp({
      companyId, category: "security", severity: "warn", link: "/operators",
      title: "Operator deleted",
      body: `${op.name || op.email || "An operator"} was permanently removed from your company.`,
    });
    if (op.email || op.phone) {
      await notifyContact({
        to: { email: op.email || null, phone: op.phone || null, name: op.name || "there" },
        companyId,
        critical: true,
        skipInApp: true,
        subject: `${BRAND.name}: your account was removed`,
        notif: ({
          category: "account",
          accent: "warn",
          heading: "Account removed",
          intro: `Your operator account on ${BRAND.name} has been permanently removed, so you no longer have access.`,
          note: "If you believe this is a mistake, contact your administrator.",
        }),
      }).catch((e) => console.warn("operator-deleted notice failed:", e.message));
    }
  });

// ─── Company deleted: purge its Storage (face frames + KYC photo) ───────────
// Firestore doc deletion leaves Storage untouched, so without this a deleted
// company strands every operator's face frames plus its Aadhaar/KYC photo.
exports.onCompanyDeleted = fns.firestore
  .document("companies/{companyId}")
  .onDelete(async (snap, context) => {
    const { companyId } = context.params;
    const c = snap.data() || {};
    // All face-enrollment frames for the company (every operator, both schemes).
    try {
      await bucket.deleteFiles({ prefix: `face-enrollment/${companyId}/` });
    } catch (e) {
      console.warn("company face-frame cleanup failed:", e.message);
    }
    // The company's KYC photo lives at kyc/{reference}/… — derive the reference
    // from the stored verifiedPhotoUrl ( …/o/<urlencoded path>?… ).
    try {
      const m = String(c.verifiedPhotoUrl || "").match(/\/o\/([^?]+)/);
      if (m) {
        const ref = decodeURIComponent(m[1]).split("/")[1];
        if (ref) await bucket.deleteFiles({ prefix: `kyc/${ref}/` });
      }
    } catch (e) {
      console.warn("company kyc cleanup failed:", e.message);
    }
  });

// ─── Weighbridge created: alert when the plan limit is reached ──────────────
exports.onWeighbridgeCreated = fns.firestore
  .document("companies/{companyId}/sites/{siteId}/weighbridges/{weighbridgeId}")
  .onCreate(async (snap, context) => {
    const { companyId } = context.params;
    try {
      const compSnap = await db.doc(`companies/${companyId}`).get();
      const max = compSnap.exists ? (compSnap.data().license?.maxWeighbridges ?? 1) : 1;
      if (max === -1) return null; // unlimited plan — no ceiling

      // Count weighbridges across all sites.
      let count = 0;
      const sites = await db.collection(`companies/${companyId}/sites`).get();
      for (const site of sites.docs) {
        const wbs = await db.collection(`companies/${companyId}/sites/${site.id}/weighbridges`).get();
        count += wbs.size;
      }
      if (count < max) return null; // still under the limit
      if (count <= 1) return null; // never nag on the very first weighbridge (onboarding)

      // At/over the limit — notify once per window (reuses the cooldown guard so
      // repeated add attempts don't re-alert).
      if (await _alertSmsAllowed(companyId, "quotaReached")) {
        await notifyContact({
          companyId,
          subject: `${BRAND.name}: weighbridge limit reached`,
          notif: ({
            category: "billing",
            link: "/settings/license",
            accent: "warn",
            heading: "Weighbridge limit reached",
            intro: `Your ${BRAND.name} plan allows ${max} weighbridge${max === 1 ? "" : "s"} and you've now reached that limit. Upgrade your plan to add more.`,
            rows: [["Plan limit", String(max)], ["In use", String(count)]],
            ctaText: "Upgrade plan",
            ctaUrl: `https://${BRAND.website}/billing`,
            note: `Need a higher limit? Contact ${BRAND.support}.`,
          }),
        });
      }
    } catch (e) {
      console.warn("weighbridge quota check failed:", e.message);
    }
    return null;
  });

// ─── Security Settings Changed: Audit + Emergency Lockdown ──────────────────

exports.onSecuritySettingsChanged = fns.firestore
  .document("companies/{companyId}/settings/security")
  .onUpdate(async (change, context) => {
    const { companyId } = context.params;
    const before = change.before.data();
    const after = change.after.data();

    // Log the security setting change
    const changedFields = [];
    for (const key of Object.keys(after)) {
      if (JSON.stringify(before[key]) !== JSON.stringify(after[key])) {
        changedFields.push(key);
      }
    }

    if (changedFields.length > 0) {
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "settingChange",
        description: `Security settings updated: ${changedFields.join(", ")}`,
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
        metadata: { changedFields },
      });
    }

    // Emergency lockdown activated — force sign out all operator sessions
    if (!before.emergencyLockdown && after.emergencyLockdown) {
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "emergencyLockdown",
        description: "Emergency lockdown ACTIVATED — all operator sessions locked",
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
      });
    }

    if (before.emergencyLockdown && !after.emergencyLockdown) {
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "emergencyLockdown",
        description: "Emergency lockdown DEACTIVATED",
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
      });
    }
  });

// ─── Scheduled: Audit Log Cleanup ───────────────────────────────────────────

exports.cleanupAuditLogs = fns.pubsub
  .schedule("every 24 hours")
  .onRun(async () => {
    const retentionDays = 365;
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - retentionDays);

    const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoff);
    const batch = db.batch();
    let count = 0;

    const snap = await db.collectionGroup("auditLog")
      .where("timestamp", "<", cutoffTimestamp)
      .limit(500)
      .get();

    snap.docs.forEach((doc) => {
      batch.delete(doc.ref);
      count++;
    });

    if (count > 0) {
      await batch.commit();
      console.log(`Deleted ${count} audit logs older than ${retentionDays} days`);
    }

    return null;
  });

// ─── Scheduled: Password Expiry Check ───────────────────────────────────────

exports.checkPasswordExpiry = fns.pubsub
  .schedule("every 24 hours")
  .onRun(async () => {
    const expiryDays = 90;
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - expiryDays);

    const operators = await db.collectionGroup("operators")
      .where("isActive", "==", true)
      .get();

    const batch = db.batch();
    let flagged = 0;
    const toNotify = [];

    operators.docs.forEach((doc) => {
      const data = doc.data();
      const lastChanged = data.passwordLastChanged;

      // Only newly-expired (not already flagged) — avoids re-notifying every run.
      if ((!lastChanged || lastChanged.toDate() < cutoff) && !data.mustChangePassword) {
        batch.update(doc.ref, { mustChangePassword: true });
        flagged++;
        toNotify.push({ email: data.email || null, companyId: doc.ref.parent.parent?.id || null });
      }
    });

    if (flagged > 0) {
      await batch.commit();
      console.log(`Flagged ${flagged} operators for password change (expired > ${expiryDays} days)`);
      for (const o of toNotify) {
        if (!o.email || !o.companyId) continue;
        await notifyContact({
          to: { email: o.email },
          companyId: o.companyId,
          subject: `${BRAND.name}: time to update your password`,
          notif: ({
            category: "account",
            link: "/settings/mfa",
            operatorEmail: o.email,
            accent: "warn",
            heading: "Password expired",
            intro: `Your ${BRAND.name} password is more than ${expiryDays} days old. You'll be asked to set a new one at your next sign-in.`,
            note: "Choosing a fresh password regularly keeps your account secure.",
          }),
        }).catch((e) => console.warn("password-expiry notice failed:", e.message));
      }
    }

    return null;
  });

// ─── Scheduled: Inactive Operator Deactivation ──────────────────────────────

exports.deactivateInactiveOperators = fns.pubsub
  .schedule("every 168 hours")
  .timeZone("Asia/Kolkata")
  .onRun(async () => {
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - 90);

    const operators = await db.collectionGroup("operators")
      .where("isActive", "==", true)
      .get();

    const batch = db.batch();
    let deactivated = 0;
    const byCompany = {};

    operators.docs.forEach((doc) => {
      const data = doc.data();
      const lastLogin = data.lastLoginAt;

      // Never auto-deactivate a company owner/admin. With the live-session
      // re-check, isActive:false on the admin's own mirror doc would reject every
      // guarded callable (and delete the session) with no in-app reactivation path
      // — the activate toggle is hidden for admin operators — hard-locking them out.
      if (data.role === "companyAdmin" || data.role === "admin"
        || data.isCompanyAdmin === true || data.isAdmin === true) {
        return;
      }

      if (lastLogin && lastLogin.toDate() < cutoff) {
        batch.update(doc.ref, { isActive: false });
        deactivated++;
        const cid = doc.ref.parent.parent?.id;
        if (cid) byCompany[cid] = (byCompany[cid] || 0) + 1;
      }
    });

    if (deactivated > 0) {
      await batch.commit();
      console.log(`Auto-deactivated ${deactivated} operators`);
      // Each operator gets their own deactivation notice via onOperatorUpdated;
      // here we give the admin a per-company summary of the bulk action.
      for (const [cid, n] of Object.entries(byCompany)) {
        await _writeInApp({
          companyId: cid, category: "operator", severity: "warn", link: "/operators",
          title: `${n} operator${n === 1 ? "" : "s"} auto-deactivated`,
          body: `${n} operator${n === 1 ? "" : "s"} ${n === 1 ? "was" : "were"} deactivated after 90 days without signing in. Reactivate from Operators if still needed.`,
        }).catch((e) => console.warn("auto-deactivation summary failed:", e.message));
      }
    }

    return null;
  });

// ─── HTTP: Admin endpoint to bulk update operator shifts ────────────────────

exports.bulkUpdateShifts = fns.https.onCall(async (data, context) => {
  const { companyId, operatorIds, shiftStart, shiftEnd, shiftDays, shiftRestricted } = data;

  if (!companyId || !operatorIds || !Array.isArray(operatorIds)) {
    throw new functions.https.HttpsError("invalid-argument", "companyId and operatorIds array required");
  }

  // Authorize via the server-issued session token — caller must be an admin of
  // THIS company. Replaces the dead `token.admin` custom-claim check.
  await _requireAdminSession(data, companyId);

  const batch = db.batch();
  for (const id of operatorIds) {
    const ref = db.collection(`companies/${companyId}/operators`).doc(id);
    batch.update(ref, {
      shiftRestricted: shiftRestricted !== false,
      shiftStart: shiftStart || null,
      shiftEnd: shiftEnd || null,
      shiftDays: shiftDays || [],
    });
  }

  await batch.commit();
  return { updated: operatorIds.length };
});

// ─── HTTP: Reset operator password flag ─────────────────────────────────────

exports.forcePasswordReset = fns.https.onCall(async (data, context) => {
  const { companyId, operatorId } = data;
  if (!companyId || !operatorId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId and operatorId required");
  }

  // Authorize via the server-issued session token — caller must be an admin of
  // THIS company. Replaces the dead `token.admin` custom-claim check.
  const _as = await _requireAdminSession(data, companyId);

  await db.collection(`companies/${companyId}/operators`).doc(operatorId).update({
    mustChangePassword: true,
  });

  await db.collection(`companies/${companyId}/auditLog`).add({
    event: "passwordReset",
    description: `Password reset forced for operator ${operatorId}`,
    user: _as.email || "admin",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    success: true,
  });

  // Tell the operator their password must be reset (best-effort).
  try {
    const opDoc = await db.collection(`companies/${companyId}/operators`).doc(operatorId).get();
    const op = opDoc.exists ? (opDoc.data() || {}) : {};
    if (op.email) {
      await notifyContact({
        to: { email: op.email, phone: op.phone || null, name: op.name || "there" },
        companyId,
        critical: true,
        subject: `${BRAND.name}: please reset your password`,
        notif: ({
          category: "account",
          link: "/settings/mfa",
          operatorEmail: op.email,
          accent: "warn",
          heading: "Password reset required",
          intro: `Your administrator has required a password reset on your ${BRAND.name} account. You'll be prompted to set a new password at your next sign-in.`,
          note: "If you didn't expect this, contact your administrator.",
        }),
      });
    }
  } catch (e) {
    console.warn("force-reset notice failed:", e.message);
  }

  return { success: true };
});

// ─── Trigger: Login audit — update operator lastLoginAt + security alerts ───

// Firestore doc-id-safe key for a user identifier (emails can't contain "/" but
// guard anyway so a malformed `user` value can't escape the collection).
function _alertDocId(user) {
  return String(user || "unknown").replace(/[/\\#?]/g, "_").slice(0, 256);
}

exports.onAuditLogCreated = fns.firestore
  .document("companies/{companyId}/auditLog/{logId}")
  .onCreate(async (snap, context) => {
    const { companyId } = context.params;
    const data = snap.data();

    // Update operator login stats
    if (data.event === "login" && data.success) {
      const email = data.user;
      if (email && email !== "unknown") {
        const opSnap = await db.collection(`companies/${companyId}/operators`)
          .where("email", "==", email)
          .limit(1)
          .get();

        if (!opSnap.empty) {
          await opSnap.docs[0].ref.update({
            lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
            loginCount: admin.firestore.FieldValue.increment(1),
          });
        }
      }
    }

    // A successful login clears the per-user failed-login alert cooldown so the
    // next genuine streak can alert again.
    if (data.event === "login" && data.success && data.user && data.user !== "unknown") {
      await db.doc(`companies/${companyId}/login_alert_state/${_alertDocId(data.user)}`)
        .delete().catch(() => {});
    }

    // Failed login alert — notify admin only on 3 ACTUALLY-CONSECUTIVE failures
    // from the same user, and at most once per cooldown window (avoid spamming
    // the free in-app channel on every subsequent failure).
    if (data.event === "login" && !data.success && data.user && data.user !== "unknown") {
      // Two queries that both fit the EXISTING (event,user,success,timestamp)
      // index — no new composite index needed:
      //  1) the user's last 3 FAILURES,
      //  2) whether a SUCCESS landed after the oldest of those 3.
      // A success newer than the oldest failure breaks the streak, so only an
      // unbroken run of 3 failures counts as "consecutive".
      const recentFails = await db.collection(`companies/${companyId}/auditLog`)
        .where("event", "==", "login")
        .where("user", "==", data.user)
        .where("success", "==", false)
        .orderBy("timestamp", "descending")
        .limit(3)
        .get();
      let consecutiveFails = recentFails.docs.length >= 3;
      if (consecutiveFails) {
        const oldestFailTs = recentFails.docs[recentFails.docs.length - 1].data().timestamp;
        if (oldestFailTs) {
          const interveningSuccess = await db.collection(`companies/${companyId}/auditLog`)
            .where("event", "==", "login")
            .where("user", "==", data.user)
            .where("success", "==", true)
            .where("timestamp", ">", oldestFailTs)
            .orderBy("timestamp", "descending")
            .limit(1)
            .get();
          if (!interveningSuccess.empty) consecutiveFails = false;
        }
      }

      if (consecutiveFails) {
        // Per-user cooldown so we alert once per streak, not on every failure.
        const ALERT_COOLDOWN_MS = 15 * 60 * 1000;
        const stateRef = db.doc(`companies/${companyId}/login_alert_state/${_alertDocId(data.user)}`);
        const shouldAlert = await db.runTransaction(async (tx) => {
          const st = await tx.get(stateRef);
          const lastMs = (st.exists && st.data().lastAlertAt && st.data().lastAlertAt.toMillis)
            ? st.data().lastAlertAt.toMillis() : 0;
          if (Date.now() - lastMs < ALERT_COOLDOWN_MS) return false;
          tx.set(stateRef, { lastAlertAt: admin.firestore.FieldValue.serverTimestamp(), user: data.user });
          return true;
        }).catch(() => false);

        if (shouldAlert) {
          await sendAdminNotification(
            "Security Alert: Repeated Failed Logins",
            `${data.user} has 3+ consecutive failed login attempts from ${data.machine || data.ip || "unknown machine"}.`,
            { companyId, sms: { template: "securityAlert", vars: ["repeated failed logins"] } }
          );
        }
      }
    }

    // Lockdown activation alert
    if (data.event === "emergencyLockdown" && data.description.includes("ACTIVATED")) {
      await sendAdminNotification(
        "EMERGENCY LOCKDOWN ACTIVATED",
        "All operator sessions have been locked. Only admin access remains.",
        { companyId, sms: { template: "securityAlert", vars: ["emergency lockdown activated"] } }
      );
    }
  });

// ─── Trigger: Security settings — notify on critical changes ────────────────

exports.onSecurityCriticalChange = fns.firestore
  .document("companies/{companyId}/settings/security")
  .onUpdate(async (change, context) => {
    const { companyId } = context.params;
    const before = change.before.data();
    const after = change.after.data();

    // Notify if IP whitelist disabled (potential breach)
    if (before.ipWhitelistEnabled && !after.ipWhitelistEnabled) {
      await sendAdminNotification(
        "Security: IP Whitelist Disabled",
        "IP whitelist has been disabled. All IPs can now access the system.",
        { companyId, sms: { template: "securityAlert", vars: ["IP whitelist disabled"] } }
      );
    }

    // Notify if encryption disabled
    if (before.encryptBackups && !after.encryptBackups) {
      await sendAdminNotification(
        "Security: Backup Encryption Disabled",
        "Local backup encryption has been turned off.",
        { companyId, sms: { template: "securityAlert", vars: ["backup encryption disabled"] } }
      );
    }

    // Notify if audit logging disabled
    if (before.auditEnabled && !after.auditEnabled) {
      await sendAdminNotification(
        "Security: Audit Logging Disabled",
        "Audit trail has been disabled. Activity will not be recorded.",
        { companyId, sms: { template: "securityAlert", vars: ["audit logging disabled"] } }
      );
    }
  });

// ═══════════════════════════════════════════════════════════════════════════════
// GATE CONTROL BACKEND
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Gate Settings Changed: Audit trail ────────────────────────────────────────

exports.onGateSettingsChanged = fns.firestore
  .document("companies/{companyId}/sites/{siteId}/weighbridges/{weighbridgeId}/settings/gateControl")
  .onUpdate(async (change, context) => {
    const { companyId } = context.params;
    const before = change.before.data();
    const after = change.after.data();

    const changedFields = [];
    for (const key of Object.keys(after)) {
      if (key === "updatedAt") continue;
      if (JSON.stringify(before[key]) !== JSON.stringify(after[key])) {
        changedFields.push(key);
      }
    }

    if (changedFields.length === 0) return;

    await db.collection(`companies/${companyId}/auditLog`).add({
      event: "gateSettingChange",
      description: `Gate control settings updated: ${changedFields.join(", ")}`,
      user: "admin",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      success: true,
      metadata: { changedFields },
    });

    // Notify if gate system disabled
    if (before.enabled && !after.enabled) {
      await sendAdminNotification(
        "Gate Control System Disabled",
        "The gate automation system has been turned off.",
        { companyId, sms: { template: "gateAlert", vars: ["gate control disabled"] } }
      );
    }

    // Notify if safety features disabled
    if (before.emergencyStop && !after.emergencyStop) {
      await sendAdminNotification(
        "Gate Safety: Emergency Stop Disabled",
        "Emergency stop has been disabled on the gate control system.",
        { companyId, sms: { template: "gateAlert", vars: ["emergency stop disabled"] } }
      );
    }
    if (before.interlockGates && !after.interlockGates) {
      await sendAdminNotification(
        "Gate Safety: Interlock Disabled",
        "Gate interlock safety feature has been turned off. Both gates can now open simultaneously.",
        { companyId, sms: { template: "gateAlert", vars: ["gate interlock disabled"] } }
      );
    }
  });

// ─── Gate Event Logging ────────────────────────────────────────────────────────

exports.logGateEvent = fns.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  }

  const { companyId, siteId, weighbridgeId, gateId, action, success, message, weighmentId, vehicleNumber, rfidTag, responseTimeMs } = data;

  if (!companyId || !siteId || !weighbridgeId || !gateId || !action) {
    throw new functions.https.HttpsError("invalid-argument", "companyId, siteId, weighbridgeId, gateId, and action are required");
  }

  const validActions = ["open", "close", "test", "emergency_stop", "auto_close", "rfid_trigger"];
  if (!validActions.includes(action)) {
    throw new functions.https.HttpsError("invalid-argument", `Invalid action: ${action}`);
  }

  const wbPath = `companies/${companyId}/sites/${siteId}/weighbridges/${weighbridgeId}`;

  const event = {
    event: "gateEvent",
    gateId,
    action,
    success: success !== false,
    message: message || "",
    user: context.auth.token.email || "unknown",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    metadata: {},
  };

  if (weighmentId) event.metadata.weighmentId = weighmentId;
  if (vehicleNumber) event.metadata.vehicleNumber = vehicleNumber;
  if (rfidTag) event.metadata.rfidTag = rfidTag;
  if (responseTimeMs) event.metadata.responseTimeMs = responseTimeMs;

  await db.collection(`${wbPath}/gateEvents`).add(event);

  // Also log to main audit log for critical actions
  if (action === "emergency_stop" || (!success && action !== "test")) {
    await db.collection(`companies/${companyId}/auditLog`).add({
      event: "gateEvent",
      description: `Gate ${gateId} ${action}: ${message || (success ? "OK" : "FAILED")}`,
      user: event.user,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      success: success !== false,
      metadata: event.metadata,
    });
  }

  return { logged: true };
});

// ─── Remote Gate Trigger (cloud-initiated open/close) ─────────────────────────

exports.triggerGate = fns.https.onCall(async (data, context) => {
  const { companyId, siteId, weighbridgeId, gateId, action } = data;

  if (!companyId || !siteId || !weighbridgeId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId, siteId, and weighbridgeId required");
  }
  // Caller must hold a valid session for THIS company (any role — operators
  // trigger gates). Replaces the old dead `context.auth.token.admin` check that
  // never denied anyone under anonymous auth.
  const _gs = await _requireSession(data);
  if (_gs.companyId !== companyId) {
    throw new functions.https.HttpsError("permission-denied", "Not authorized for this company.");
  }
  if (!gateId || !["entry", "exit"].includes(gateId)) {
    throw new functions.https.HttpsError("invalid-argument", "gateId must be 'entry' or 'exit'");
  }
  if (!action || !["open", "close"].includes(action)) {
    throw new functions.https.HttpsError("invalid-argument", "action must be 'open' or 'close'");
  }

  const wbPath = `companies/${companyId}/sites/${siteId}/weighbridges/${weighbridgeId}`;

  // Load current gate config
  const configDoc = await db.doc(`${wbPath}/settings/gateControl`).get();
  if (!configDoc.exists) {
    throw new functions.https.HttpsError("failed-precondition", "Gate control not configured");
  }

  const config = configDoc.data();
  if (!config.enabled) {
    throw new functions.https.HttpsError("failed-precondition", "Gate system is disabled");
  }

  const gateEnabled = gateId === "entry" ? config.entryEnabled : config.exitEnabled;
  if (!gateEnabled) {
    throw new functions.https.HttpsError("failed-precondition", `${gateId} gate is disabled`);
  }

  // Interlock check: if opening one gate, verify the other is not open
  if (action === "open" && config.interlockGates) {
    const otherGateId = gateId === "entry" ? "exit" : "entry";
    const recentEvents = await db.collection(`${wbPath}/gateEvents`)
      .where("gateId", "==", otherGateId)
      .where("success", "==", true)
      .orderBy("timestamp", "desc")
      .limit(1)
      .get();

    if (!recentEvents.empty) {
      const lastEvent = recentEvents.docs[0].data();
      if (lastEvent.action === "open") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          `Interlock: ${otherGateId} gate appears to be open`
        );
      }
    }
  }

  // Write a command document that the client app watches
  await db.collection(`${wbPath}/gateCommands`).add({
    gateId,
    action,
    requestedBy: context.auth.token.email || "admin",
    status: "pending",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Log the remote trigger
  await db.collection(`${wbPath}/gateEvents`).add({
    event: "gateEvent",
    gateId,
    action: `remote_${action}`,
    success: true,
    message: `Remote ${action} requested`,
    user: context.auth.token.email || "admin",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    metadata: { remote: true },
  });

  return { success: true, message: `${action} command sent to ${gateId} gate` };
});

// ─── RFID Tag Validation ──────────────────────────────────────────────────────

exports.validateRfidTag = fns.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  }

  const { companyId, siteId, weighbridgeId, tagId, gateId } = data;

  if (!companyId || !siteId || !weighbridgeId || !tagId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId, siteId, weighbridgeId, and tagId are required");
  }

  const wbPath = `companies/${companyId}/sites/${siteId}/weighbridges/${weighbridgeId}`;

  // Check gate config
  const configDoc = await db.doc(`${wbPath}/settings/gateControl`).get();
  if (!configDoc.exists || !configDoc.data().rfidEnabled) {
    return { valid: false, reason: "RFID not enabled" };
  }

  // Look up tag in registered vehicles
  const vehicleSnap = await db.collection(`companies/${companyId}/vehicles`)
    .where("rfidTag", "==", tagId)
    .where("active", "==", true)
    .limit(1)
    .get();

  if (vehicleSnap.empty) {
    await db.collection(`${wbPath}/gateEvents`).add({
      event: "gateEvent",
      gateId: gateId || "unknown",
      action: "rfid_trigger",
      success: false,
      message: `Unregistered RFID tag: ${tagId}`,
      user: "rfid_reader",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      metadata: { rfidTag: tagId },
    });

    // Unauthorized vehicle at the gate — in-app alert, throttled to once per
    // ~20 min per company (reusing the alert cooldown) so random scans don't spam.
    if (await _alertSmsAllowed(companyId, "unknownRfid")) {
      await _writeInApp({
        companyId, category: "security", severity: "warn", link: "/settings/gate-control",
        title: "Unknown vehicle at gate",
        body: `An unregistered RFID tag (${tagId}) was scanned at ${gateId || "the"} gate. If it's a known vehicle, register its tag — otherwise it may be an unauthorized entry attempt.`,
      }).catch((e) => console.warn("unknown-rfid alert failed:", e.message));
    }

    return { valid: false, reason: "Tag not registered" };
  }

  const vehicle = vehicleSnap.docs[0].data();

  // Check if vehicle is blacklisted
  if (vehicle.blacklisted) {
    await db.collection(`${wbPath}/gateEvents`).add({
      event: "gateEvent",
      gateId: gateId || "unknown",
      action: "rfid_trigger",
      success: false,
      message: `Blacklisted vehicle: ${vehicle.number}`,
      user: "rfid_reader",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      metadata: { rfidTag: tagId, vehicleNumber: vehicle.number },
    });

    await sendAdminNotification(
      "Gate Alert: Blacklisted Vehicle",
      `Blacklisted vehicle ${vehicle.number} scanned at ${gateId || "unknown"} gate.`,
      { companyId, sms: { template: "gateAlert", vars: ["blacklisted vehicle at gate"] } }
    );

    return { valid: false, reason: "Vehicle is blacklisted", vehicleNumber: vehicle.number };
  }

  // Valid tag — log and approve
  await db.collection(`${wbPath}/gateEvents`).add({
    event: "gateEvent",
    gateId: gateId || "entry",
    action: "rfid_trigger",
    success: true,
    message: `RFID validated: ${vehicle.number}`,
    user: "rfid_reader",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    metadata: { rfidTag: tagId, vehicleNumber: vehicle.number, vehicleId: vehicleSnap.docs[0].id },
  });

  return {
    valid: true,
    vehicleNumber: vehicle.number,
    vehicleId: vehicleSnap.docs[0].id,
    vehicleType: vehicle.type || null,
    customer: vehicle.customer || null,
  };
});

// ─── RFID Tag Registration ────────────────────────────────────────────────────

exports.registerRfidTag = fns.https.onCall(async (data, context) => {
  const { companyId, vehicleId, tagId } = data;

  if (!companyId || !vehicleId || !tagId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId, vehicleId, and tagId are required");
  }

  // Authorize via the server-issued session token — caller must be an admin of
  // THIS company. Replaces the dead `token.admin` custom-claim check.
  const _as = await _requireAdminSession(data, companyId);

  // Check tag not already assigned
  const existing = await db.collection(`companies/${companyId}/vehicles`)
    .where("rfidTag", "==", tagId)
    .limit(1)
    .get();

  if (!existing.empty && existing.docs[0].id !== vehicleId) {
    throw new functions.https.HttpsError(
      "already-exists",
      `Tag already assigned to vehicle ${existing.docs[0].data().number}`
    );
  }

  await db.collection(`companies/${companyId}/vehicles`).doc(vehicleId).update({
    rfidTag: tagId,
    rfidRegisteredAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await db.collection(`companies/${companyId}/auditLog`).add({
    event: "rfidRegistration",
    description: `RFID tag ${tagId} registered to vehicle ${vehicleId}`,
    user: _as.email || "admin",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    success: true,
    metadata: { vehicleId, tagId },
  });

  return { success: true };
});

// ─── Gate Event Cleanup (older than 30 days) ──────────────────────────────────

exports.cleanupGateEvents = fns.pubsub
  .schedule("every 24 hours")
  .onRun(async () => {
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - 30);
    const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoff);

    const batch = db.batch();
    let count = 0;

    const snap = await db.collectionGroup("gateEvents")
      .where("timestamp", "<", cutoffTimestamp)
      .limit(500)
      .get();

    snap.docs.forEach((doc) => {
      batch.delete(doc.ref);
      count++;
    });

    if (count > 0) {
      await batch.commit();
      console.log(`Deleted ${count} gate events older than 30 days`);
    }

    return null;
  });

// ─── Gate Command Watcher: Clean up stale commands ────────────────────────────

exports.cleanupStaleGateCommands = fns.pubsub
  .schedule("every 1 hours")
  .onRun(async () => {
    const cutoff = new Date();
    cutoff.setMinutes(cutoff.getMinutes() - 5);
    const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoff);

    const batch = db.batch();
    let count = 0;

    const snap = await db.collectionGroup("gateCommands")
      .where("status", "==", "pending")
      .where("createdAt", "<", cutoffTimestamp)
      .limit(100)
      .get();

    snap.docs.forEach((doc) => {
      batch.update(doc.ref, { status: "expired" });
      count++;
    });

    if (count > 0) {
      await batch.commit();
      console.log(`Marked ${count} stale gate commands as expired`);
    }

    return null;
  });

// ─── Gate Status Endpoint (for dashboard/monitoring) ──────────────────────────

exports.getGateStatus = fns.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  }

  const { companyId, siteId, weighbridgeId } = data;
  if (!companyId || !siteId || !weighbridgeId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId, siteId, and weighbridgeId required");
  }

  const wbPath = `companies/${companyId}/sites/${siteId}/weighbridges/${weighbridgeId}`;

  // Get config
  const configDoc = await db.doc(`${wbPath}/settings/gateControl`).get();
  const config = configDoc.exists ? configDoc.data() : {};

  // Get last events for each gate
  const [entryEvents, exitEvents] = await Promise.all([
    db.collection(`${wbPath}/gateEvents`)
      .where("gateId", "==", "entry")
      .where("success", "==", true)
      .orderBy("timestamp", "desc")
      .limit(5)
      .get(),
    db.collection(`${wbPath}/gateEvents`)
      .where("gateId", "==", "exit")
      .where("success", "==", true)
      .orderBy("timestamp", "desc")
      .limit(5)
      .get(),
  ]);

  // Today's stats
  const todayStart = new Date();
  todayStart.setHours(0, 0, 0, 0);
  const todayTimestamp = admin.firestore.Timestamp.fromDate(todayStart);

  const todayEvents = await db.collection(`${wbPath}/gateEvents`)
    .where("timestamp", ">=", todayTimestamp)
    .get();

  const stats = {
    totalToday: todayEvents.docs.length,
    opensToday: todayEvents.docs.filter(d => d.data().action === "open" && d.data().success).length,
    failuresToday: todayEvents.docs.filter(d => !d.data().success).length,
    rfidScansToday: todayEvents.docs.filter(d => d.data().action === "rfid_trigger").length,
  };

  return {
    enabled: config.enabled || false,
    entryEnabled: config.entryEnabled || false,
    exitEnabled: config.exitEnabled || false,
    interlockActive: config.interlockGates || false,
    rfidEnabled: config.rfidEnabled || false,
    lastEntryEvent: entryEvents.empty ? null : entryEvents.docs[0].data(),
    lastExitEvent: exitEvents.empty ? null : exitEvents.docs[0].data(),
    stats,
  };
});

// ─── Helper: Send notification to admin devices ─────────────────────────────

// Per-(company, template) SMS throttle. Some alerts fire on machine- or
// attacker-repeatable events (a failed-login storm, a blacklisted truck the RFID
// reader re-scans), which would otherwise mean one paid SMS PER event. In-app +
// email stay responsive; only the SMS is rate-limited. Fail-open so a transient
// Firestore error never suppresses a genuine alert.
const ALERT_SMS_COOLDOWN_MINUTES = 20;
async function _alertSmsAllowed(companyId, template) {
  if (!companyId || !template) return true;
  const ref = db.collection("notification_cooldowns").doc(`${companyId}_${template}`);
  try {
    const snap = await ref.get();
    if (snap.exists) {
      const last = snap.data().lastSentAt;
      if (last && typeof last.toMillis === "function" &&
          Date.now() - last.toMillis() < ALERT_SMS_COOLDOWN_MINUTES * 60 * 1000) {
        return false;
      }
    }
    await ref.set({
      companyId, template,
      lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return true;
  } catch (e) {
    console.warn("alert SMS cooldown check failed:", e.message);
    return true;
  }
}

// Targeted push to a company's admin devices (per-operator FCM tokens stored in
// operators.fcmTokens). macOS-only on the client side; here it's just best-effort
// multicast with dead-token cleanup. Never throws; no tokens = silent no-op.
async function _pushToCompanyAdmins(companyId, title, body) {
  if (!companyId) return;
  try {
    const opSnap = await db.collection(`companies/${companyId}/operators`)
      .where("role", "==", "companyAdmin").get();
    const entries = [];
    opSnap.forEach((doc) => {
      const toks = doc.data().fcmTokens;
      if (Array.isArray(toks)) toks.forEach((t) => { if (t) entries.push({ token: t, ref: doc.ref }); });
    });
    if (!entries.length) return;
    const res = await admin.messaging().sendEachForMulticast({
      tokens: entries.map((e) => e.token),
      notification: { title, body },
      data: { type: "security_alert", companyId },
    });
    res.responses.forEach((r, i) => {
      if (r.success) return;
      const code = r.error && r.error.code;
      if (code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token" ||
          code === "messaging/invalid-argument") {
        entries[i].ref.update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(entries[i].token),
        }).catch(() => {});
      }
    });
  } catch (e) {
    console.warn("admin device push failed:", e.message);
  }
}

// ── In-app notification engine ───────────────────────────────────────────────
// Single writer for in-app notifications (companies/{id}/notifications). Enriched
// schema: category (security|billing|licence|operator|kyc|backup|account|welcome|
// system), severity (info|warn|critical), link (in-app route to deep-link to),
// operatorEmail (per-operator targeting; "*" sentinel = company-wide, the
// default). The client filters with operatorEmail in ["*", myEmail]. `type`
// mirrors category for backward-compat with the existing UI. In-app is FREE.
async function _writeInApp({ companyId, operatorEmail = "*", category = "system", severity = "info", title, body = "", link = null }) {
  if (!companyId || !title) return;
  try {
    await db.collection(`companies/${companyId}/notifications`).add({
      title, body, category, severity, link, operatorEmail,
      type: category,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.warn("in-app notification write failed:", e.message);
  }
}

async function sendAdminNotification(title, body, opts = {}) {
  const { companyId = null, sms = null } = opts;
  // Broadcast FCM (topic) — the in-app entry itself is written by notifyContact.
  try {
    await admin.messaging().send({
      topic: "admin_security_alerts",
      notification: { title, body },
      data: { type: "security_alert", title, body, companyId: companyId || "" },
      apns: { payload: { aps: { sound: "default", badge: 1 } } },
    });
  } catch (e) {
    console.log("FCM send failed (may not be configured):", e.message);
  }

  // Targeted push to the company's admin devices (best-effort).
  if (companyId) await _pushToCompanyAdmins(companyId, title, body);

  // In-app (free) + email (always) + SMS (urgent, throttled) via notifyContact.
  if (companyId) {
    const smsToSend = sms && (await _alertSmsAllowed(companyId, sms.template)) ? sms : null;
    await notifyContact({
      companyId,
      critical: true,
      subject: `${BRAND.name} security alert: ${title}`,
      notif: ({
        heading: title,
        intro: body,
        accent: "danger",
        category: "security",
        link: "/settings/mfa",
        note: `If you did not expect this alert, secure your account and contact ${BRAND.support}.`,
      }),
      sms: smsToSend, // {template, vars} for urgent alerts; null = email + in-app only
    }).catch((e) => console.warn("admin alert fan-out failed:", e.message));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WEIGHMENT BACKEND
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Weighment Created: RST counter, customer stats, audit ──────────────────

exports.onWeighmentCreated = fns.firestore
  .document("companies/{companyId}/sites/{siteId}/weighbridges/{weighbridgeId}/weighments/{weighmentId}")
  .onCreate(async (snap, context) => {
    const { companyId, siteId, weighbridgeId } = context.params;
    const wbPath = `companies/${companyId}/sites/${siteId}/weighbridges/${weighbridgeId}`;
    const data = snap.data();
    const updates = {};

    // Auto-assign RST number if not already set
    if (!data.rst) {
      const counterRef = db.collection(`${wbPath}/counters`).doc("weighments");
      const counterSnap = await counterRef.get();
      let nextRst = 1;

      if (counterSnap.exists) {
        nextRst = (counterSnap.data().lastRst || 0) + 1;
      }

      await counterRef.set({ lastRst: nextRst }, { merge: true });
      updates.rst = nextRst;
    }

    // Set createdAt if missing
    if (!data.createdAt) {
      updates.createdAt = admin.firestore.FieldValue.serverTimestamp();
    }

    if (Object.keys(updates).length > 0) {
      await snap.ref.update(updates);
    }

    // Update customer stats
    const customerName = data.customerName;
    if (customerName && customerName !== "[Archived]") {
      const custSnap = await db.collection(`companies/${companyId}/customers`)
        .where("name", "==", customerName)
        .limit(1)
        .get();

      if (!custSnap.empty) {
        const custUpdates = {
          totalWeighments: admin.firestore.FieldValue.increment(1),
        };
        if (data.netWeight) {
          custUpdates.totalNetWeight = admin.firestore.FieldValue.increment(data.netWeight);
        }
        await custSnap.docs[0].ref.update(custUpdates);
      }
    }

    // Audit log
    await db.collection(`companies/${companyId}/auditLog`).add({
      event: "weighmentCreated",
      description: `Weighment created: ${data.vehicleNumber || "--"} / ${customerName || "--"} / ${data.material || "--"}`,
      user: data.operatorId || "system",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      success: true,
      metadata: {
        weighmentId: context.params.weighmentId,
        vehicle: data.vehicleNumber || null,
        customer: customerName || null,
        material: data.material || null,
        status: data.status || "pending",
      },
    });
  });

// ─── Weighment Updated: Status changes, customer transfer, face sync ────────

exports.onWeighmentUpdated = fns.firestore
  .document("companies/{companyId}/sites/{siteId}/weighbridges/{weighbridgeId}/weighments/{weighmentId}")
  .onUpdate(async (change, context) => {
    const { companyId } = context.params;
    const before = change.before.data();
    const after = change.after.data();

    // Status changed to completed — update customer stats for net weight
    if (before.status !== "completed" && after.status === "completed") {
      const customerName = after.customerName;
      if (customerName && customerName !== "[Archived]") {
        const custSnap = await db.collection(`companies/${companyId}/customers`)
          .where("name", "==", customerName)
          .limit(1)
          .get();

        if (!custSnap.empty) {
          const netDelta = (after.netWeight || 0) - (before.netWeight || 0);
          if (netDelta !== 0) {
            await custSnap.docs[0].ref.update({
              totalNetWeight: admin.firestore.FieldValue.increment(netDelta),
            });
          }
        }
      }

      // Audit
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "weighmentCompleted",
        description: `Weighment completed: ${after.vehicleNumber || "--"} — Net: ${after.netWeight || 0} kg`,
        user: after.operatorId || "system",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
        metadata: {
          weighmentId: context.params.weighmentId,
          grossWeight: after.grossWeight || null,
          tareWeight: after.tareWeight || null,
          netWeight: after.netWeight || null,
        },
      });

      // Weighment receipt to the customer — OFF by default. Opt-in per
      // weighbridge via settings/general.sendWeighmentReceipts, and only when a
      // customer phone is present on the weighment. Best-effort.
      try {
        const { siteId, weighbridgeId } = context.params;
        const custPhone = (after.customerPhone || "").toString().trim();
        if (custPhone) {
          const genSnap = await db.doc(
            `companies/${companyId}/sites/${siteId}/weighbridges/${weighbridgeId}/settings/general`).get();
          if (genSnap.exists && genSnap.data().sendWeighmentReceipts === true) {
            const ticket = after.serialNumber || after.ticketNumber || after.slipNumber || context.params.weighmentId;
            const vehicle = after.vehicleNumber || "--";
            const net = Math.round(after.netWeight || 0);
            if (await _consumeQuota(companyId, "sms")) {
              await _sendDltSms("weighmentReceipt", custPhone, [String(ticket), String(vehicle), String(net)]);
            }
            if (after.customerEmail && await _consumeQuota(companyId, "email")) {
              const subject = `${BRAND.name}: weighment receipt ${ticket}`;
              // Plain HTML fallback (always works, image-block-safe).
              const fallbackHtml = buildBrandEmail({
                heading: "Weighment receipt",
                intro: `Your weighment for vehicle ${vehicle} has been recorded and confirmed.`,
                rows: [
                  ["Ticket", String(ticket)],
                  ["Vehicle", String(vehicle)],
                  ["Material", after.material || "--"],
                  ["Gross", `${Math.round(after.grossWeight || 0)} kg`],
                  ["Tare", `${Math.round(after.tareWeight || 0)} kg`],
                  ["Net weight", `${net} kg`],
                ],
                note: "Questions about this weighment? Contact the weighbridge operator.",
              });
              // Try the rendered receipt (inline image + PDF attachment); fall back to HTML.
              const receiptData = await _weighmentToReceiptData(companyId, after, ticket);
              const rendered = await _renderEmailAssets("receipt", receiptData, await _printerPageSize(companyId));
              if (rendered && rendered.imageUrl) {
                await _sendRenderedEmail(after.customerEmail, subject, {
                  imageUrl: rendered.imageUrl, pdfBase64: rendered.pdfBase64,
                  pdfName: `weighment-${receiptData.rst || ticket}.pdf`, fallbackHtml, alt: "Weighment receipt",
                });
              } else {
                await _sendBrandEmail(after.customerEmail, subject, fallbackHtml);
              }
            }
          }
        }
      } catch (e) {
        console.warn("weighment receipt failed:", e.message);
      }
    }

    // Customer transfer — reassign stats
    if (before.customerName !== after.customerName && before.customerName && after.customerName) {
      // Decrement old customer
      if (before.customerName !== "[Archived]") {
        const oldCust = await db.collection(`companies/${companyId}/customers`)
          .where("name", "==", before.customerName)
          .limit(1)
          .get();

        if (!oldCust.empty) {
          const decrements = { totalWeighments: admin.firestore.FieldValue.increment(-1) };
          if (after.netWeight) {
            decrements.totalNetWeight = admin.firestore.FieldValue.increment(-(after.netWeight));
          }
          await oldCust.docs[0].ref.update(decrements);
        }
      }

      // Increment new customer
      if (after.customerName !== "[Archived]") {
        const newCust = await db.collection(`companies/${companyId}/customers`)
          .where("name", "==", after.customerName)
          .limit(1)
          .get();

        if (!newCust.empty) {
          const increments = { totalWeighments: admin.firestore.FieldValue.increment(1) };
          if (after.netWeight) {
            increments.totalNetWeight = admin.firestore.FieldValue.increment(after.netWeight);
          }
          await newCust.docs[0].ref.update(increments);
        }
      }

      // Audit transfer
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "weighmentTransferred",
        description: `Weighment ${context.params.weighmentId} transferred: "${before.customerName}" → "${after.customerName}"`,
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
        metadata: {
          weighmentId: context.params.weighmentId,
          fromCustomer: before.customerName,
          toCustomer: after.customerName,
        },
      });
    }

    // Camera face sync
    if (after.status === "completed") {
      const customerName = after.customerName;
      if (customerName && customerName !== "[Archived]") {
        const snaps = after.cameraSnapshots;
        if (snaps) {
          const face = snaps.tare?.customer || snaps.gross?.customer;
          if (face) {
            const custSnap = await db.collection(`companies/${companyId}/customers`)
              .where("name", "==", customerName)
              .limit(1)
              .get();

            if (!custSnap.empty) {
              const custDoc = custSnap.docs[0];
              const custData = custDoc.data();
              const faceUpdates = { lastFace: face };
              if (!custData.firstFace) {
                faceUpdates.firstFace = face;
              }
              await custDoc.ref.update(faceUpdates);
            }
          }
        }
      }
    }
  });

// ─── Weighment Deleted: Decrement customer stats ────────────────────────────

exports.onWeighmentDeleted = fns.firestore
  .document("companies/{companyId}/sites/{siteId}/weighbridges/{weighbridgeId}/weighments/{weighmentId}")
  .onDelete(async (snap, context) => {
    const { companyId } = context.params;
    const data = snap.data();
    const customerName = data.customerName;

    if (customerName && customerName !== "[Archived]") {
      const custSnap = await db.collection(`companies/${companyId}/customers`)
        .where("name", "==", customerName)
        .limit(1)
        .get();

      if (!custSnap.empty) {
        const decrements = { totalWeighments: admin.firestore.FieldValue.increment(-1) };
        if (data.netWeight) {
          decrements.totalNetWeight = admin.firestore.FieldValue.increment(-(data.netWeight));
        }
        await custSnap.docs[0].ref.update(decrements);
      }
    }

    await db.collection(`companies/${companyId}/auditLog`).add({
      event: "weighmentDeleted",
      description: `Weighment deleted: ${data.vehicleNumber || "--"} / ${customerName || "--"}`,
      user: "admin",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      success: true,
      metadata: {
        weighmentId: context.params.weighmentId,
        vehicle: data.vehicleNumber || null,
        customer: customerName || null,
        netWeight: data.netWeight || null,
      },
    });
  });

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOMER BACKEND
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Customer Created: Set defaults ─────────────────────────────────────────

exports.onCustomerCreated = fns.firestore
  .document("companies/{companyId}/customers/{customerId}")
  .onCreate(async (snap, context) => {
    const { companyId } = context.params;
    const data = snap.data();
    const defaults = {};

    if (!data.createdAt) defaults.createdAt = admin.firestore.FieldValue.serverTimestamp();
    if (data.totalWeighments === undefined) defaults.totalWeighments = 0;
    if (data.totalNetWeight === undefined) defaults.totalNetWeight = 0;

    if (Object.keys(defaults).length > 0) {
      await snap.ref.update(defaults);
    }

    await db.collection(`companies/${companyId}/auditLog`).add({
      event: "customerCreated",
      description: `Customer created: ${data.name || "--"}`,
      user: "admin",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      success: true,
      metadata: {
        customerId: context.params.customerId,
        name: data.name || null,
        phone: data.phone || null,
      },
    });
  });

// ─── Customer Deleted (moved to recycle bin): Audit ─────────────────────────

exports.onCustomerArchived = fns.firestore
  .document("companies/{companyId}/customers_deleted/{customerId}")
  .onCreate(async (snap, context) => {
    const { companyId } = context.params;
    const data = snap.data();

    await db.collection(`companies/${companyId}/auditLog`).add({
      event: "customerArchived",
      description: `Customer archived: ${data.name || "--"} (${data.totalWeighments || 0} weighments)`,
      user: "admin",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      success: true,
      metadata: {
        customerId: context.params.customerId,
        name: data.name || null,
        totalWeighments: data.totalWeighments || 0,
        reason: data.deleteReason || null,
      },
    });
  });

// ─── Customer Restored from recycle bin: Audit ──────────────────────────────

exports.onCustomerRestoredFromBin = fns.firestore
  .document("companies/{companyId}/customers_deleted/{customerId}")
  .onDelete(async (snap, context) => {
    const { companyId } = context.params;
    const data = snap.data();

    // Check if the customer was actually restored (not permanently deleted)
    const restoredDoc = await db.collection(`companies/${companyId}/customers`).doc(context.params.customerId).get();
    if (restoredDoc.exists) {
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "customerRestored",
        description: `Customer restored: ${data.name || "--"}`,
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
        metadata: {
          customerId: context.params.customerId,
          name: data.name || null,
        },
      });
    }
  });

// ─── Customer Merge: Audit ──────────────────────────────────────────────────

exports.onCustomerMergeCreated = fns.firestore
  .document("companies/{companyId}/customer_merges/{mergeId}")
  .onCreate(async (snap, context) => {
    const { companyId } = context.params;
    const data = snap.data();

    await db.collection(`companies/${companyId}/auditLog`).add({
      event: "customerMerge",
      description: `Customers merged into "${data.primaryName || "--"}": ${(data.mergedNames || []).join(", ")}`,
      user: "admin",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      success: true,
      metadata: {
        mergeId: context.params.mergeId,
        primaryId: data.primaryId || null,
        primaryName: data.primaryName || null,
        mergedIds: data.mergedIds || [],
        mergedNames: data.mergedNames || [],
        weighmentsReassigned: data.weighmentsReassigned || 0,
      },
    });
  });

// ─── Customer Merge Reverted: Audit ─────────────────────────────────────────

exports.onCustomerMergeUpdated = fns.firestore
  .document("companies/{companyId}/customer_merges/{mergeId}")
  .onUpdate(async (change, context) => {
    const { companyId } = context.params;
    const before = change.before.data();
    const after = change.after.data();

    if (!before.reverted && after.reverted) {
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "customerMergeReverted",
        description: `Customer merge reverted: "${after.primaryName || "--"}" — ${(after.mergedNames || []).join(", ")} restored`,
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
        metadata: {
          mergeId: context.params.mergeId,
          primaryName: after.primaryName || null,
          mergedNames: after.mergedNames || [],
        },
      });
    }
  });

// ─── Customer Updated: Track name/phone changes ─────────────────────────────

exports.onCustomerUpdated = fns.firestore
  .document("companies/{companyId}/customers/{customerId}")
  .onUpdate(async (change, context) => {
    const { companyId } = context.params;
    const before = change.before.data();
    const after = change.after.data();

    // Log significant field changes
    const tracked = ["name", "phone", "address", "gstNumber"];
    const changes = [];
    for (const field of tracked) {
      if (before[field] !== after[field]) {
        changes.push(`${field}: "${before[field] || ""}" → "${after[field] || ""}"`);
      }
    }

    if (changes.length > 0) {
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "customerUpdated",
        description: `Customer "${after.name || "--"}" updated: ${changes.join(", ")}`,
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
        metadata: {
          customerId: context.params.customerId,
          changedFields: changes,
        },
      });
    }
  });

// ─── Vehicle blacklist toggle: audit + admin alert (security) ───────────────
exports.onVehicleUpdated = fns.firestore
  .document("companies/{companyId}/vehicles/{vehicleId}")
  .onUpdate(async (change, context) => {
    const { companyId } = context.params;
    const before = change.before.data();
    const after = change.after.data();
    if (!!before.blacklisted === !!after.blacklisted) return null; // only on toggle
    const num = after.number || after.vehicleNumber || context.params.vehicleId;
    await db.collection(`companies/${companyId}/auditLog`).add({
      event: after.blacklisted ? "vehicleBlacklisted" : "vehicleUnblacklisted",
      description: `Vehicle ${num} ${after.blacklisted ? "blacklisted" : "removed from blacklist"}`,
      user: "admin",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      success: true,
      metadata: { vehicleId: context.params.vehicleId },
    });
    await _writeInApp({
      companyId, category: "security", severity: "warn", link: "/customers",
      title: `Vehicle ${after.blacklisted ? "blacklisted" : "un-blacklisted"}`,
      body: `${num} is now ${after.blacklisted ? "blocked from gate entry" : "allowed at the gate again"}.`,
    }).catch((e) => console.warn("vehicle-blacklist alert failed:", e.message));
    return null;
  });

// ═══════════════════════════════════════════════════════════════════════════════
// OPERATOR BACKEND (additional triggers)
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Weighment Completed: Sync customer face (legacy alias removed) ─────────
// Face sync is now handled inside onWeighmentUpdated above.

// ─── Operator Archive/Restore + Face Enrollment audit ───────────────────────
// (extends existing onOperatorUpdated)

exports.onOperatorLifecycle = fns.firestore
  .document("companies/{companyId}/operators/{operatorId}")
  .onUpdate(async (change, context) => {
    const { companyId } = context.params;
    const before = change.before.data();
    const after = change.after.data();

    // Archive event
    if (!before.isArchived && after.isArchived) {
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "operatorArchived",
        description: `Operator archived: ${after.name || after.email}`,
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
        metadata: {
          operatorId: context.params.operatorId,
          permissionsRevoked: after.permissionsRevoked || false,
        },
      });
      // Notify the operator their access was revoked (mirrors operatorDeactivated).
      if (after.email || after.phone) {
        await notifyContact({
          to: { email: after.email || null, phone: after.phone || null, name: after.name || "there" },
          companyId,
          critical: true,
          subject: `${BRAND.name}: your operator access was removed`,
          notif: ({
            category: "operator",
            link: "/operators",
            operatorEmail: after.email || null,
            accent: "warn",
            heading: "Access removed",
            intro: `Hi ${after.name || "there"}, your operator account on ${BRAND.name} has been archived, so you can no longer sign in.`,
            note: `If you believe this is a mistake, contact your ${BRAND.name} administrator.`,
          }),
        }).catch((e) => console.warn("operator-archived notice failed:", e.message));
      }
    }

    // Restore event
    if (before.isArchived && !after.isArchived) {
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "operatorRestored",
        description: `Operator restored: ${after.name || after.email} (KYC reset, password change required)`,
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
        metadata: { operatorId: context.params.operatorId },
      });
    }

    // Face enrollment
    if (!before.facePhoto && after.facePhoto) {
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "faceEnrolled",
        description: `Face enrolled for operator: ${after.name || after.email}`,
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
        metadata: { operatorId: context.params.operatorId },
      });
    }

    // Face removed
    if (before.facePhoto && !after.facePhoto) {
      await db.collection(`companies/${companyId}/auditLog`).add({
        event: "faceRemoved",
        description: `Face enrollment removed for operator: ${after.name || after.email}`,
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
        metadata: { operatorId: context.params.operatorId },
      });
    }

  });

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MIGRATION: Flat → Multi-Site Hierarchy
// ═══════════════════════════════════════════════════════════════════════════════

exports.migrateToHierarchy = fns.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  }

  const { companyId, siteId, weighbridgeId } = data;
  if (!companyId || !siteId || !weighbridgeId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "companyId, siteId, and weighbridgeId are required"
    );
  }

  const companyPath = `companies/${companyId}`;
  const sitePath = `${companyPath}/sites/${siteId}`;
  const wbPath = `${sitePath}/weighbridges/${weighbridgeId}`;

  const results = { moved: {}, skipped: {}, errors: [] };

  // Helper: copy collection docs from flat to nested path
  async function migrateCollection(srcName, destPath, batchSize = 200) {
    const srcSnap = await db.collection(srcName).get();
    if (srcSnap.empty) {
      results.skipped[srcName] = "empty";
      return;
    }

    let count = 0;
    let batch = db.batch();

    for (const doc of srcSnap.docs) {
      const destRef = db.collection(destPath).doc(doc.id);
      batch.set(destRef, doc.data());
      count++;

      if (count % batchSize === 0) {
        await batch.commit();
        batch = db.batch();
      }
    }

    if (count % batchSize !== 0) {
      await batch.commit();
    }

    results.moved[srcName] = count;
  }

  try {
    // Company-wide collections
    await migrateCollection("customers", `${companyPath}/customers`);
    await migrateCollection("customers_deleted", `${companyPath}/customers_deleted`);
    await migrateCollection("customer_merges", `${companyPath}/customer_merges`);
    await migrateCollection("materials", `${companyPath}/materials`);
    await migrateCollection("vehicles", `${companyPath}/vehicles`);
    await migrateCollection("auditLog", `${companyPath}/auditLog`);
    await migrateCollection("notifications", `${companyPath}/notifications`);

    // Site-scoped collections
    await migrateCollection("operators", `${sitePath}/operators`);

    // Settings → split into site-level and weighbridge-level
    const settingsSnap = await db.collection("settings").get();
    if (!settingsSnap.empty) {
      const siteSettings = ["security", "notifications", "integrations", "general", "general_docs", "appearance", "dataBackup", "customFields"];
      const wbSettings = ["scale", "camerasAi", "gateControl", "printing"];

      let batch2 = db.batch();
      let count2 = 0;

      for (const doc of settingsSnap.docs) {
        if (siteSettings.includes(doc.id)) {
          batch2.set(db.doc(`${sitePath}/settings/${doc.id}`), doc.data());
        } else if (wbSettings.includes(doc.id)) {
          batch2.set(db.doc(`${wbPath}/settings/${doc.id}`), doc.data());
        }
        count2++;
      }

      if (count2 > 0) await batch2.commit();
      results.moved["settings"] = count2;
    }

    // Weighbridge-scoped collections
    await migrateCollection("weighments", `${wbPath}/weighments`);
    await migrateCollection("queues", `${wbPath}/queues`);
    await migrateCollection("counters", `${wbPath}/counters`);
    await migrateCollection("gateEvents", `${wbPath}/gateEvents`);
    await migrateCollection("gateCommands", `${wbPath}/gateCommands`);
    await migrateCollection("cameras", `${wbPath}/cameras`);

    // Audit log entry for migration
    await db.collection(`${companyPath}/auditLog`).add({
      event: "dataMigration",
      description: `Flat data migrated to hierarchy: ${companyPath}`,
      user: context.auth.token.email || "admin",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      success: true,
      metadata: results,
    });
  } catch (e) {
    results.errors.push(e.message);
  }

  return results;
});

// ═══════════════════════════════════════════════════════════════════════════════
// LICENSING
// ═══════════════════════════════════════════════════════════════════════════════

function generateKey() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const segment = () => Array.from({length: 4}, () => chars[Math.floor(Math.random() * chars.length)]).join("");
  return `${segment()}-${segment()}-${segment()}-${segment()}`;
}

// ─── Generate License Key (admin only) ─────────────────────────────────────

exports.generateLicenseKey = fns.https.onCall(async (data, context) => {
  const { tier, maxWeighbridges, maxSites, features, adminSecret } = data;

  // Secret lives in the server env (LICENSE_ADMIN_SECRET), never hardcoded in
  // source. Fail closed if unset so a misconfig can't mint licences openly.
  const expected = process.env.LICENSE_ADMIN_SECRET;
  if (!expected || adminSecret !== expected) {
    throw new functions.https.HttpsError("permission-denied", "Invalid admin secret");
  }

  const validTiers = ["free", "trial", "pro"];
  if (!validTiers.includes(tier)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid tier");
  }

  const key = generateKey();
  await db.collection("licenses").doc(key).set({
    tier,
    status: "active",
    gstin: null,
    companyId: null,
    deviceFingerprint: null,
    activatedAt: null,
    expiresAt: null,
    trialStartedAt: null,
    lastValidatedAt: null,
    maxWeighbridges: maxWeighbridges || (tier === "pro" ? -1 : 1),
    maxSites: maxSites || (tier === "pro" ? -1 : 1),
    features: features || (tier === "pro" ? [
      "multi_weighbridge", "ip_cameras", "rtsp", "ai_anpr", "ai_material",
      "ai_face", "gate_control", "integrations", "advanced_security", "multi_site",
    ] : []),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: context.auth?.token?.email || "admin",
  });

  return { success: true, key };
});

// ─── Activate License ──────────────────────────────────────────────────────

/**
 * _sendLicenseActivatedNotice — branded "your plan is active" confirmation to
 * the company admin (email + SMS). Shared by paid activation (activateLicense)
 * and client-side trial/free activation (notifyLicenseActivated). Best-effort.
 */
async function _sendLicenseActivatedNotice(companyId, tier, maxWeighbridges, expiresAtMs) {
  const planLabel = (tier || "plan").toString();
  const wbLabel = (maxWeighbridges || 1) === -1 ? "Unlimited" : String(maxWeighbridges || 1);
  const validLabel = expiresAtMs
    ? new Date(expiresAtMs).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Kolkata" })
    : "No expiry";
  await notifyContact({
    companyId,
    subject: `${BRAND.name}: your ${planLabel} plan is active`,
    notif: ({
      category: "licence",
      link: "/settings/license",
      heading: "Plan active",
      intro: `Your ${BRAND.name} license has been activated — you're all set to run your weighbridge operations.`,
      rows: [["Plan", planLabel], ["Weighbridges", wbLabel], ["Valid until", validLabel]],
      note: `Manage your subscription anytime at ${BRAND.website}.`,
    }),
  });
}

// Client-triggered activation confirmation for trial/free (those activate
// directly in Firestore, with no activateLicense call to hook server-side).
exports.notifyLicenseActivated = fns.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  const companyId = data && data.companyId ? String(data.companyId) : "";
  if (!companyId) return { success: false };
  const compSnap = await db.doc(`companies/${companyId}`).get();
  const lic = (compSnap.exists ? compSnap.data().license : null) || {};
  await _sendLicenseActivatedNotice(
    companyId, lic.tier, lic.maxWeighbridges,
    lic.expiresAt && typeof lic.expiresAt.toMillis === "function" ? lic.expiresAt.toMillis() : null);
  return { success: true };
});

exports.activateLicense = fns.https.onCall(async (data, context) => {
  const { licenseKey, gstin, companyId, deviceFingerprint } = data;

  if (!licenseKey || !gstin || !companyId || !deviceFingerprint) {
    throw new functions.https.HttpsError("invalid-argument", "Missing required fields");
  }

  const licenseRef = db.collection("licenses").doc(licenseKey);
  const licenseSnap = await licenseRef.get();

  if (!licenseSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Invalid license key");
  }

  const license = licenseSnap.data();

  if (license.status !== "active") {
    throw new functions.https.HttpsError("failed-precondition", `License is ${license.status}`);
  }

  if (license.companyId && license.companyId !== companyId) {
    throw new functions.https.HttpsError("already-exists", "License already activated for another company");
  }

  // GSTIN uniqueness check
  const normalizedGstin = gstin.replace(/[^A-Z0-9]/gi, "").toUpperCase();
  const registryRef = db.collection("gstin_registry").doc(normalizedGstin);
  const registrySnap = await registryRef.get();

  if (registrySnap.exists) {
    const regData = registrySnap.data();
    if (regData.companyId !== companyId) {
      throw new functions.https.HttpsError("already-exists", "GSTIN already registered to another account");
    }
  }

  // Trial abuse check
  if (license.tier === "trial" && registrySnap.exists && registrySnap.data().hadTrial) {
    throw new functions.https.HttpsError("failed-precondition", "Trial already used for this GSTIN");
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const updates = {
    gstin: normalizedGstin,
    companyId,
    deviceFingerprint,
    activatedAt: now,
    lastValidatedAt: now,
  };

  if (license.tier === "trial") {
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    updates.trialStartedAt = now;
    updates.expiresAt = admin.firestore.Timestamp.fromDate(expiresAt);
  }

  await licenseRef.update(updates);

  // Write to GSTIN registry
  await registryRef.set({
    companyId,
    deviceFingerprint,
    hadTrial: license.tier === "trial" ? true : (registrySnap.exists ? registrySnap.data().hadTrial || false : false),
    registeredAt: now,
  }, { merge: true });

  // Denormalize to company doc
  const companyLicense = {
    currentLicenseKey: licenseKey,
    tier: license.tier,
    status: "active",
    features: license.features || [],
    maxWeighbridges: license.maxWeighbridges || 1,
    maxSites: license.maxSites || 1,
    lastValidatedAt: now,
  };
  if (updates.expiresAt) companyLicense.expiresAt = updates.expiresAt;

  await db.doc(`companies/${companyId}`).set({ license: companyLicense }, { merge: true });

  // Confirm activation to the company admin (best-effort). Covers paid keys
  // entered in-app; trial/free are client-side and confirm via notifyLicenseActivated.
  await _sendLicenseActivatedNotice(
    companyId, license.tier, license.maxWeighbridges,
    updates.expiresAt ? updates.expiresAt.toMillis() : null);

  return {
    success: true,
    tier: license.tier,
    features: license.features || [],
    maxWeighbridges: license.maxWeighbridges || 1,
    maxSites: license.maxSites || 1,
    expiresAt: updates.expiresAt ? updates.expiresAt.toMillis() : null,
  };
});

// ─── Validate License ──────────────────────────────────────────────────────

exports.validateLicense = fns.https.onCall(async (data, context) => {
  const { licenseKey, companyId, deviceFingerprint } = data;

  if (!companyId) {
    throw new functions.https.HttpsError("invalid-argument", "Missing companyId");
  }

  let license = null;
  let licenseRef = null;
  let isInline = false;

  // Try standalone licenses collection first
  if (licenseKey) {
    licenseRef = db.collection("licenses").doc(licenseKey);
    const licenseSnap = await licenseRef.get();
    if (licenseSnap.exists) {
      license = licenseSnap.data();
    }
  }

  // Fallback: read from company doc's inline license field
  if (!license) {
    const companySnap = await db.doc(`companies/${companyId}`).get();
    if (companySnap.exists && companySnap.data().license) {
      license = companySnap.data().license;
      isInline = true;
    }
  }

  if (!license) {
    return { valid: false, reason: "License not found" };
  }

  // Device fingerprint check (only for standalone licenses that have it)
  if (!isInline && license.deviceFingerprint && deviceFingerprint && license.deviceFingerprint !== deviceFingerprint) {
    return { valid: false, reason: "Device mismatch" };
  }

  // Expiry check
  const expiresAt = license.expiresAt ? (license.expiresAt.toDate ? license.expiresAt.toDate() : new Date(license.expiresAt)) : null;
  if (expiresAt && expiresAt < new Date()) {
    if (licenseRef && !isInline) {
      await licenseRef.update({ status: "expired" });
    }
    await db.doc(`companies/${companyId}`).set({
      license: { status: "expired" },
    }, { merge: true });
    return { valid: false, reason: "License expired", tier: license.tier };
  }

  const status = license.status || "active";
  if (status !== "active") {
    return { valid: false, reason: `License is ${status}`, tier: license.tier };
  }

  // Update last validated
  const now = admin.firestore.FieldValue.serverTimestamp();
  if (licenseRef && !isInline) {
    await licenseRef.update({ lastValidatedAt: now });
  }
  await db.doc(`companies/${companyId}`).set({
    license: { lastValidatedAt: now },
  }, { merge: true });

  const expiresAtMs = expiresAt ? expiresAt.getTime() : null;

  return {
    valid: true,
    tier: license.tier,
    features: license.features || [],
    maxWeighbridges: license.maxWeighbridges || (license.tier === "pro" ? -1 : license.tier === "trial" ? 2 : 1),
    maxSites: license.maxSites || (license.tier === "pro" ? -1 : 1),
    expiresAt: expiresAtMs,
    daysRemaining: expiresAt
      ? Math.ceil((expiresAt - new Date()) / (1000 * 60 * 60 * 24))
      : -1,
  };
});

// ─── Check Expired Licenses (daily scheduled) ──────────────────────────────

exports.checkExpiredLicenses = fns.pubsub
  .schedule("every 24 hours")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const expired = await db.collection("licenses")
      .where("status", "==", "active")
      .where("expiresAt", "<=", now)
      .get();

    if (expired.empty) return null;

    const batch = db.batch();
    const expiredCompanies = [];
    for (const doc of expired.docs) {
      batch.update(doc.ref, { status: "expired" });
      const companyId = doc.data().companyId;
      if (companyId) {
        batch.set(db.doc(`companies/${companyId}`), {
          license: { status: "expired" },
        }, { merge: true });
        expiredCompanies.push(companyId);
      }
    }
    await batch.commit();
    console.log(`Expired ${expired.size} licenses`);

    // Notify each company's admin that the subscription lapsed (best-effort).
    for (const companyId of expiredCompanies) {
      await notifyContact({
        companyId,
        subject: `${BRAND.name}: your subscription has expired`,
        notif: ({
          category: "licence",
          link: "/settings/license",
          accent: "warn",
          heading: "Subscription expired",
          intro: `Your ${BRAND.name} subscription has expired. Renew now to restore full access to your weighbridge operations.`,
          ctaText: "Renew subscription",
          ctaUrl: `https://${BRAND.website}/billing`,
          note: `Need help renewing? Contact ${BRAND.support}.`,
        }),
      });
    }
    return null;
  });

// ─── Scheduled: subscription expiry reminders (7 / 3 / 1 days out) ───────────
exports.licenseExpiryReminders = fns.pubsub
  .schedule("every 24 hours")
  .timeZone("Asia/Kolkata")
  .onRun(async () => {
    const now = Date.now();
    const soon = await db.collection("licenses")
      .where("status", "==", "active")
      .where("expiresAt", "<=", admin.firestore.Timestamp.fromMillis(now + 8 * 24 * 60 * 60 * 1000))
      .where("expiresAt", ">", admin.firestore.Timestamp.fromMillis(now))
      .get();

    for (const doc of soon.docs) {
      const lic = doc.data();
      const companyId = lic.companyId;
      if (!companyId || !lic.expiresAt) continue;
      const daysLeft = Math.ceil((lic.expiresAt.toMillis() - now) / (24 * 60 * 60 * 1000));
      // Fire once per 7/3/1 threshold — `remindersSent` guards against repeats.
      const sent = lic.remindersSent || [];
      const due = [7, 3, 1].find((t) => daysLeft <= t && !sent.includes(t));
      if (!due) continue;

      await notifyContact({
        companyId,
        subject: `${BRAND.name}: your subscription expires in ${daysLeft} day${daysLeft === 1 ? "" : "s"}`,
        notif: ({
          category: "licence",
          link: "/settings/license",
          accent: "warn",
          heading: "Subscription expiring",
          intro: `Your ${BRAND.name} subscription expires in ${daysLeft} day${daysLeft === 1 ? "" : "s"}. Renew to avoid interruption to weighbridge operations.`,
          rows: [["Expires in", `${daysLeft} day${daysLeft === 1 ? "" : "s"}`]],
          ctaText: "Renew subscription",
          ctaUrl: `https://${BRAND.website}/billing`,
          note: `Need help? Contact ${BRAND.support}.`,
        }),
      });
      await doc.ref.set({ remindersSent: admin.firestore.FieldValue.arrayUnion(due) }, { merge: true });
    }
    return null;
  });

// ─── Scheduled: address-verification grace reminders (7 / 3 / 1 days out) ────
exports.addressGraceReminders = fns.pubsub
  .schedule("every 24 hours")
  .timeZone("Asia/Kolkata")
  .onRun(async () => {
    const now = Date.now();
    // status-only query (single-field index) + in-memory window filter, so no
    // composite index on (status, graceUntil) is required.
    const pending = await db.collection("address_verifications")
      .where("status", "==", "pending")
      .get();

    for (const doc of pending.docs) {
      const av = doc.data();
      if (!av.graceUntil) continue;
      const daysLeft = Math.ceil((av.graceUntil.toMillis() - now) / (24 * 60 * 60 * 1000));
      if (daysLeft <= 0 || daysLeft > 7) continue;
      const sent = av.remindersSent || [];
      const due = [7, 3, 1].find((t) => daysLeft <= t && !sent.includes(t));
      if (!due) continue;

      await notifyContact({
        companyId: av.companyId || doc.id,
        subject: `${BRAND.name}: verify your business address (${daysLeft} day${daysLeft === 1 ? "" : "s"} left)`,
        notif: ({
          category: "account",
          link: "/address-verify",
          accent: "warn",
          heading: "Verify business address",
          intro: `To keep your ${BRAND.name} account active, enter the verification code from the letter we mailed to your registered address. You have ${daysLeft} day${daysLeft === 1 ? "" : "s"} left.`,
          rows: [["Time left", `${daysLeft} day${daysLeft === 1 ? "" : "s"}`]],
          note: `Didn't receive the letter? Contact ${BRAND.support} for a reissue.`,
        }),
        sms: { template: "addressGrace", vars: [String(daysLeft)] },
      });
      await doc.ref.set({ remindersSent: admin.firestore.FieldValue.arrayUnion(due) }, { merge: true });
    }
    return null;
  });

// ─── Email & Phone Verification ─────────────────────────────────────────────

const nodemailer = require("nodemailer");

function generateOTP() {
  // Length is driven by OTP_LENGTH (defined below; evaluated at call time).
  // Use a CSPRNG — Math.random() is not cryptographically secure for OTPs.
  const min = Math.pow(10, OTP_LENGTH - 1);
  return require("crypto").randomInt(min, min * 10).toString();
}

function getMailTransporter() {
  return nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: _fnConfig().gmail?.email || process.env.GMAIL_EMAIL,
      pass: _fnConfig().gmail?.app_password || process.env.GMAIL_APP_PASSWORD,
    },
  });
}

// The "000000" test OTP code is honored ONLY when explicitly enabled
// (dev/staging via `ALLOW_TEST_OTP=true`). In production the flag is unset, so
// the code is rejected — this is what closes the OTP / password-reset bypass.
const ALLOW_TEST_OTP = process.env.ALLOW_TEST_OTP === "true";

// Anti-spam / anti-enumeration: minimum gap between OTP sends to one destination.
const OTP_RESEND_COOLDOWN_SECONDS = 60;

// ─── OTP policy — single source of truth ─────────────────────────────────────
// Every OTP message (the email template + the documented DLT SMS template)
// derives its copy from these constants, so the validity a user is shown can
// never drift from the real Firestore expiry / attempt limits.
const OTP_LENGTH = 6;
const OTP_EXPIRY_MINUTES = 10;
const OTP_MAX_ATTEMPTS = 5;
const OTP_EXPIRY_MS = OTP_EXPIRY_MINUTES * 60 * 1000;

// ─── Brand tokens — kept consistent with the Tulanam app shell ───────────────
// teal #0D9488 / navy #1E3A5F mirror lib/shared/theme/app_theme.dart so every
// OTP message looks like the rest of the product.
const BRAND = {
  name: "Tulanam",
  glyph: "⚖", // balance scale
  website: "tulanam.com",
  support: "support@tulanam.com",
  noreply: "noreply@tulanam.com",
  teal: "#0D9488",
  tealTint: "#F0FDFA",
  navy: "#1E3A5F",
  slate: "#94A3B8",
  ink: "#0F172A",
  muted: "#64748B",
  border: "#E2E8F0",
  pageBg: "#F4F6F8",
};

// ── Email building blocks ────────────────────────────────────────────────────
// Table-based layout + inline styles so every Tulanam email survives Outlook /
// Word-engine clients (no flexbox, no CSS gradients on divs). All OTP and
// transactional emails share the same branded shell (header band + footer).
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

/**
 * buildOtpEmail — the single template behind every OTP email (verification +
 * password reset). Expiry copy is derived from OTP_EXPIRY_MINUTES, never hardcoded.
 */
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

/**
 * buildBrandEmail — generic branded template for all transactional notifications.
 * rows: array of [label, value] shown in a bordered detail table.
 * accent: "danger" | "warn" prepends a coloured status chip.
 */
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

/**
 * _sendBrandEmail — best-effort send of a branded email. Never throws.
 */
async function _sendBrandEmail(toEmail, subject, html) {
  if (!toEmail) return false;
  try {
    const transporter = getMailTransporter();
    const senderEmail = _fnConfig().gmail?.email || process.env.GMAIL_EMAIL || BRAND.noreply;
    await transporter.sendMail({
      from: `"${BRAND.name}" <${senderEmail}>`,
      replyTo: BRAND.support,
      to: toEmail,
      subject,
      html,
    });
    return true;
  } catch (e) {
    console.warn(`Email '${subject}' failed:`, e.message);
    return false;
  }
}

// ─── Scheduled: daily client-error digest ────────────────────────────────────
// Summarises the last 24h of `error_reports` (the client crash/error log) and
// emails it, so production app bugs surface without watching the console. Also
// prunes reports older than 30 days. Recipient: ERROR_DIGEST_TO env, else support.
exports.errorReportDigest = fns.pubsub
  .schedule("every day 08:00")
  .timeZone("Asia/Kolkata")
  .onRun(async () => {
    const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;" }[c]));
    const now = Date.now();
    const since = admin.firestore.Timestamp.fromMillis(now - 24 * 60 * 60 * 1000);
    const snap = await db.collection("error_reports").where("createdAt", ">=", since).get();

    if (!snap.empty) {
      const groups = new Map(); // message -> { count, versions, platforms }
      snap.forEach((d) => {
        const e = d.data();
        const key = (e.message || "unknown").slice(0, 160);
        const g = groups.get(key) || { count: 0, versions: new Set(), platforms: new Set() };
        g.count++;
        if (e.version) g.versions.add(e.version);
        if (e.platform) g.platforms.add(e.platform);
        groups.set(key, g);
      });
      const rows = [...groups.entries()]
        .sort((a, b) => b[1].count - a[1].count)
        .map(([msg, g]) => `<tr>
          <td style="padding:6px 10px;border-bottom:1px solid #eee;font-weight:700;color:#b00020">${g.count}&times;</td>
          <td style="padding:6px 10px;border-bottom:1px solid #eee">
            <div style="font-family:monospace;font-size:12px;color:#222">${esc(msg)}</div>
            <div style="font-size:11px;color:#777">${[...g.platforms].join(", ")} &middot; ${[...g.versions].join(", ")}</div>
          </td></tr>`).join("");
      const html = `<h2 style="font-family:sans-serif">${BRAND.name} — client errors (last 24h)</h2>
        <p style="font-family:sans-serif;color:#555">${snap.size} report(s), ${groups.size} distinct. Full detail in Firestore &rarr; error_reports.</p>
        <table style="border-collapse:collapse;width:100%;max-width:680px;font-family:sans-serif">${rows}</table>`;
      await _sendBrandEmail(process.env.ERROR_DIGEST_TO || BRAND.support,
        `${BRAND.name}: ${snap.size} client error(s) in the last 24h`, html);
    }

    // Retention: drop reports older than 30 days (batched).
    try {
      const old = await db.collection("error_reports")
        .where("createdAt", "<", admin.firestore.Timestamp.fromMillis(now - 30 * 24 * 60 * 60 * 1000))
        .limit(400).get();
      if (!old.empty) {
        const batch = db.batch();
        old.forEach((d) => batch.delete(d.ref));
        await batch.commit();
      }
    } catch (e) { console.warn("error_reports prune failed:", e.message); }

    return null;
  });

// ── Rendered email documents (inline image + PDF attachment) ─────────────────
// Calls the isolated gen-2 renderEmailDoc over HTTP. Best-effort: returns null
// on any failure so callers fall back to the plain buildBrandEmail HTML.
async function _renderEmailAssets(kind, data, pageSize) {
  const url = _fnConfig().render?.url || process.env.RENDER_URL;
  if (!url) return null;
  try {
    const fetch = (await import("node-fetch")).default;
    const r = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-render-secret": process.env.RENDER_SECRET || _fnConfig().render?.secret || "",
      },
      body: JSON.stringify({ kind, data, pageSize }),
    });
    if (!r.ok) { console.warn(`render ${kind} HTTP ${r.status}`); return null; }
    return await r.json(); // { imageUrl, pdfBase64 }
  } catch (e) {
    console.warn(`render ${kind} call failed:`, e.message);
    return null;
  }
}

// Company details for the document band (name, GSTIN, PAN, address).
async function _companyDetails(companyId) {
  try {
    const snap = await db.doc(`companies/${companyId}`).get();
    const c = snap.exists ? (snap.data() || {}) : {};
    const address = [c.address1, c.address2, c.state, c.pincode].filter(Boolean).join(", ");
    return { name: c.name || "", gstin: c.gstin || "", pan: c.pan || "", address };
  } catch (e) {
    return { name: "", gstin: "", pan: "", address: "" };
  }
}

// Company's configured normal-printer page size (A4/A5/Letter/Legal → PDF size).
async function _printerPageSize(companyId) {
  try {
    const snap = await db.doc(`companies/${companyId}/settings/printing`).get();
    const p = snap.exists ? (snap.data() || {}) : {};
    return (p.normal && p.normal.paperSize) || p.normalPaperSize || "A4";
  } catch (e) {
    return "A4";
  }
}

// Email carrying the rendered inline image + PDF attachment, with the plain
// buildBrandEmail HTML kept beneath as the fallback (survives image-blocking).
async function _sendRenderedEmail(toEmail, subject, opts) {
  if (!toEmail) return false;
  const { imageUrl, pdfBase64, pdfName, fallbackHtml, alt } = opts || {};
  try {
    const transporter = getMailTransporter();
    const senderEmail = _fnConfig().gmail?.email || process.env.GMAIL_EMAIL || BRAND.noreply;
    const html =
      `<div style="background:#eef2f7;padding:20px 0;text-align:center"><img src="${imageUrl}" alt="${alt || BRAND.name}" style="display:block;max-width:600px;width:100%;margin:0 auto;border-radius:14px"/></div>` +
      `<div style="margin-top:8px">${fallbackHtml || ""}</div>`;
    const attachments = pdfBase64
      ? [{ filename: pdfName || "document.pdf", content: Buffer.from(pdfBase64, "base64"), contentType: "application/pdf" }]
      : [];
    await transporter.sendMail({
      from: `"${BRAND.name}" <${senderEmail}>`, replyTo: BRAND.support, to: toEmail, subject, html, attachments,
    });
    return true;
  } catch (e) {
    console.warn(`rendered email '${subject}' failed:`, e.message);
    return false;
  }
}

// Maps a weighment doc to the receipt template's data shape. NOTE: the CCTV
// snapshot and customFields shapes are best-effort — verify against real docs.
function _asImageUri(s) {
  if (!s || typeof s !== "string") return null;
  // Only data: URIs and https URLs — block plaintext http:// so a malicious
  // photo URL can't make the renderer fetch internal/metadata endpoints (SSRF).
  if (s.startsWith("data:") || s.startsWith("https://")) return s;
  return `data:image/jpeg;base64,${s}`;
}
async function _weighmentToReceiptData(companyId, w, ticket) {
  const company = await _companyDetails(companyId);
  const cf = [];
  if (w.customFields && typeof w.customFields === "object") {
    for (const [k, v] of Object.entries(w.customFields)) {
      if (v != null && String(v).trim() !== "") cf.push({ k, v: String(v) });
    }
  }
  const toFrames = (snaps) => {
    if (!snaps) return [];
    const arr = Array.isArray(snaps) ? snaps : Object.entries(snaps).map(([cam, img]) => ({ cam, img }));
    return arr.slice(0, 3).map((s, i) => ({
      cam: (s && s.cam) || `CAM ${i + 1}`,
      ts: (s && s.ts) || "",
      img: _asImageUri(typeof s === "string" ? s : (s && s.img)),
    }));
  };
  const firstIsTare = String(w.firstWeightType || "").toLowerCase() === "tare";
  const fmtKg = (n) => Math.round(n || 0).toLocaleString("en-IN");
  const fmtDT = (ts) => (ts && ts.toDate)
    ? ts.toDate().toLocaleString("en-IN", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hour12: false, timeZone: "Asia/Kolkata" })
    : "";
  return {
    company,
    customer: { name: w.customerName || "", phone: w.customerPhone || "", address: w.customerAddress || "" },
    rst: String(w.rstNumber || ticket || "").replace(/^RST[-\s]*/i, ""),
    date: w.completedAt && w.completedAt.toDate
      ? w.completedAt.toDate().toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Kolkata" })
      : "",
    status: "Completed",
    vehicle: w.vehicleNumber || "",
    material: w.material || "",
    net: fmtKg(w.netWeight),
    gross: { weight: fmtKg(w.grossWeight), time: fmtDT(firstIsTare ? w.secondWeightAt : w.firstWeightAt) },
    tare: { weight: fmtKg(w.tareWeight), time: fmtDT(firstIsTare ? w.firstWeightAt : w.secondWeightAt) },
    operator: { name: w.operatorName || "", weighbridge: w.weighbridgeName || "", port: w.portName || "", pc: w.pcName || "", shift: w.shift || "" },
    customFields: cf,
    cctv: { tare: toFrames(firstIsTare ? w.firstWeightSnapshots : w.secondWeightSnapshots), gross: toFrames(firstIsTare ? w.secondWeightSnapshots : w.firstWeightSnapshots) },
  };
}

// ── SMS: OTP via Fast2SMS OTP API; transactional via DLT bulk route ───────────
/**
 * Fast2SMS OTP TEMPLATE — register this text on the DLT portal, create a
 * Fast2SMS "OTP Template" from it, and put its OTP Template ID in FAST2SMS_OTP_ID.
 * OTP is sent through the dedicated /dev/otp/send API (NOT the bulkV2 DLT route
 * used by transactional messages, so sender_id/message do not apply here). We
 * pass our OWN otp value so it matches the hash we store for verification;
 * Fast2SMS injects it as the template's {#var#}. DLT Header (sender ID) = TULNAM.
 *
 *   Tulanam: {#var#} is your verification code. Valid for 10 minutes. Do not
 *   share it with anyone.
 */
const FAST2SMS_OTP_TEMPLATE_TEXT =
  `${BRAND.name}: {#var#} is your verification code. Valid for ${OTP_EXPIRY_MINUTES} minutes. ` +
  "Do not share it with anyone.";

/**
 * _sendOtpSms — sends the OTP via the Fast2SMS OTP API (/dev/otp/send).
 * Returns true if a send was attempted (creds present), false if skipped/failed.
 */
async function _sendOtpSms(digits, otp) {
  const apiKey = _fnConfig().fast2sms?.api_key || process.env.FAST2SMS_API_KEY;
  const otpId = _fnConfig().fast2sms?.otp_id || process.env.FAST2SMS_OTP_ID;
  if (!apiKey || !otpId) {
    console.warn(
      "FAST2SMS OTP not configured (need FAST2SMS_API_KEY + FAST2SMS_OTP_ID), skipping. " +
      `Register this OTP template: ${FAST2SMS_OTP_TEMPLATE_TEXT}`);
    return false;
  }
  try {
    const fetch = (await import("node-fetch")).default;
    const response = await fetch("https://www.fast2sms.com/dev/otp/send", {
      method: "POST",
      headers: { "authorization": apiKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        mobile: String(digits).replace(/\D/g, "").slice(-10),
        otp_id: otpId,
        otp: otp, // our generated value — matches the hash we verify against
        otp_length: OTP_LENGTH,
        otp_expiry: OTP_EXPIRY_MINUTES, // minutes
      }),
    });
    const result = await response.json().catch(() => ({}));
    const ok = !!result.return;
    if (!ok) console.error("FAST2SMS OTP error:", result);
    return ok;
  } catch (e) {
    console.warn("FAST2SMS OTP send failed:", e.message);
    return false;
  }
}

/**
 * TRANSACTIONAL DLT SMS TEMPLATES (Fast2SMS bulkV2 "dlt" route, Header = TULNAM).
 * Each entry is ONE DLT template to register on the portal; put its Template ID
 * in the listed env var. DLT rules enforced here: ≤3 variables, pipe-separated
 * in the EXACT order of `vars`, and static text between every {#var#} (operators
 * reject adjacent variables). Until an entry's env var is set, that SMS is logged
 * and skipped — it never throws into business logic.
 */
// Lean SMS set — SMS only where it must reach someone off-screen / out-of-band.
// Everything else (welcome, licence, KYC, operator lifecycle, account-security,
// backup, quota) is delivered by email + the in-app notification center instead.
const DLT_TEMPLATES = {
  securityAlert: { env: "FAST2SMS_TPL_SECURITY_ALERT", vars: ["alert"],
    text: "Tulanam security alert: {#var#}. Please review your account now. - Tulanam" },
  gateAlert: { env: "FAST2SMS_TPL_GATE_ALERT", vars: ["alert"],
    text: "Tulanam gate alert: {#var#}. Please check the gate control system. - Tulanam" },
  addressGrace: { env: "FAST2SMS_TPL_ADDRESS_GRACE", vars: ["days"],
    text: "Tulanam: Verify your business address within {#var#} days to keep your account active. Use the code in the letter we mailed. - Tulanam" },
  weighmentReceipt: { env: "FAST2SMS_TPL_WEIGHMENT_RECEIPT", vars: ["ticket", "vehicle", "net"],
    text: "Tulanam: Weighment {#var#} for vehicle {#var#} is recorded. Net weight {#var#} kg. - Tulanam" },
  dailyDigest: { env: "FAST2SMS_TPL_DAILY_DIGEST", vars: ["weighments", "tonnage"],
    text: "Tulanam: Daily summary — {#var#} weighments, {#var#} tonnes recorded. - Tulanam" },
};

/**
 * _sendDltSms — best-effort transactional SMS via the registered DLT template.
 * `vars` must match templateKey's registered order. Never throws.
 */
async function _sendDltSms(templateKey, digits, vars = []) {
  const tpl = DLT_TEMPLATES[templateKey];
  if (!tpl) { console.error(`Unknown DLT template: ${templateKey}`); return false; }
  const apiKey = _fnConfig().fast2sms?.api_key || process.env.FAST2SMS_API_KEY;
  const senderId = _fnConfig().fast2sms?.sender_id || process.env.FAST2SMS_SENDER_ID;
  const templateId = process.env[tpl.env];
  if (!apiKey || !senderId || !templateId) {
    console.warn(`SMS '${templateKey}' skipped (set ${tpl.env}). Template to register: ${tpl.text}`);
    return false;
  }
  const cleaned = String(digits || "").replace(/\D/g, "").slice(-10);
  if (cleaned.length !== 10) return false;
  try {
    const fetch = (await import("node-fetch")).default;
    const payload = { route: "dlt", sender_id: senderId, message: templateId, flash: 0, numbers: cleaned };
    if (tpl.vars.length) payload.variables_values = vars.map((v) => String(v)).join("|");
    const response = await fetch("https://www.fast2sms.com/dev/bulkV2", {
      method: "POST",
      headers: { "authorization": apiKey, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const result = await response.json().catch(() => ({}));
    const ok = !!result.return;
    if (!ok) console.error(`FAST2SMS '${templateKey}' error:`, result);
    return ok;
  } catch (e) {
    console.warn(`SMS '${templateKey}' send failed:`, e.message);
    return false;
  }
}

/**
 * resolveCompanyAdminContact — best-effort {email, phone, name} for a company's
 * admin. Prefers the company doc, falls back to the companyAdmin operator.
 */
async function resolveCompanyAdminContact(companyId) {
  const out = { email: null, phone: null, name: "Admin" };
  if (!companyId) return out;
  try {
    const compSnap = await db.doc(`companies/${companyId}`).get();
    if (compSnap.exists) {
      const c = compSnap.data() || {};
      out.email = c.email || c.contactEmail || null;
      out.phone = c.phone || c.contactPhone || null;
      out.name = c.contactName || c.name || out.name;
    }
    if (!out.email || !out.phone || out.name === "Admin") {
      const opSnap = await db.collection(`companies/${companyId}/operators`)
        .where("role", "==", "companyAdmin").limit(1).get();
      if (!opSnap.empty) {
        const op = opSnap.docs[0].data() || {};
        out.email = out.email || op.email || null;
        out.phone = out.phone || op.phone || null;
        if (out.name === "Admin") out.name = op.name || out.name;
      }
    }
  } catch (e) {
    console.warn("resolveCompanyAdminContact failed:", e.message);
  }
  return out;
}

/**
 * notifyContact — central best-effort email+SMS fan-out. Never throws into the
 * business path. Pass `to` directly or a `companyId` to resolve the admin.
 */
// Image-only email (per the delivery choice): the rendered design as a single
// <img>, with the essential info in `alt` (so it still reads when images are
// blocked) and the whole image wrapped in `linkUrl` when there's a CTA. Falls
// back to plain HTML if the image is missing.
async function _sendImageEmail(toEmail, subject, opts) {
  if (!toEmail) return false;
  const { imageUrl, alt, linkUrl, fallbackHtml } = opts || {};
  if (!imageUrl) return fallbackHtml ? _sendBrandEmail(toEmail, subject, fallbackHtml) : false;
  try {
    const transporter = getMailTransporter();
    const senderEmail = _fnConfig().gmail?.email || process.env.GMAIL_EMAIL || BRAND.noreply;
    const safeAlt = String(alt || BRAND.name).replace(/"/g, "&quot;");
    const img = `<img src="${imageUrl}" alt="${safeAlt}" style="display:block;max-width:600px;width:100%;margin:0 auto;border:0;border-radius:14px"/>`;
    const inner = linkUrl ? `<a href="${linkUrl}" style="text-decoration:none">${img}</a>` : img;
    await transporter.sendMail({
      from: `"${BRAND.name}" <${senderEmail}>`, replyTo: BRAND.support, to: toEmail, subject,
      html: `<div style="background:#eef2f7;padding:20px 0;text-align:center">${inner}</div>`,
    });
    return true;
  } catch (e) {
    console.warn(`image email '${subject}' failed:`, e.message);
    return fallbackHtml ? _sendBrandEmail(toEmail, subject, fallbackHtml) : false;
  }
}

// Render a designed email (kind=otp|notification|…) and send it image-only.
// On any render failure, sends `fallbackHtml` so the email always goes out.
async function _sendDesignedEmail(toEmail, subject, kind, data, opts = {}) {
  if (!toEmail) return false;
  const rendered = await _renderEmailAssets(kind, data, opts.pageSize);
  return _sendImageEmail(toEmail, subject, {
    imageUrl: rendered && rendered.imageUrl, alt: opts.alt, linkUrl: opts.linkUrl, fallbackHtml: opts.fallbackHtml,
  });
}

// Plain-HTML fallback built from a structured notification (old design, used
// only when the rendered image can't be produced).
function _notifToBrandHtml(n) {
  const note = [n.note, n.callout && n.callout.text].filter(Boolean).join(" ");
  return buildBrandEmail({
    accent: n.accent, heading: n.heading, intro: n.intro, rows: n.rows || [],
    ctaText: n.ctaText, ctaUrl: n.ctaUrl, note,
  });
}

// ── Per-company monthly send caps (cost guard) ───────────────────────────────
// Bounds spend per company: once the month's email/SMS cap is hit, further sends
// of that kind are skipped. Best-effort (a tiny over-count under heavy concurrency
// is acceptable for a budget guard). Passing no companyId = UNCAPPED — used for
// OTP/auth mail, which must never be dropped for a cost cap.
// Per-company override: companies/{id}/settings/limits { emailMonthly, smsMonthly }
// (0 or unset on a key = unlimited for that key). Defaults via env/config.
const DEFAULT_EMAIL_MONTHLY = Number(process.env.DEFAULT_EMAIL_MONTHLY || _fnConfig().limits?.email_monthly || 5000);
const DEFAULT_SMS_MONTHLY = Number(process.env.DEFAULT_SMS_MONTHLY || _fnConfig().limits?.sms_monthly || 1000);

// opts.force = a CRITICAL message (security alert, password-changed, etc.): it
// always sends and is never blocked, but still counts toward usage. Non-critical
// sends are blocked once the cap is hit, and the admin gets a one-time in-app
// warning (free, uncapped) when usage crosses 90%.
async function _consumeQuota(companyId, kind, opts = {}) {
  if (!companyId) return true; // uncapped (OTP / pre-company)
  try {
    const limSnap = await db.doc(`companies/${companyId}/settings/limits`).get();
    const lim = limSnap.exists ? (limSnap.data() || {}) : {};
    const cap = kind === "sms"
      ? Number(lim.smsMonthly != null ? lim.smsMonthly : DEFAULT_SMS_MONTHLY)
      : Number(lim.emailMonthly != null ? lim.emailMonthly : DEFAULT_EMAIL_MONTHLY);
    if (!(cap > 0) && !opts.force) return true; // unlimited & non-critical — skip tracking
    const period = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" }).slice(0, 7); // YYYY-MM
    const ref = db.doc(`companies/${companyId}/usage/${period}`);
    const snap = await ref.get();
    const data = snap.exists ? (snap.data() || {}) : {};
    const used = Number(data[kind] || 0);
    const label = kind === "sms" ? "SMS" : "Email";
    const things = kind === "sms" ? "messages" : "emails";
    if (!opts.force && cap > 0 && used >= cap) {
      await ref.set({ [`${kind}Blocked`]: admin.firestore.FieldValue.increment(1) }, { merge: true });
      console.warn(`quota: ${kind} cap (${cap}) reached for ${companyId} — send skipped`);
      // One-time "limit reached" in-app notice (free, uncapped).
      if (!data[`${kind}HitNotified`]) {
        await ref.set({ [`${kind}HitNotified`]: true }, { merge: true });
        await _writeInApp({
          companyId, category: "billing", severity: "warn", link: "/settings/license",
          title: `${label} limit reached`,
          body: `Your monthly ${label} limit (${cap}) is reached. Non-critical ${things} are paused until next month — security alerts still send.`,
        });
      }
      return false;
    }
    await ref.set({ [kind]: admin.firestore.FieldValue.increment(1), updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    // One-time 90% warning to the admin via the in-app channel (free, uncapped).
    if (!opts.force && cap > 0 && used + 1 >= Math.floor(cap * 0.9) && !data[`${kind}Warned`]) {
      await ref.set({ [`${kind}Warned`]: true }, { merge: true });
      await _writeInApp({
        companyId, category: "billing", severity: "warn", link: "/settings/license",
        title: `${label} limit near`,
        body: `${label} usage is ${used + 1} of ${cap} this month. Once the limit is hit, further ${things} are skipped — security alerts still send.`,
      });
    }
    return true;
  } catch (e) {
    console.warn("quota check failed (allowing send):", e.message);
    return true; // fail-open: a transient error must not drop mail
  }
}

async function notifyContact({ to, companyId, subject, emailHtml, notif, sms, critical, skipInApp }) {
  try {
    // In-app entry FIRST (free, always — never gated by the email/SMS cap, and
    // written before contact resolution so a resolve failure can't lose the most
    // reliable channel) for every structured notification. skipInApp avoids a
    // duplicate entry when the same notice is sent to multiple addresses.
    if (notif && companyId && !skipInApp) {
      await _writeInApp({
        companyId, operatorEmail: notif.operatorEmail || "*",
        category: notif.category || "system",
        severity: notif.accent === "danger" ? "critical" : notif.accent === "warn" ? "warn" : "info",
        title: notif.heading, body: notif.intro || notif.note || "", link: notif.link || null,
      });
    }
    const r = to || (companyId ? await resolveCompanyAdminContact(companyId) : {});
    if (r && r.email && (notif || emailHtml) && await _consumeQuota(companyId, "email", { force: critical })) {
      if (notif) {
        // New design, rendered image-only (HTML fallback on render failure).
        const company = notif.company || (companyId ? await _companyDetails(companyId) : {});
        const data = {
          pill: notif.pill, accent: notif.accent, heading: notif.heading, intro: notif.intro,
          rows: notif.rows, callout: notif.callout, ctaText: notif.ctaText, ctaUrl: notif.ctaUrl, note: notif.note, company,
        };
        const alt = [notif.heading, notif.intro].filter(Boolean).join(" — ");
        await _sendDesignedEmail(r.email, subject || BRAND.name, "notification", data,
          { alt, linkUrl: notif.ctaUrl, fallbackHtml: _notifToBrandHtml(notif) });
      } else if (emailHtml) {
        await _sendBrandEmail(r.email, subject || BRAND.name, emailHtml);
      }
    }
    if (sms && r && r.phone && await _consumeQuota(companyId, "sms", { force: critical })) await _sendDltSms(sms.template, r.phone, sms.vars || []);
  } catch (e) {
    console.warn("notifyContact failed:", e.message);
  }
}

/**
 * _notifyPasswordChanged — security notice to a user whose password changed.
 * Looks up the operator by email to also reach their phone. Best-effort.
 */
async function _notifyPasswordChanged(email) {
  if (!email) return;
  const addr = String(email).toLowerCase();
  let phone = null, name = "there", companyId = null;
  try {
    const opSnap = await db.collectionGroup("operators").where("email", "==", addr).limit(1).get();
    if (!opSnap.empty) {
      const op = opSnap.docs[0].data() || {};
      phone = op.phone || null;
      name = op.name || name;
      companyId = opSnap.docs[0].ref.parent.parent?.id || null; // company that owns this operator
    }
  } catch (e) {
    console.warn("password-change lookup failed:", e.message);
  }
  await notifyContact({
    to: { email: addr, phone, name },
    companyId,
    critical: true,
    subject: `${BRAND.name}: your password was changed`,
    notif: ({
      category: "account",
      link: "/settings/mfa",
      operatorEmail: addr,
      accent: "danger",
      heading: "Password changed",
      intro: `The password for your ${BRAND.name} account (${addr}) was just changed. If this was you, no further action is needed.`,
      note: `If you did NOT do this, contact ${BRAND.support} immediately — your account may be at risk.`,
    }),
  });
}

/**
 * Throws resource-exhausted if an OTP for [docId] was issued within the cooldown
 * window. Call before writing a fresh OTP in the send* functions.
 */
async function _enforceOtpCooldown(docId) {
  const snap = await db.collection("verification_otps").doc(docId).get();
  if (snap.exists) {
    const created = snap.data().createdAt;
    if (created && typeof created.toDate === "function") {
      const ageMs = Date.now() - created.toDate().getTime();
      if (ageMs < OTP_RESEND_COOLDOWN_SECONDS * 1000) {
        const wait = Math.ceil((OTP_RESEND_COOLDOWN_SECONDS * 1000 - ageMs) / 1000);
        throw new functions.https.HttpsError(
          "resource-exhausted", `Please wait ${wait}s before requesting another code.`);
      }
    }
  }
}

/**
 * sendEmailOTP - Sends a 6-digit OTP to the user's email.
 * Stores OTP hash in Firestore with 10-minute expiry.
 */
exports.sendEmailOTP = fns.https.onCall(async (data, context) => {
  const { email } = data;
  if (!email || !email.includes("@")) {
    throw new functions.https.HttpsError("invalid-argument", "Valid email required");
  }

  const emailLc = email.toLowerCase();
  const otp = generateOTP();
  const expiresAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + OTP_EXPIRY_MS)
  );
  const crypto = require("crypto");
  const otpHash = crypto.createHash("sha256").update(otp).digest("hex");

  // Cooldown check + OTP write ATOMICALLY. Two near-simultaneous send calls used
  // to both pass the (read-then-write) cooldown and both store an OTP — leaving
  // only the SECOND code valid (the "OTP sent twice, code doesn't work" bug).
  // In a transaction the loser sees the winner's doc and is rejected, so exactly
  // one OTP is stored and only one email goes out.
  const otpRef = db.collection("verification_otps").doc(emailLc);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(otpRef);
    if (snap.exists) {
      const created = snap.data().createdAt;
      if (created && typeof created.toDate === "function") {
        const ageMs = Date.now() - created.toDate().getTime();
        if (ageMs < OTP_RESEND_COOLDOWN_SECONDS * 1000) {
          const wait = Math.ceil((OTP_RESEND_COOLDOWN_SECONDS * 1000 - ageMs) / 1000);
          throw new functions.https.HttpsError("resource-exhausted", `Please wait ${wait}s before requesting another code.`);
        }
      }
    }
    tx.set(otpRef, { otpHash, expiresAt, attempts: 0, type: "email", createdAt: admin.firestore.FieldValue.serverTimestamp() });
  });

  // Send email — image-only design (code stays in subject + image alt), HTML fallback.
  try {
    const heading = "Your verification code";
    const intro = `Use the code below to continue. Enter it in ${BRAND.name} to confirm it's you.`;
    const securityNote = `If you didn't request this, you can safely ignore this email. ${BRAND.name} will never ask you to share this code.`;
    await _sendDesignedEmail(email, `${BRAND.name} verification code: ${otp}`, "otp",
      { eyebrow: "Verification", heading, intro, otp, securityNote, company: {} },
      { alt: `${BRAND.name} verification code: ${otp} — expires in ${OTP_EXPIRY_MINUTES} minutes`,
        fallbackHtml: buildOtpEmail({ heading, intro, otp, securityNote }) });
  } catch (e) {
    console.warn("Email send failed (credentials not configured?):", e.message);
  }

  return { success: true, message: "OTP sent to email" };
});

/**
 * verifyEmailOTP - Verifies the 6-digit OTP for email.
 */
exports.verifyEmailOTP = fns.https.onCall(async (data, context) => {
  const { email, otp } = data;
  if (!email || !otp) {
    throw new functions.https.HttpsError("invalid-argument", "Email and OTP required");
  }

  // Test bypass: 000000 always passes (remove in production)
  if (otp === "000000" && ALLOW_TEST_OTP) {
    // Clean up any pending OTP doc
    const docRef = db.collection("verification_otps").doc(email.toLowerCase());
    const doc = await docRef.get();
    if (doc.exists) await docRef.delete();

    const opSnap = await db.collectionGroup("operators")
      .where("email", "==", email.toLowerCase())
      .limit(1)
      .get();
    if (!opSnap.empty) {
      await opSnap.docs[0].ref.update({
        emailVerified: true,
        emailVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return { success: true, verified: true };
  }

  const docRef = db.collection("verification_otps").doc(email.toLowerCase());
  const doc = await docRef.get();

  if (!doc.exists) {
    throw new functions.https.HttpsError("not-found", "No OTP found. Request a new one.");
  }

  const otpData = doc.data();

  // Check expiry
  if (otpData.expiresAt.toDate() < new Date()) {
    await docRef.delete();
    throw new functions.https.HttpsError("deadline-exceeded", "OTP expired. Request a new one.");
  }

  // Check attempts (max 5)
  if (otpData.attempts >= OTP_MAX_ATTEMPTS) {
    await docRef.delete();
    throw new functions.https.HttpsError("resource-exhausted", "Too many attempts. Request a new OTP.");
  }

  // Verify hash
  const crypto = require("crypto");
  const inputHash = crypto.createHash("sha256").update(otp).digest("hex");

  if (inputHash !== otpData.otpHash) {
    await docRef.update({ attempts: admin.firestore.FieldValue.increment(1) });
    throw new functions.https.HttpsError("permission-denied", "Invalid OTP");
  }

  // Success — mark email as verified
  await docRef.delete();

  // Update operator record if exists
  const opSnap = await db.collectionGroup("operators")
    .where("email", "==", email.toLowerCase())
    .limit(1)
    .get();

  if (!opSnap.empty) {
    await opSnap.docs[0].ref.update({
      emailVerified: true,
      emailVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  return { success: true, verified: true };
});

/**
 * sendPhoneOTP - Sends a 6-digit OTP via FAST2SMS (DLT route).
 */
exports.sendPhoneOTP = fns.https.onCall(async (data, context) => {
  const { phone } = data;
  if (!phone || phone.length < 10) {
    throw new functions.https.HttpsError("invalid-argument", "Valid phone number required");
  }

  // Extract digits only (remove +91 prefix if present)
  const digits = phone.replace(/\D/g, "").slice(-10);
  if (digits.length !== 10) {
    throw new functions.https.HttpsError("invalid-argument", "10-digit Indian mobile number required");
  }

  await _enforceOtpCooldown(`phone_${digits}`);

  const otp = generateOTP();
  const expiresAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + OTP_EXPIRY_MS)
  );

  const crypto = require("crypto");
  const otpHash = crypto.createHash("sha256").update(otp).digest("hex");

  await db.collection("verification_otps").doc(`phone_${digits}`).set({
    otpHash,
    expiresAt,
    attempts: 0,
    type: "phone",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Send via FAST2SMS DLT route (graceful fallback if not configured)
  try {
    await _sendOtpSms(digits, otp);
  } catch (e) {
    console.warn("SMS send failed:", e.message);
  }

  return { success: true, message: "OTP sent to phone" };
});

/**
 * verifyPhoneOTP - Verifies the 6-digit OTP for phone.
 */
exports.verifyPhoneOTP = fns.https.onCall(async (data, context) => {
  const { phone, otp } = data;
  if (!phone || !otp) {
    throw new functions.https.HttpsError("invalid-argument", "Phone and OTP required");
  }

  const digits = phone.replace(/\D/g, "").slice(-10);

  // Test bypass: 000000 always passes (remove in production)
  if (otp === "000000" && ALLOW_TEST_OTP) {
    const docRef = db.collection("verification_otps").doc(`phone_${digits}`);
    const doc = await docRef.get();
    if (doc.exists) await docRef.delete();

    const opSnap = await db.collectionGroup("operators")
      .where("phone", "==", phone)
      .limit(1)
      .get();
    if (!opSnap.empty) {
      await opSnap.docs[0].ref.update({
        phoneVerified: true,
        phoneVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return { success: true, verified: true };
  }

  const docRef = db.collection("verification_otps").doc(`phone_${digits}`);
  const doc = await docRef.get();

  if (!doc.exists) {
    throw new functions.https.HttpsError("not-found", "No OTP found. Request a new one.");
  }

  const otpData = doc.data();

  if (otpData.expiresAt.toDate() < new Date()) {
    await docRef.delete();
    throw new functions.https.HttpsError("deadline-exceeded", "OTP expired. Request a new one.");
  }

  if (otpData.attempts >= OTP_MAX_ATTEMPTS) {
    await docRef.delete();
    throw new functions.https.HttpsError("resource-exhausted", "Too many attempts. Request a new OTP.");
  }

  const crypto = require("crypto");
  const inputHash = crypto.createHash("sha256").update(otp).digest("hex");

  if (inputHash !== otpData.otpHash) {
    await docRef.update({ attempts: admin.firestore.FieldValue.increment(1) });
    throw new functions.https.HttpsError("permission-denied", "Invalid OTP");
  }

  await docRef.delete();

  // Update operator record
  const opSnap = await db.collectionGroup("operators")
    .where("phone", "==", phone)
    .limit(1)
    .get();

  if (!opSnap.empty) {
    await opSnap.docs[0].ref.update({
      phoneVerified: true,
      phoneVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  return { success: true, verified: true };
});

// ─── Update Company Contact (Email/Phone) ────────────────────────────────────

/**
 * verifyOTP - Verifies an OTP without performing any update action.
 * Used to confirm current email/phone ownership before allowing a change.
 */
exports.verifyOTP = fns.https.onCall(async (data) => {
  const { target, otp, type } = data;

  if (!target || !otp || !type) {
    throw new functions.https.HttpsError("invalid-argument", "target, otp, and type required");
  }

  const crypto = require("crypto");
  const inputHash = crypto.createHash("sha256").update(otp).digest("hex");

  let docId;
  if (type === "email") {
    docId = target.toLowerCase();
  } else {
    const digits = target.replace(/\D/g, "").slice(-10);
    docId = `phone_${digits}`;
  }

  const otpRef = db.collection("verification_otps").doc(docId);
  const otpDoc = await otpRef.get();

  if (!otpDoc.exists) {
    return { valid: false, message: "No OTP found. Request a new one." };
  }

  const otpData = otpDoc.data();

  if (otpData.expiresAt.toDate() < new Date()) {
    await otpRef.delete();
    return { valid: false, message: "OTP expired. Request a new one." };
  }

  if (otpData.attempts >= OTP_MAX_ATTEMPTS) {
    await otpRef.delete();
    return { valid: false, message: "Too many attempts. Request a new OTP." };
  }

  if (inputHash !== otpData.otpHash) {
    await otpRef.update({ attempts: admin.firestore.FieldValue.increment(1) });
    return { valid: false, message: "Invalid code. Please try again." };
  }

  // Don't delete — updateCompanyContact will verify it again with currentOtp
  // Mark as verified so it can be checked later
  await otpRef.update({ verified: true });

  return { valid: true };
});

/**
 * updateCompanyContact - Updates email or phone after OTP verification.
 * Propagates to: generalSettings, company doc, license record, operator record.
 */
exports.updateCompanyContact = fns.https.onCall(async (data, context) => {
  const { companyId, siteId, weighbridgeId, field, newValue, otp } = data;

  if (!companyId || !field || !newValue || !otp) {
    throw new functions.https.HttpsError("invalid-argument", "Missing required fields");
  }
  await _requireAdminSession(data, companyId); // only an admin of this company may change its contact

  if (field !== "email" && field !== "phone") {
    throw new functions.https.HttpsError("invalid-argument", "Field must be 'email' or 'phone'");
  }

  // Verify OTP first
  const crypto = require("crypto");
  const inputHash = crypto.createHash("sha256").update(otp).digest("hex");

  let docId;
  if (field === "email") {
    docId = newValue.toLowerCase();
  } else {
    const digits = newValue.replace(/\D/g, "").slice(-10);
    docId = `phone_${digits}`;
  }

  const otpRef = db.collection("verification_otps").doc(docId);
  const otpDoc = await otpRef.get();

  if (!otpDoc.exists) {
    throw new functions.https.HttpsError("not-found", "No OTP found. Request a new one.");
  }

  const otpData = otpDoc.data();

  if (otpData.expiresAt.toDate() < new Date()) {
    await otpRef.delete();
    throw new functions.https.HttpsError("deadline-exceeded", "OTP expired. Request a new one.");
  }

  if (otpData.attempts >= OTP_MAX_ATTEMPTS) {
    await otpRef.delete();
    throw new functions.https.HttpsError("resource-exhausted", "Too many attempts. Request a new OTP.");
  }

  if (inputHash !== otpData.otpHash) {
    await otpRef.update({ attempts: admin.firestore.FieldValue.increment(1) });
    throw new functions.https.HttpsError("permission-denied", "Invalid OTP");
  }

  // OTP verified — delete it
  await otpRef.delete();

  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();

  // 1. Update generalSettings
  const settingsPath = `companies/${companyId}/sites/${siteId}/weighbridges/${weighbridgeId}/settings/general`;
  batch.set(db.doc(settingsPath), {
    [field]: field === "email" ? newValue.toLowerCase() : newValue,
    [`${field}Verified`]: true,
    [`${field}VerifiedAt`]: now,
    updatedAt: now,
  }, { merge: true });

  // 2. Update company doc
  batch.set(db.doc(`companies/${companyId}`), {
    [field]: field === "email" ? newValue.toLowerCase() : newValue,
    [`${field}UpdatedAt`]: now,
  }, { merge: true });

  // 3. Update license record if exists
  const companyDoc = await db.doc(`companies/${companyId}`).get();
  if (companyDoc.exists) {
    const companyData = companyDoc.data();
    const licenseKey = companyData?.license?.currentLicenseKey;
    if (licenseKey) {
      batch.set(db.doc(`licenses/${licenseKey}`), {
        [`contact_${field}`]: field === "email" ? newValue.toLowerCase() : newValue,
        lastContactUpdate: now,
      }, { merge: true });
    }
  }

  // 4. Update current operator record
  if (context.auth?.token?.email) {
    const opSnap = await db.collectionGroup("operators")
      .where("email", "==", context.auth.token.email)
      .limit(1)
      .get();

    if (!opSnap.empty) {
      batch.update(opSnap.docs[0].ref, {
        [field]: field === "email" ? newValue.toLowerCase() : newValue,
        [`${field}Verified`]: true,
        [`${field}VerifiedAt`]: now,
      });
    }
  }

  await batch.commit();

  // Audit log — use the canonical `auditLog` collection (the onAuditLogCreated
  // trigger fires on `auditLog`; the old `audit_log` name was a dead write).
  await db.collection(`companies/${companyId}/auditLog`).add({
    event: "contactUpdate",
    description: `Company ${field} updated to ${field === "email" ? newValue.toLowerCase() : newValue}`,
    user: context.auth?.token?.email || "system",
    timestamp: now,
  });

  // Confirm to the NEW contact and alert the OLD one (the security signal).
  // companyDoc was read before commit, so it still holds the previous values.
  const oldData = companyDoc.exists ? (companyDoc.data() || {}) : {};
  const newVal = field === "email" ? newValue.toLowerCase() : newValue;
  const oldVal = oldData[field] || null;
  const label = field === "email" ? "email address" : "phone number";
  const adminName = oldData.contactName || oldData.name || "there";
  const contactNotif = {
    category: "account",
    link: "/profile",
    operatorEmail: oldData.email || newVal || null, // the account whose contact changed
    accent: "warn",
    heading: `Account ${label} updated`,
    intro: `Hi ${adminName}, the ${label} on your ${BRAND.name} account was just changed.`,
    rows: [["Updated field", label], ["New value", newVal]],
    note: `If you did not make this change, contact ${BRAND.support} immediately.`,
  };
  if (field === "email") {
    await notifyContact({ to: { email: newVal }, subject: `${BRAND.name}: your email was updated`, companyId, notif: contactNotif, critical: true });
    if (oldVal && oldVal !== newVal) {
      await notifyContact({ to: { email: oldVal }, subject: `${BRAND.name}: your email was changed`, companyId, notif: contactNotif, critical: true, skipInApp: true });
    }
  } else {
    // Phone change → email + in-app only (no SMS to the phone numbers).
    if (oldData.email) {
      await notifyContact({ to: { email: oldData.email }, subject: `${BRAND.name}: your phone number was updated`, companyId, notif: contactNotif, critical: true });
    } else {
      await notifyContact({ companyId, notif: contactNotif }); // in-app notice at least
    }
  }

  return { success: true, field, verified: true };
});

// ─── GSTIN Lookup & Validation ───────────────────────────────────────────────

/**
 * lookupGstin - Looks up GSTIN via public API and returns trade/legal name + status.
 * Used for owner confirmation and company name cross-validation.
 */
exports.lookupGstin = fns.https.onCall(async (data, context) => {
  const { gstin } = data;

  if (!gstin || gstin.length !== 15) {
    throw new functions.https.HttpsError("invalid-argument", "Valid 15-character GSTIN required");
  }

  const normalized = gstin.replace(/[^A-Z0-9]/gi, "").toUpperCase();
  const gstRegex = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$/;
  if (!gstRegex.test(normalized)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid GSTIN format");
  }

  // Rate limiting: per-user (if authenticated) or per-GSTIN
  const uid = context.auth?.uid || "anonymous";
  const now = Date.now();
  const oneHourAgo = new Date(now - 60 * 60 * 1000);
  const oneDayAgo = new Date(now - 24 * 60 * 60 * 1000);

  try {
    // Check cache first — return immediately if this GSTIN was looked up within 24h
    const gstinLookups = await db.collection("gstin_lookups")
      .where("gstin", "==", normalized)
      .where("timestamp", ">", admin.firestore.Timestamp.fromDate(oneDayAgo))
      .get();

    if (gstinLookups.size > 0) {
      const cached = gstinLookups.docs[0].data();
      if (cached.result) {
        return { success: true, data: cached.result, cached: true };
      }
    }

    // Rate limit: max 5 lookups per user per hour
    if (uid !== "anonymous") {
      const userLookups = await db.collection("gstin_lookups")
        .where("uid", "==", uid)
        .where("timestamp", ">", admin.firestore.Timestamp.fromDate(oneHourAgo))
        .get();

      if (userLookups.size >= 5) {
        throw new functions.https.HttpsError("resource-exhausted", "Too many lookups. Try again in an hour.");
      }
    }
  } catch (cacheErr) {
    // If it's our own rate-limit error, rethrow
    if (cacheErr instanceof functions.https.HttpsError) throw cacheErr;
    // Index not ready or other Firestore error — skip cache, proceed with lookup
    console.warn("Cache/rate-limit check skipped:", cacheErr.message);
  }

  try {
    const fetch = (await import("node-fetch")).default;

    // GSTIN checksum validation (Luhn mod 36 on first 14 chars)
    function validateGstinChecksum(gst) {
      const chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
      let factor = 1, total = 0;
      for (let i = 0; i < 14; i++) {
        const codePoint = chars.indexOf(gst[i]);
        let digit = factor * codePoint;
        digit = Math.floor(digit / 36) + (digit % 36);
        total += digit;
        factor = factor === 2 ? 1 : 2;
      }
      const checkCode = (36 - (total % 36)) % 36;
      return chars[checkCode] === gst[14];
    }

    const checksumValid = validateGstinChecksum(normalized);
    let result = null;

    // Try paid/configured GST API if available
    const gstApiKey = process.env.GSTIN_API_KEY;
    if (gstApiKey) {
      try {
        const response = await fetch(
          `https://appyflow.in/api/verifyGST?gstNo=${normalized}&key_secret=${gstApiKey}`,
          { method: "GET", headers: { "Accept": "application/json" }, signal: AbortSignal.timeout(8000) }
        );
        if (response.ok) {
          const json = await response.json();
          if (json && !json.error && json.taxpayerInfo) {
            const info = json.taxpayerInfo;

            // Verify the returned GSTIN matches what we asked for
            const returnedGstin = (info.gstin || "").toUpperCase();
            if (returnedGstin && returnedGstin !== normalized) {
              // API returned data for a different GSTIN (sandbox/test key behavior)
              // Skip this result and fall through to structural validation
            } else {
              // Build address as two logical lines
              let addressLine1 = "";
              let addressLine2 = "";
              if (info.pradr?.addr) {
                const a = info.pradr.addr;
                // Line 1: building/floor/street/locality
                const streetParts = [a.bno, a.bnm, a.flno, a.st, a.loc].filter(Boolean);
                addressLine1 = streetParts.join(", ");
                // Line 2: city/district/state/pin
                const cityParts = [a.dst, a.city, a.stcd, a.pncd].filter(Boolean);
                addressLine2 = cityParts.join(", ");
              } else if (typeof info.pradr?.adr === "string") {
                addressLine1 = info.pradr.adr;
              }

              const stateFromAddr = info.pradr?.addr?.stcd || "";

              result = {
                gstin: normalized,
                legalName: info.lgnm || "",
                tradeName: info.tradeNam || "",
                status: info.sts || "Unknown",
                stateCode: normalized.substring(0, 2),
                stateName: stateFromAddr || "",
                registrationDate: info.rgdt || "",
                constitutionOfBusiness: info.ctb || "",
                address: addressLine1,
                address2: addressLine2,
                verified: true,
              };
            }
          }
        }
      } catch (_) {}
    }

    // State code lookup table
    const stateCodes = {
      "01": "Jammu & Kashmir", "02": "Himachal Pradesh", "03": "Punjab",
      "04": "Chandigarh", "05": "Uttarakhand", "06": "Haryana",
      "07": "Delhi", "08": "Rajasthan", "09": "Uttar Pradesh",
      "10": "Bihar", "11": "Sikkim", "12": "Arunachal Pradesh",
      "13": "Nagaland", "14": "Manipur", "15": "Mizoram",
      "16": "Tripura", "17": "Meghalaya", "18": "Assam",
      "19": "West Bengal", "20": "Jharkhand", "21": "Odisha",
      "22": "Chhattisgarh", "23": "Madhya Pradesh", "24": "Gujarat",
      "26": "Dadra & Nagar Haveli", "27": "Maharashtra", "29": "Karnataka",
      "30": "Goa", "31": "Lakshadweep", "32": "Kerala",
      "33": "Tamil Nadu", "34": "Puducherry", "35": "Andaman & Nicobar",
      "36": "Telangana", "37": "Andhra Pradesh",
    };

    const panFromGstin = normalized.substring(2, 12);
    const stateCode = normalized.substring(0, 2);

    const entityTypeFromPan = panFromGstin[3] === "P" ? "Individual/Proprietor"
      : panFromGstin[3] === "C" ? "Company"
      : panFromGstin[3] === "F" ? "Firm/LLP"
      : panFromGstin[3] === "H" ? "HUF"
      : panFromGstin[3] === "A" ? "AOP/BOI/Trust"
      : panFromGstin[3] === "T" ? "AOP (Trust)"
      : panFromGstin[3] === "G" ? "Government"
      : "Other";

    // Enrich online result with derived fields
    if (result) {
      result.pan = panFromGstin;
      result.entityType = result.constitutionOfBusiness || entityTypeFromPan;
      result.checksumValid = checksumValid;
      if (!result.stateName) {
        result.stateName = stateCodes[stateCode] || "Unknown";
      }
    }

    // Structural validation fallback (no external API needed)
    if (!result) {
      result = {
        gstin: normalized,
        legalName: "",
        tradeName: "",
        status: checksumValid ? "Format Valid" : "Invalid Checksum",
        stateCode,
        stateName: stateCodes[stateCode] || "Unknown",
        pan: panFromGstin,
        entityType: entityTypeFromPan,
        checksumValid,
        verified: false,
      };
    }

    // Log this lookup for rate limiting + caching
    await db.collection("gstin_lookups").add({
      uid,
      gstin: normalized,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      result,
    });

    return { success: true, data: result };
  } catch (e) {
    throw new functions.https.HttpsError("internal", `GSTIN lookup failed: ${e.message || e}`);
  }
});

// ─── GSTIN Ownership Verification via E-Way Bill ─────────────────────────────

/**
 * verifyGstinOwnership - Verifies GSTIN ownership by checking an e-way bill number.
 * The user provides an e-way bill they generated; we verify the supplier GSTIN matches.
 * Fallback: structural validation of e-way bill format + GSTIN cross-check.
 */
exports.verifyGstinOwnership = fns.https.onCall(async (data, context) => {
  const { gstin, ewayBillNo, companyId } = data;

  if (!gstin || gstin.length !== 15) {
    throw new functions.https.HttpsError("invalid-argument", "Valid 15-character GSTIN required");
  }
  if (!ewayBillNo || ewayBillNo.length < 10 || ewayBillNo.length > 12) {
    throw new functions.https.HttpsError("invalid-argument", "Valid e-way bill number required (10-12 digits)");
  }

  const normalized = gstin.replace(/[^A-Z0-9]/gi, "").toUpperCase();
  const ewbNormalized = ewayBillNo.replace(/\D/g, "");

  if (!/^\d{10,12}$/.test(ewbNormalized)) {
    throw new functions.https.HttpsError("invalid-argument", "E-way bill must be 10-12 digits");
  }

  try {
    const fetch = (await import("node-fetch")).default;
    const gstApiKey = process.env.GSTIN_API_KEY;

    let verified = false;
    let verificationMethod = "none";
    let ewbData = null;

    // Try e-way bill verification via Appyflow
    if (gstApiKey) {
      try {
        const response = await fetch(
          `https://appyflow.in/api/verifyEwayBill?ewbNo=${ewbNormalized}&key_secret=${gstApiKey}`,
          { method: "GET", headers: { "Accept": "application/json" }, signal: AbortSignal.timeout(10000) }
        );
        if (response.ok) {
          const json = await response.json();
          if (json && !json.error) {
            const info = json.ewayBillInfo || json.data || json;
            const supplierGstin = (info.fromGstin || info.userGstin || info.fromTrdName || "").toUpperCase();
            const toGstin = (info.toGstin || "").toUpperCase();

            ewbData = {
              ewbNo: ewbNormalized,
              fromGstin: supplierGstin,
              toGstin,
              docNo: info.docNo || info.invoiceNumber || "",
              docDate: info.docDate || info.invoiceDate || "",
              totalValue: info.totInvValue || info.totalValue || null,
              status: info.status || info.ewbStatus || "Unknown",
            };

            // Verify: GSTIN must be either supplier or recipient
            if (supplierGstin === normalized || toGstin === normalized) {
              verified = true;
              verificationMethod = "ewb_api";
            }
          }
        }
      } catch (_) {}
    }

    // Record the verification attempt
    const verificationRecord = {
      gstin: normalized,
      ewayBillNo: ewbNormalized,
      verified,
      verificationMethod,
      ewbData,
      attemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      attemptedBy: context.auth?.token?.email || "unknown",
    };

    // Store in company's verification records
    if (companyId) {
      await db.collection(`companies/${companyId}/gstin_verifications`).add(verificationRecord);
    }

    // If verified, mark in GSTIN registry
    if (verified && companyId) {
      const registryRef = db.collection("gstin_registry").doc(normalized);
      await registryRef.set({
        ownershipVerified: true,
        ownershipVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        ownershipMethod: verificationMethod,
        ewayBillUsed: ewbNormalized,
      }, { merge: true });

      // Also update company doc
      await db.doc(`companies/${companyId}`).set({
        gstinVerified: true,
        gstinVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        gstinVerificationMethod: verificationMethod,
      }, { merge: true });

      await _writeInApp({
        companyId, category: "kyc", severity: "info", link: "/settings/general",
        title: "GSTIN verified",
        body: `Your GSTIN ${normalized} ownership was confirmed via e-way bill.`,
      }).catch((e) => console.warn("gstin-verified notice failed:", e.message));
    }

    return {
      success: true,
      verified,
      method: verificationMethod,
      ewbData: verified ? ewbData : null,
      message: verified
        ? "GSTIN ownership verified via e-way bill"
        : gstApiKey
          ? "E-way bill could not be matched to this GSTIN. Ensure you are the supplier or recipient."
          : "E-way bill verification service not configured",
    };
  } catch (e) {
    throw new functions.https.HttpsError("internal", `Verification failed: ${e.message || e}`);
  }
});

// ─── Migrate Free Tier Users to Trial ─────────────────────────────────────────

exports.migrateFreeTierToTrial = fns.https.onCall(async (data, context) => {
  const now = admin.firestore.Timestamp.now();
  const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;
  const expiresAt = admin.firestore.Timestamp.fromMillis(now.toMillis() + thirtyDaysMs);
  const trialFeatures = ["multi_weighbridge", "ip_cameras", "rtsp", "ai_anpr", "ai_material", "ai_face", "gate_control", "integrations", "advanced_security", "multi_site"];
  let count = 0;

  // Migrate standalone licenses collection
  const licensesSnap = await db.collection("licenses")
    .where("tier", "==", "free")
    .where("status", "==", "active")
    .get();

  if (!licensesSnap.empty) {
    const batch = db.batch();
    for (const doc of licensesSnap.docs) {
      batch.update(doc.ref, {
        tier: "trial",
        trialStartedAt: now,
        expiresAt: expiresAt,
        maxWeighbridges: 2,
        maxSites: 1,
        features: trialFeatures,
        migratedFromFree: true,
        migratedAt: now,
      });

      const licenseData = doc.data();
      if (licenseData.companyId) {
        const companyLicenseRef = db.doc(`companies/${licenseData.companyId}/license`);
        batch.set(companyLicenseRef, {
          currentLicenseKey: doc.id,
          tier: "trial",
          status: "active",
          expiresAt: expiresAt,
          lastValidatedAt: now,
          features: trialFeatures,
        }, { merge: true });
      }
      count++;
    }
    await batch.commit();
  }

  // Migrate inline company license fields (companies/{id}.license.tier == "free")
  const companiesSnap = await db.collection("companies").get();
  const batch2 = db.batch();
  let inlineCount = 0;

  for (const doc of companiesSnap.docs) {
    const companyData = doc.data();
    const license = companyData.license;
    if (license && license.tier === "free" && license.status !== "expired" && license.status !== "revoked") {
      batch2.update(doc.ref, {
        "license.tier": "trial",
        "license.trialStartedAt": now,
        "license.expiresAt": expiresAt,
        "license.maxWeighbridges": 2,
        "license.maxSites": 1,
        "license.features": trialFeatures,
        "license.migratedFromFree": true,
        "license.migratedAt": now,
      });
      inlineCount++;
    }
  }

  if (inlineCount > 0) {
    await batch2.commit();
  }

  count += inlineCount;
  return { migrated: count, message: `Migrated ${count} free tier license(s) to 30-day trial` };
});

// ─── Verify Document (GSTIN Certificate / PAN Card via Vision OCR) ──────────

const vision = require("@google-cloud/vision");
const Jimp = require("jimp");

exports.verifyDocument = fns.runWith({ timeoutSeconds: 60, memory: "512MB" }).https.onCall(async (data) => {
  const { imageBase64, documentType, expectedGstin, expectedPan } = data;

  if (!imageBase64 || !documentType) {
    throw new functions.https.HttpsError("invalid-argument", "imageBase64 and documentType required");
  }
  if (!expectedGstin && !expectedPan) {
    throw new functions.https.HttpsError("invalid-argument", "expectedGstin or expectedPan required");
  }

  const client = new vision.ImageAnnotatorClient();
  const imageBuffer = Buffer.from(imageBase64, "base64");
  const isPdf = imageBuffer.slice(0, 5).toString() === "%PDF-";
  functions.logger.info(`verifyDocument: type=${documentType}, imageSize=${imageBuffer.length} bytes, isPdf=${isPdf}`);

  let fullText = "";
  try {
    if (isPdf) {
      const [filesResponse] = await client.batchAnnotateFiles({
        requests: [{
          inputConfig: { content: imageBuffer, mimeType: "application/pdf" },
          features: [{ type: "DOCUMENT_TEXT_DETECTION" }],
          pages: [1, 2],
        }],
      });
      const fileResp = filesResponse.responses && filesResponse.responses[0];
      if (fileResp && fileResp.responses) {
        for (const page of fileResp.responses) {
          if (page.fullTextAnnotation && page.fullTextAnnotation.text) {
            fullText += page.fullTextAnnotation.text.toUpperCase().replace(/\s+/g, " ") + " ";
          }
        }
      }
      fullText = fullText.trim();
    } else {
      const [docResult] = await client.documentTextDetection({ image: { content: imageBuffer } });
      if (docResult.fullTextAnnotation && docResult.fullTextAnnotation.text) {
        fullText = docResult.fullTextAnnotation.text.toUpperCase().replace(/\s+/g, " ");
      }
      if (!fullText) {
        const [result] = await client.textDetection({ image: { content: imageBuffer } });
        const detections = result.textAnnotations;
        if (detections && detections.length > 0) {
          fullText = detections[0].description.toUpperCase().replace(/\s+/g, " ");
        }
      }
    }
  } catch (visionErr) {
    functions.logger.error("Vision API error:", visionErr.message || visionErr);
    throw new functions.https.HttpsError("unavailable", `Vision API error: ${visionErr.message || "unknown"}`);
  }

  functions.logger.info(`verifyDocument: extracted ${fullText.length} chars`);

  if (!fullText) {
    return { valid: false, error: "no_text", message: "No text could be extracted from the document" };
  }

  // Normalize: collapse spaces between alphanumeric chars for matching IDs
  const normalizedText = fullText.replace(/([A-Z0-9])\s+([A-Z0-9])/g, "$1$2");
  functions.logger.info(`verifyDocument: normalizedText preview: ${normalizedText.substring(0, 500)}`);

  if (documentType === "gstin_certificate") {
    const gstin = (expectedGstin || "").toUpperCase().trim();
    if (!gstin) {
      return { valid: false, error: "missing_gstin", message: "Expected GSTIN not provided" };
    }
    const derivedPan = gstin.substring(2, 12);

    // 0. Reject if this is actually a PAN card
    const panExclusionKeywords = ["INCOME TAX DEPARTMENT", "INCOMETAX", "PERMANENT ACCOUNT NUMBER", "IT DEPARTMENT", "FATHER'S NAME", "DATE OF BIRTH"];
    const panExclusions = panExclusionKeywords.filter(kw => fullText.includes(kw) || normalizedText.includes(kw));
    const hasGstHints = fullText.includes("GOODS AND SERVICES") || fullText.includes("GSTIN") || fullText.includes("CERTIFICATE OF REGISTRATION");
    if (panExclusions.length >= 2 && !hasGstHints) {
      functions.logger.info(`verifyDocument: GSTIN slot rejected — looks like PAN card. PAN keywords: [${panExclusions.join(", ")}]`);
      return {
        valid: false,
        error: "wrong_document",
        message: "This appears to be a PAN Card, not a GSTIN Certificate. Please upload the GST Registration Certificate.",
      };
    }

    // 1. Document type verification — must look like a GST certificate
    const gstKeywords = [
      "CERTIFICATE OF REGISTRATION",
      "GOODS AND SERVICES TAX",
      "GOODS & SERVICES TAX",
      "GST",
      "CENTRAL BOARD OF INDIRECT TAXES",
      "CBIC",
      "GOVERNMENT OF INDIA",
      "REGISTRATION CERTIFICATE",
      "GSTIN",
      "TAXPAYER",
      "TAX PAYER",
      "PLACE OF BUSINESS",
      "PRINCIPAL PLACE",
      "TRADE NAME",
      "LEGAL NAME",
      "DATE OF LIABILITY",
      "EFFECTIVE DATE OF REGISTRATION",
      "CONSTITUTION OF BUSINESS",
    ];
    const keywordsFound = gstKeywords.filter(kw => fullText.includes(kw) || normalizedText.includes(kw));
    functions.logger.info(`verifyDocument: GST keywords found: [${keywordsFound.join(", ")}]`);

    if (keywordsFound.length < 3) {
      return {
        valid: false,
        error: "not_gst_certificate",
        message: "This does not appear to be a GST Registration Certificate. Upload the official certificate from the GST portal.",
        keywordsFound,
      };
    }

    // 2. GSTIN number match
    const gstinFound = fullText.includes(gstin) || normalizedText.includes(gstin);
    if (!gstinFound) {
      return { valid: false, error: "gstin_not_found", message: `GSTIN ${gstin} not found in the certificate. Ensure the uploaded certificate belongs to this GSTIN.` };
    }

    // 3. PAN embedded in GSTIN must be present
    const panFound = fullText.includes(derivedPan) || normalizedText.includes(derivedPan);
    if (!panFound) {
      return { valid: false, error: "pan_mismatch", message: `PAN ${derivedPan} (derived from GSTIN) not found in certificate` };
    }

    // 4. State code consistency — first 2 chars of GSTIN = state code
    const stateCode = gstin.substring(0, 2);
    const stateCodeInText = fullText.includes(stateCode) || normalizedText.includes(stateCode);

    // 5. Look for "Active" status (bonus, not blocking)
    const hasActiveStatus = fullText.includes("ACTIVE") || normalizedText.includes("ACTIVE");

    return {
      valid: true,
      gstinFound: true,
      panFound: true,
      derivedPan,
      stateCode,
      stateCodePresent: stateCodeInText,
      statusActive: hasActiveStatus,
      keywordsMatched: keywordsFound.length,
    };
  }

  if (documentType === "pan_card") {
    const pan = (expectedPan || "").toUpperCase().trim();
    if (!pan) {
      return { valid: false, error: "missing_pan", message: "Expected PAN not provided" };
    }

    // 1. Reject if this is actually a GSTIN certificate
    const gstExclusionKeywords = [
      "CERTIFICATE OF REGISTRATION",
      "GOODS AND SERVICES TAX",
      "GOODS & SERVICES TAX",
      "GSTIN",
      "PLACE OF BUSINESS",
      "PRINCIPAL PLACE",
      "DATE OF LIABILITY",
      "EFFECTIVE DATE OF REGISTRATION",
      "CONSTITUTION OF BUSINESS",
      "CENTRAL BOARD OF INDIRECT TAXES",
    ];
    const gstExclusions = gstExclusionKeywords.filter(kw => fullText.includes(kw) || normalizedText.includes(kw));
    if (gstExclusions.length >= 2) {
      functions.logger.info(`verifyDocument: PAN slot rejected — looks like GST cert. GST keywords: [${gstExclusions.join(", ")}]`);
      return {
        valid: false,
        error: "wrong_document",
        message: "This appears to be a GSTIN Certificate, not a PAN Card. Please upload the actual PAN Card.",
      };
    }

    // 2. Document type verification — must look like a PAN card
    const panKeywords = [
      "INCOME TAX",
      "PERMANENT ACCOUNT NUMBER",
      "INCOME TAX DEPARTMENT",
      "INCOMETAX",
      "IT DEPARTMENT",
      "FATHER",
      "DATE OF BIRTH",
      "DOB",
    ];
    const panGenericKeywords = [
      "GOVT. OF INDIA",
      "GOVT OF INDIA",
      "GOVERNMENT OF INDIA",
      "SIGNATURE",
    ];
    const specificFound = panKeywords.filter(kw => fullText.includes(kw) || normalizedText.includes(kw));
    const genericFound = panGenericKeywords.filter(kw => fullText.includes(kw) || normalizedText.includes(kw));
    functions.logger.info(`verifyDocument: PAN specific keywords: [${specificFound.join(", ")}], generic: [${genericFound.join(", ")}]`);

    // Require at least 1 specific PAN keyword (not just generic govt keywords)
    if (specificFound.length < 1) {
      return {
        valid: false,
        error: "not_pan_card",
        message: "This does not appear to be a PAN Card. Upload the official PAN card issued by the Income Tax Department.",
        keywordsFound: [...specificFound, ...genericFound],
      };
    }

    // 3. PAN number match
    const panRegex = /[A-Z]{5}[0-9]{4}[A-Z]/g;
    const matchesRaw = fullText.match(panRegex) || [];
    const matchesNorm = normalizedText.match(panRegex) || [];
    const allMatches = [...new Set([...matchesRaw, ...matchesNorm])];
    const panFound = allMatches.includes(pan) || fullText.includes(pan) || normalizedText.includes(pan);

    if (!panFound) {
      return {
        valid: false,
        error: "pan_not_found",
        message: `PAN ${pan} not found on this card. Ensure the uploaded PAN card belongs to the entity linked to your GSTIN.`,
        extractedPans: allMatches,
      };
    }

    // 4. Validate PAN structure (4th char tells entity type)
    const panEntityChar = pan.charAt(3);
    const entityTypes = { P: "Individual", C: "Company", H: "HUF", F: "Firm", A: "AOP", T: "Trust", B: "BOI", L: "Local Authority", J: "Artificial Juridical Person", G: "Government" };
    const entityType = entityTypes[panEntityChar] || "Unknown";

    return {
      valid: true,
      panFound: true,
      panEntityType: entityType,
      keywordsMatched: specificFound.length + genericFound.length,
    };
  }

  return { valid: false, error: "unknown_type", message: "Unknown documentType" };
});

/**
 * verifyOperatorId - Scans uploaded ID document(s) (Aadhaar/PAN/DL/Passport).
 * Accepts multiple images (front+back) or a multi-page PDF.
 * Extracts name, verifies document type, compares name with operator's name.
 * Returns: extracted name, document number, match status, suggested name if mismatch.
 */
exports.verifyOperatorId = fns.runWith({ timeoutSeconds: 90, memory: "512MB" }).https.onCall(async (data) => {
  const { images, imageBase64, documentType, operatorName, operatorId, companyId } = data;

  // Support both: `images` (array) and legacy `imageBase64` (single string)
  const imageList = images || (imageBase64 ? [imageBase64] : []);

  if (!imageList.length || !documentType || !operatorName) {
    throw new functions.https.HttpsError("invalid-argument", "images (or imageBase64), documentType, and operatorName required");
  }

  const client = new vision.ImageAnnotatorClient();

  // Process all images/pages and combine text
  let fullText = "";
  try {
    for (const img of imageList) {
      const imageBuffer = Buffer.from(img, "base64");
      const isPdf = imageBuffer.slice(0, 5).toString() === "%PDF-";

      if (isPdf) {
        const [filesResponse] = await client.batchAnnotateFiles({
          requests: [{
            inputConfig: { content: imageBuffer, mimeType: "application/pdf" },
            features: [{ type: "DOCUMENT_TEXT_DETECTION" }],
            pages: [1, 2, 3, 4],
          }],
        });
        const fileResp = filesResponse.responses && filesResponse.responses[0];
        if (fileResp && fileResp.responses) {
          for (const page of fileResp.responses) {
            if (page.fullTextAnnotation && page.fullTextAnnotation.text) {
              fullText += page.fullTextAnnotation.text + "\n";
            }
          }
        }
      } else {
        const [docResult] = await client.documentTextDetection({ image: { content: imageBuffer } });
        if (docResult.fullTextAnnotation && docResult.fullTextAnnotation.text) {
          fullText += docResult.fullTextAnnotation.text + "\n";
        } else {
          const [result] = await client.textDetection({ image: { content: imageBuffer } });
          const detections = result.textAnnotations;
          if (detections && detections.length > 0) {
            fullText += detections[0].description + "\n";
          }
        }
      }
    }
  } catch (visionErr) {
    throw new functions.https.HttpsError("unavailable", `Vision API error: ${visionErr.message || "unknown"}`);
  }

  if (!fullText || fullText.trim().length < 10) {
    return { valid: false, error: "no_text", message: "Could not extract text from the document." };
  }

  const upperText = fullText.toUpperCase().replace(/\s+/g, " ").trim();
  const lines = fullText.split(/\n/).map(l => l.trim()).filter(l => l.length > 0);

  // Document type detection and name/address extraction
  let extractedName = null;
  let extractedDocNumber = null;
  let extractedAddress = null;
  let detectedType = null;
  let isValidDoc = false;

  if (documentType === "Aadhaar") {
    // Aadhaar: 12 digit number is mandatory
    const aadhaarRegex = /\b\d{4}\s?\d{4}\s?\d{4}\b/;
    const aadhaarMatch = fullText.match(aadhaarRegex);
    if (aadhaarMatch) {
      extractedDocNumber = aadhaarMatch[0].replace(/\s/g, "");
      detectedType = "Aadhaar";
    }
    // Aadhaar keywords
    const aadhaarKeywords = ["UNIQUE IDENTIFICATION", "AADHAAR", "UIDAI", "GOVERNMENT OF INDIA", "MERA AADHAAR"];
    const keyFound = aadhaarKeywords.some(kw => upperText.includes(kw));
    // Valid only if document number found AND at least one keyword, or number + DOB/gender
    const hasAadhaarContext = keyFound || upperText.includes("DOB") || /MALE|FEMALE/.test(upperText) || upperText.includes("DATE OF BIRTH");
    if (aadhaarMatch && hasAadhaarContext) { isValidDoc = true; }


    // Name extraction: typically the line above or 2 lines above the DOB/Aadhaar number
    // Look for a line that's all alphabetic with spaces (name pattern)
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      // Skip known labels
      if (/^(DOB|Date of Birth|Male|Female|MALE|FEMALE|GOVERNMENT|UNIQUE|AADHAAR|UIDAI|\d)/i.test(line)) continue;
      // Name is typically all letters + spaces, 2+ words
      if (/^[A-Za-z\s]+$/.test(line) && line.split(/\s+/).length >= 2 && line.length > 4) {
        extractedName = line;
        break;
      }
    }

    // Address extraction: look for "Address" label, collect lines until pincode
    for (let i = 0; i < lines.length; i++) {
      if (/^address\s*[:.]?/i.test(lines[i])) {
        const addrLines = [];
        const firstLine = lines[i].replace(/^address\s*[:.]?\s*/i, "").trim();
        if (firstLine.length > 3) addrLines.push(firstLine);
        for (let j = i + 1; j < lines.length && j < i + 8; j++) {
          const l = lines[j].trim();
          if (/^\d{4}\s?\d{4}\s?\d{4}$/.test(l)) break; // hit aadhaar number
          if (/^(VID|vid)\s*:/i.test(l)) break;
          addrLines.push(l);
          if (/\b\d{6}\b/.test(l)) break; // pincode found, end of address
        }
        if (addrLines.length > 0) extractedAddress = addrLines.join(", ");
        break;
      }
    }
  }

  if (documentType === "PAN") {
    // PAN: XXXXX9999X format is mandatory
    const panRegex = /[A-Z]{5}[0-9]{4}[A-Z]/;
    const panMatch = upperText.match(panRegex);
    if (panMatch) {
      extractedDocNumber = panMatch[0];
      detectedType = "PAN";
    }
    const panKeywords = ["INCOME TAX", "PERMANENT ACCOUNT NUMBER", "INCOMETAX"];
    const panKeyFound = panKeywords.some(kw => upperText.includes(kw));
    // Valid only if PAN number found (strong signal), or PAN number + keyword
    if (panMatch) { isValidDoc = true; }

    // PAN: name is usually the first prominent text line (after dept header)
    let foundDept = false;
    for (const line of lines) {
      if (/INCOME TAX|PERMANENT ACCOUNT/i.test(line)) { foundDept = true; continue; }
      if (foundDept && /^[A-Za-z\s]+$/.test(line.trim()) && line.trim().split(/\s+/).length >= 2 && line.trim().length > 4) {
        extractedName = line.trim();
        break;
      }
    }
  }

  if (documentType === "Driving License") {
    // DL: XX99 + 11 digits format
    const dlRegex = /[A-Z]{2}\d{2}\s?\d{11}/;
    const dlMatch = upperText.replace(/\s/g, "").match(dlRegex);
    if (dlMatch) {
      extractedDocNumber = dlMatch[0];
      detectedType = "Driving License";
    }
    const dlKeywords = ["DRIVING", "LICENCE", "LICENSE", "TRANSPORT", "MOTOR VEHICLE"];
    const dlKeyCount = dlKeywords.filter(kw => upperText.includes(kw)).length;
    // Valid if DL number found, OR at least 2 keywords present (e.g., "DRIVING" + "LICENCE")
    if (dlMatch || dlKeyCount >= 2) { isValidDoc = true; detectedType = "Driving License"; }


    // Name after "Name" label
    for (let i = 0; i < lines.length; i++) {
      if (/^name\s*[:.]?/i.test(lines[i])) {
        const nameLine = lines[i].replace(/^name\s*[:.]?\s*/i, "").trim();
        if (nameLine.length > 3) { extractedName = nameLine; break; }
        if (i + 1 < lines.length && /^[A-Za-z\s]+$/.test(lines[i + 1].trim())) {
          extractedName = lines[i + 1].trim();
          break;
        }
      }
    }

    // Address extraction for DL
    for (let i = 0; i < lines.length; i++) {
      if (/^add(?:ress)?\s*[:.]?/i.test(lines[i])) {
        const addrLines = [];
        const firstLine = lines[i].replace(/^add(?:ress)?\s*[:.]?\s*/i, "").trim();
        if (firstLine.length > 3) addrLines.push(firstLine);
        for (let j = i + 1; j < lines.length && j < i + 8; j++) {
          const l = lines[j].trim();
          if (/^(DOI|DOB|BG|DL NO|Name|S\/W\/D|CLASS|COV|VALIDITY|MCWG|LMV)/i.test(l)) break;
          addrLines.push(l);
          if (/\b\d{6}\b/.test(l)) break; // pincode
        }
        if (addrLines.length > 0) extractedAddress = addrLines.join(", ");
        break;
      }
    }
  }

  if (documentType === "Passport") {
    // Passport: X1234567 format
    const passportRegex = /[A-Z]\d{7}/;
    const passportMatch = upperText.match(passportRegex);
    if (passportMatch) {
      extractedDocNumber = passportMatch[0];
      detectedType = "Passport";
    }
    const passportKeywords = ["PASSPORT", "REPUBLIC OF INDIA", "SURNAME", "GIVEN NAME"];
    const passportKeyCount = passportKeywords.filter(kw => upperText.includes(kw)).length;
    // Valid if passport number found + at least 1 keyword, OR 3+ keywords without number
    if ((passportMatch && passportKeyCount >= 1) || passportKeyCount >= 3) { isValidDoc = true; detectedType = "Passport"; }

    // Passport: surname + given names
    let surname = "";
    let givenNames = "";
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      // Given names — check FIRST (more specific match, avoids /nom/ stealing it)
      if (/given\s*name/i.test(line) || /pr[eé]nom/i.test(line)) {
        const cleaned = line.replace(/^.*?(?:given\s*name[s]?\s*(?:\([s]?\))?\s*[\/|]?\s*(?:pr[eé]nom[s]?)?\s*|pr[eé]nom[s]?\s*)\s*[:.]?\s*/i, "").trim();
        if (/^[A-Za-z\s]+$/.test(cleaned) && cleaned.length > 1) {
          givenNames = cleaned;
        } else if (i + 1 < lines.length) {
          const next = lines[i + 1].trim();
          const alphaOnly = next.replace(/[^A-Za-z\s]/g, "").trim();
          if (/^[A-Za-z\s]+$/.test(alphaOnly) && alphaOnly.length > 1) givenNames = alphaOnly;
        }
      }
      // Surname — only match if NOT a "given name" or "prenom" line
      else if (/surname/i.test(line) || (/\bnom\b/i.test(line) && !/pr[eé]nom/i.test(line) && !/given/i.test(line))) {
        const cleaned = line.replace(/^.*?(?:surname\s*(?:[\/|]\s*nom)?\s*|(?<![a-z])nom\s*)\s*[:.]?\s*/i, "").trim();
        if (/^[A-Za-z\s]+$/.test(cleaned) && cleaned.length > 1) {
          surname = cleaned;
        } else if (i + 1 < lines.length) {
          const next = lines[i + 1].trim();
          const alphaOnly = next.replace(/[^A-Za-z\s]/g, "").trim();
          if (/^[A-Za-z\s]+$/.test(alphaOnly) && alphaOnly.length > 1) surname = alphaOnly;
        }
      }
    }
    // Also try MRZ line (last 2 lines of passport, 44 chars each)
    if (!surname && !givenNames) {
      for (const line of lines) {
        const trimmed = line.trim().replace(/\s/g, "");
        if (/^P[<A-Z]IND/.test(trimmed) && trimmed.length >= 40) {
          const mrzName = trimmed.substring(5);
          const parts = mrzName.split("<<");
          if (parts.length >= 2) {
            surname = parts[0].replace(/</g, " ").trim();
            givenNames = parts[1].replace(/</g, " ").trim();
          }
        }
      }
    }
    // If only surname found, try to derive given names from operatorName input
    if (surname && !givenNames && operatorName) {
      const opParts = operatorName.trim().toLowerCase().split(/\s+/);
      const surnameLower = surname.trim().toLowerCase();
      const remaining = opParts.filter(p => p !== surnameLower);
      if (remaining.length > 0) {
        givenNames = remaining.map(p => p.charAt(0).toUpperCase() + p.slice(1)).join(" ");
      }
    }
    if (surname || givenNames) {
      extractedName = [givenNames, surname].filter(Boolean).join(" ");
    }

    // Passport address extraction — Indian passport last page format:
    // "Address" label followed by multi-line residential address (can be 3-8 lines)
    // terminated by pincode line, or next field ("Name of Father", "Name of Mother", "Spouse", "File No", "Old Passport")
    const addrTerminators = /^(name of (father|mother|spouse)|spouse|father|mother|file\s*(no|number)|old passport|emergency|place of (birth|issue))/i;

    for (let i = 0; i < lines.length; i++) {
      if (/\baddress\b/i.test(lines[i])) {
        const addrLines = [];
        const firstLine = lines[i].replace(/^.*\baddress\b\s*[:.]?\s*/i, "").trim();
        if (firstLine.length > 2 && !addrTerminators.test(firstLine)) addrLines.push(firstLine);
        for (let j = i + 1; j < lines.length && j < i + 10; j++) {
          const l = lines[j].trim();
          if (addrTerminators.test(l)) break;
          if (l.length > 1) addrLines.push(l);
          if (/\b\d{6}\b/.test(l)) break; // pincode = end of address
        }
        if (addrLines.length > 0) {
          extractedAddress = addrLines.join(", ");
          break;
        }
      }
    }

    // Fallback: "Place of Birth" as partial address (front page)
    if (!extractedAddress) {
      for (let i = 0; i < lines.length; i++) {
        if (/place of birth/i.test(lines[i])) {
          const val = lines[i].replace(/^.*place of birth\s*[:.]?\s*/i, "").trim();
          if (val.length > 2) { extractedAddress = val; break; }
          if (i + 1 < lines.length && lines[i + 1].trim().length > 2 && !/^(date|DOI|sex|nationality)/i.test(lines[i + 1])) {
            extractedAddress = lines[i + 1].trim();
            break;
          }
        }
      }
    }

    // Last fallback: pincode-bearing line + preceding context
    if (!extractedAddress) {
      for (let i = 0; i < lines.length; i++) {
        if (/\b\d{6}\b/.test(lines[i]) && !/passport|file/i.test(lines[i])) {
          const addrLines = [];
          const startIdx = Math.max(0, i - 4);
          for (let j = startIdx; j <= i; j++) {
            const l = lines[j].trim();
            if (l.length > 2 && !/^(surname|given|date|DOB|nationality|sex|type|passport|name of)/i.test(l)) {
              addrLines.push(l);
            }
          }
          if (addrLines.length > 0) extractedAddress = addrLines.join(", ");
          break;
        }
      }
    }
  }

  if (!isValidDoc) {
    return { valid: false, error: "unrecognized_document", message: `Could not identify this as a valid ${documentType}.` };
  }

  // Fallback name extraction: look for any line that's all alphabetic 2+ words
  if (!extractedName) {
    for (const line of lines) {
      const trimmed = line.trim();
      if (/^[A-Za-z\s]+$/.test(trimmed) && trimmed.split(/\s+/).length >= 2 && trimmed.length > 4 && trimmed.length < 60) {
        // Skip known labels
        if (/GOVERNMENT|INDIA|INCOME|DEPARTMENT|UNIQUE|IDENTIFICATION|ELECTION|TRANSPORT|REPUBLIC|SURNAME|GIVEN NAME|NATIONALITY|DATE OF BIRTH|PLACE OF|SEX|MALE|FEMALE|TYPE|COUNTRY|PASSPORT/i.test(trimmed)) continue;
        extractedName = trimmed;
        break;
      }
    }
  }

  if (!extractedName) {
    return {
      valid: true,
      verified: false,
      error: "name_not_found",
      message: "Could not extract your name. Try uploading a clearer photo or a different ID type.",
      detectedType,
      extractedDocNumber,
    };
  }

  // Enforce at least two name parts (first + last)
  const nameParts = extractedName.trim().split(/\s+/).filter(p => p.length > 1);
  if (nameParts.length < 2) {
    return {
      valid: true,
      verified: false,
      error: "incomplete_name",
      extractedName: extractedName.trim(),
      message: `Only a partial name was extracted ("${extractedName.trim()}"). Please upload a clearer photo or try a different ID type.`,
      detectedType,
      extractedDocNumber,
    };
  }

  // Name comparison (fuzzy match)
  const normalize = (s) => s.toUpperCase().replace(/[^A-Z\s]/g, "").replace(/\s+/g, " ").trim();
  const opName = normalize(operatorName);
  const docName = normalize(extractedName);

  // Check exact match
  const exactMatch = opName === docName;

  // Check if one contains the other (partial match — last name might be missing etc)
  const containsMatch = opName.includes(docName) || docName.includes(opName);

  // Token-based similarity
  const opTokens = opName.split(" ").filter(t => t.length > 1);
  const docTokens = docName.split(" ").filter(t => t.length > 1);
  const commonTokens = opTokens.filter(t => docTokens.includes(t));
  const tokenSimilarity = commonTokens.length / Math.max(opTokens.length, docTokens.length);

  // Levenshtein for close misspellings
  function levenshtein(a, b) {
    const m = a.length, n = b.length;
    const dp = Array.from({ length: m + 1 }, () => Array(n + 1).fill(0));
    for (let i = 0; i <= m; i++) dp[i][0] = i;
    for (let j = 0; j <= n; j++) dp[0][j] = j;
    for (let i = 1; i <= m; i++) {
      for (let j = 1; j <= n; j++) {
        dp[i][j] = a[i-1] === b[j-1] ? dp[i-1][j-1] : 1 + Math.min(dp[i-1][j-1], dp[i-1][j], dp[i][j-1]);
      }
    }
    return dp[m][n];
  }
  const editDist = levenshtein(opName, docName);
  const maxLen = Math.max(opName.length, docName.length);
  const similarity = 1 - editDist / maxLen;

  // Decision: exact or high similarity = match, moderate = suggest, low = mismatch
  let nameMatch = "mismatch";
  if (exactMatch || containsMatch) {
    nameMatch = "exact";
  } else if (tokenSimilarity >= 0.5 || similarity >= 0.7) {
    nameMatch = "close";
  }

  // Check for duplicate name among other operators in the same company
  let duplicateWarning = null;
  if (extractedDocNumber && companyId) {
    try {
      const opsSnap = await db.collection(`companies/${companyId}/operators`)
        .where("idDocumentNumber", "==", extractedDocNumber)
        .limit(5)
        .get();
      const duplicates = opsSnap.docs.filter(d => d.id !== operatorId);
      if (duplicates.length > 0) {
        const dupNames = duplicates.map(d => d.data().name || "Unknown").join(", ");
        return {
          valid: false,
          error: "duplicate_id",
          message: `This document number is already linked to another operator: ${dupNames}. Each operator must have a unique ID document.`,
          extractedName: extractedName.trim(),
          extractedDocNumber,
          detectedType,
        };
      }
    } catch (e) {
      functions.logger.warn("Duplicate ID check failed:", e.message);
    }
  }

  // Also check if the extracted name (normalized) matches another operator's name exactly
  if (companyId && extractedName) {
    try {
      const nameNorm = extractedName.trim();
      const opsSnap = await db.collection(`companies/${companyId}/operators`)
        .where("name", "==", nameNorm)
        .limit(5)
        .get();
      const duplicates = opsSnap.docs.filter(d => d.id !== operatorId);
      if (duplicates.length > 0) {
        duplicateWarning = `Note: Another operator "${duplicates[0].data().name}" has the same name. Ensure this is the correct person.`;
      }
    } catch (_) {}
  }

  // Title case helper — normalize comma spacing, capitalize each word
  const toTitleCase = (s) => s
    ? s.replace(/,\s*/g, ", ").replace(/\s+/g, " ").trim()
        .replace(/\w\S*/g, w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
    : s;
  const titleName = toTitleCase(extractedName.trim());
  const titleAddress = extractedAddress ? toTitleCase(extractedAddress.trim()) : null;

  // Extract and crop face photo from ID for enrollment comparison
  let croppedFaceBase64 = null;
  const firstImageBuffer = Buffer.from(imageList[0], "base64");
  const firstImageIsPdf = firstImageBuffer.slice(0, 5).toString() === "%PDF-";
  if (imageList.length > 0 && !firstImageIsPdf) {
    try {
      // Step 1: Detect face bounding box in full ID document image
      const [faceResult] = await client.faceDetection({ image: { content: imageList[0] } });
      const idFaces = faceResult.faceAnnotations || [];
      functions.logger.info(`Face detection on ID: found ${idFaces.length} face(s)`);

      if (idFaces.length > 0) {
        const bestFace = idFaces[0];
        const vertices = bestFace.fdBoundingPoly?.vertices || bestFace.boundingPoly?.vertices || [];
        functions.logger.info(`Face bounding vertices: ${JSON.stringify(vertices)}`);

        if (vertices.length >= 4) {
          // Compute bounding rect from vertices
          const xs = vertices.map(v => v.x || 0);
          const ys = vertices.map(v => v.y || 0);
          let left = Math.max(0, Math.min(...xs));
          let top = Math.max(0, Math.min(...ys));
          let right = Math.max(...xs);
          let bottom = Math.max(...ys);

          // Add 20% padding around face for better landmark context
          const w = right - left;
          const h = bottom - top;
          const padX = Math.round(w * 0.20);
          const padY = Math.round(h * 0.20);
          left = Math.max(0, left - padX);
          top = Math.max(0, top - padY);
          right = right + padX;
          bottom = bottom + padY;

          // Step 2: Crop face region from full ID image using Jimp
          const idBuffer = Buffer.from(imageList[0], "base64");
          const image = await Jimp.read(idBuffer);
          const imgWidth = image.getWidth();
          const imgHeight = image.getHeight();
          functions.logger.info(`ID image size: ${imgWidth}x${imgHeight}, crop: left=${Math.round(left)} top=${Math.round(top)} w=${Math.round(right-left)} h=${Math.round(bottom-top)}`);

          const cropLeft = Math.max(0, Math.round(left));
          const cropTop = Math.max(0, Math.round(top));
          const cropWidth = Math.min(Math.round(right - left), imgWidth - cropLeft);
          const cropHeight = Math.min(Math.round(bottom - top), imgHeight - cropTop);

          if (cropWidth > 20 && cropHeight > 20) {
            const cropped = image.clone().crop(cropLeft, cropTop, cropWidth, cropHeight);
            const croppedBuffer = await cropped.quality(90).getBufferAsync(Jimp.MIME_JPEG);
            croppedFaceBase64 = croppedBuffer.toString("base64");
            functions.logger.info(`Cropped face: ${croppedFaceBase64.length} chars`);
          }
        }
      } else {
        // No face detected via faceDetection — try object localization as fallback
        functions.logger.info("No face found via faceDetection, trying objectLocalization...");
        const [objResult] = await client.objectLocalization({ image: { content: imageList[0] } });
        const persons = (objResult.localizedObjectAnnotations || []).filter(o => o.name === "Person" || o.name === "Face");
        if (persons.length > 0) {
          const person = persons[0];
          const normVerts = person.boundingPoly?.normalizedVertices || [];
          if (normVerts.length >= 4) {
            const idBuffer = Buffer.from(imageList[0], "base64");
            const image = await Jimp.read(idBuffer);
            const imgWidth = image.getWidth();
            const imgHeight = image.getHeight();

            const xs = normVerts.map(v => (v.x || 0) * imgWidth);
            const ys = normVerts.map(v => (v.y || 0) * imgHeight);
            const cropLeft = Math.max(0, Math.round(Math.min(...xs)));
            const cropTop = Math.max(0, Math.round(Math.min(...ys)));
            const cropWidth = Math.min(Math.round(Math.max(...xs) - Math.min(...xs)), imgWidth - cropLeft);
            const cropHeight = Math.min(Math.round(Math.max(...ys) - Math.min(...ys)), imgHeight - cropTop);

            if (cropWidth > 20 && cropHeight > 20) {
              const cropped = image.clone().crop(cropLeft, cropTop, cropWidth, cropHeight);
              const croppedBuffer = await cropped.quality(90).getBufferAsync(Jimp.MIME_JPEG);
              croppedFaceBase64 = croppedBuffer.toString("base64");
              functions.logger.info(`Cropped via objectLocalization: ${croppedFaceBase64.length} chars`);
            }
          }
        }
      }

      // Fallback: if no face/person detected, convert full image to JPEG as reference
      if (!croppedFaceBase64) {
        functions.logger.info("No face region found via any method — converting full ID image to JPEG as reference");
        try {
          const idBuffer = Buffer.from(imageList[0], "base64");
          const image = await Jimp.read(idBuffer);
          const jpegBuffer = await image.quality(85).getBufferAsync(Jimp.MIME_JPEG);
          croppedFaceBase64 = jpegBuffer.toString("base64");
          functions.logger.info(`Fallback JPEG: ${croppedFaceBase64.length} chars`);
        } catch (imgErr) {
          functions.logger.warn("Could not convert ID image to JPEG:", imgErr.message);
        }
      }

      // Step 3: Run face landmark detection on cropped face (higher accuracy)
      const faceImageForLandmarks = croppedFaceBase64;
      const [croppedFaceResult] = await client.faceDetection({ image: { content: faceImageForLandmarks } });
      const croppedFaces = croppedFaceResult.faceAnnotations || [];

      let idFaceLandmarks = null;
      if (croppedFaces.length > 0) {
        idFaceLandmarks = {};
        for (const lm of (croppedFaces[0].landmarks || [])) {
          idFaceLandmarks[lm.type] = { x: lm.position.x, y: lm.position.y, z: lm.position.z || 0 };
        }
      }

      // Step 4: Save to operator doc — full ID image + cropped face photo + landmarks
      if (companyId) {
        const opQuery = await db.collection(`companies/${companyId}/operators`)
          .where("name", "==", operatorName.trim())
          .limit(1).get();
        if (opQuery.docs.length > 0) {
          await opQuery.docs[0].ref.update({
            ...(idFaceLandmarks && { idFaceLandmarks }),
            idDocImages: imageList,
            ...(croppedFaceBase64 && { idCroppedFaceBase64: croppedFaceBase64 }),
          });
        }
      }
    } catch (e) {
      functions.logger.warn("Could not extract ID face for enrollment:", e.message);
    }
  }

  return {
    valid: true,
    verified: nameMatch !== "mismatch",
    nameMatch,
    extractedName: titleName,
    extractedDocNumber,
    extractedAddress: titleAddress,
    detectedType,
    operatorName,
    similarity: Math.round(similarity * 100),
    tokenSimilarity: Math.round(tokenSimilarity * 100),
    duplicateWarning,
    idCroppedFaceBase64: croppedFaceBase64 || null,
    message: nameMatch === "exact" ? "Name matches perfectly."
      : nameMatch === "close" ? `Name is similar: "${titleName}". You can update the operator name to match the ID.`
      : `Name on document "${titleName}" does not match operator name "${operatorName}".`,
  };
});

/**
 * sendPasswordResetOTP - Looks up user by email, sends OTP to both email and phone.
 * Returns masked phone number so the client knows where SMS was sent.
 */
exports.sendPasswordResetOTP = fns.https.onCall(async (data, context) => {
  const { email } = data;
  if (!email || !email.includes("@")) {
    throw new functions.https.HttpsError("invalid-argument", "Valid email required");
  }

  const normalizedEmail = email.trim().toLowerCase();

  await _enforceOtpCooldown(`pwreset_${normalizedEmail}`);

  // Look up operator by email (try collectionGroup, fallback to top-level companies)
  let phone = null;
  let userName = "User";
  let accountFound = false;

  try {
    const opSnap = await db.collectionGroup("operators")
      .where("email", "==", normalizedEmail)
      .limit(1)
      .get();

    if (!opSnap.empty) {
      const opData = opSnap.docs[0].data();
      phone = opData.phone || null;
      userName = opData.name || "Operator";
      accountFound = true;
    }
  } catch (e) {
    console.warn("collectionGroup operators query failed:", e.message);
  }

  // If not found as operator, check company-level email
  if (!accountFound) {
    try {
      const compSnap = await db.collection("companies")
        .where("email", "==", normalizedEmail)
        .limit(1)
        .get();
      if (!compSnap.empty) {
        const compData = compSnap.docs[0].data();
        phone = compData.phone || compData.contactPhone || null;
        userName = compData.contactName || compData.companyName || "Admin";
        accountFound = true;
      }
    } catch (e) {
      console.warn("companies email lookup failed:", e.message);
    }
  }

  // Constant, non-enumerating response — never reveal whether an account exists
  // (or whether it has a phone). Only do OTP work for a real account; otherwise
  // return the same shape so an attacker can't distinguish registered emails.
  const CONSTANT_RESPONSE = {
    success: true,
    emailSent: true,
    message: `If an account exists for ${normalizedEmail}, a reset code has been sent.`,
  };
  if (!accountFound) {
    return CONSTANT_RESPONSE;
  }

  // Generate OTP
  const otp = generateOTP();
  const expiresAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + OTP_EXPIRY_MS)
  );

  const crypto = require("crypto");
  const otpHash = crypto.createHash("sha256").update(otp).digest("hex");

  // Store OTP under password_reset prefix
  await db.collection("verification_otps").doc(`pwreset_${normalizedEmail}`).set({
    otpHash,
    expiresAt,
    attempts: 0,
    type: "password_reset",
    email: normalizedEmail,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Send OTP via email — image-only design (code in subject + image alt), HTML fallback.
  try {
    const heading = "Reset your password";
    const intro = `Hi ${userName}, use the code below to reset your ${BRAND.name} password.`;
    const securityNote = `If you didn't request a password reset, ignore this email — your password stays unchanged. ${BRAND.name} will never ask you to share this code.`;
    await _sendDesignedEmail(normalizedEmail, `${BRAND.name} password reset code: ${otp}`, "otp",
      { eyebrow: "Password reset", heading, intro, otp, securityNote, company: {} },
      { alt: `${BRAND.name} password reset code: ${otp} — expires in ${OTP_EXPIRY_MINUTES} minutes`,
        fallbackHtml: buildOtpEmail({ heading, intro, otp, securityNote }) });
  } catch (e) {
    console.warn("Password reset email send failed:", e.message);
  }

  // Send OTP via SMS if phone is available — but do NOT leak whether/where it
  // was sent in the response (that would re-enable phone-presence enumeration).
  if (phone) {
    const digits = phone.replace(/\D/g, "").slice(-10);
    if (digits.length === 10) {
      try {
        await _sendOtpSms(digits, otp);
      } catch (e) {
        console.warn("Password reset SMS send failed:", e.message);
      }
    }
  }

  return CONSTANT_RESPONSE;
});

/**
 * verifyPasswordResetOTP - Verifies OTP for password reset flow.
 * Returns a token that resetUserPassword accepts.
 */
/**
 * Mints a single-use, email-bound, short-lived password-reset token and stores
 * it server-side. resetUserPassword validates and consumes it. This replaces
 * the old static "otp_verified"/"000000" string, which let anyone reset any
 * account's password without proving they completed the OTP step.
 */
async function _mintPasswordResetToken(normalizedEmail) {
  const crypto = require("crypto");
  const token = crypto.randomBytes(32).toString("hex");
  const expiresAt = admin.firestore.Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000));
  await db.collection("password_reset_tokens").doc(token).set({
    email: normalizedEmail,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt,
  });
  return token;
}

exports.verifyPasswordResetOTP = fns.https.onCall(async (data, context) => {
  const { email, otp } = data;
  if (!email || !otp) {
    throw new functions.https.HttpsError("invalid-argument", "Email and OTP required");
  }

  const normalizedEmail = email.trim().toLowerCase();

  // Test bypass: 000000 is accepted as a valid OTP *code* (test flows). It still
  // mints a real one-time reset token — it is NOT a skeleton key for the reset.
  if (otp === "000000" && ALLOW_TEST_OTP) {
    const docRef = db.collection("verification_otps").doc(`pwreset_${normalizedEmail}`);
    const doc = await docRef.get();
    if (doc.exists) await docRef.delete();
    return { success: true, verified: true, verificationToken: await _mintPasswordResetToken(normalizedEmail) };
  }

  const docRef = db.collection("verification_otps").doc(`pwreset_${normalizedEmail}`);
  const doc = await docRef.get();

  if (!doc.exists) {
    throw new functions.https.HttpsError("not-found", "No OTP found. Request a new one.");
  }

  const otpData = doc.data();

  if (otpData.expiresAt.toDate() < new Date()) {
    await docRef.delete();
    throw new functions.https.HttpsError("deadline-exceeded", "OTP expired. Request a new one.");
  }

  if (otpData.attempts >= OTP_MAX_ATTEMPTS) {
    await docRef.delete();
    throw new functions.https.HttpsError("resource-exhausted", "Too many attempts. Request a new OTP.");
  }

  const crypto = require("crypto");
  const inputHash = crypto.createHash("sha256").update(otp).digest("hex");

  if (inputHash !== otpData.otpHash) {
    await docRef.update({ attempts: admin.firestore.FieldValue.increment(1) });
    throw new functions.https.HttpsError("permission-denied", "Invalid OTP");
  }

  await docRef.delete();
  return { success: true, verified: true, verificationToken: await _mintPasswordResetToken(normalizedEmail) };
});

/**
 * resetUserPassword - Resets a user's password after OTP has been verified.
 * Uses Admin SDK so no reauthentication is required on client.
 * Caller must have already verified OTP via verifyPasswordResetOTP.
 */
exports.resetUserPassword = fns.https.onCall(async (data, context) => {
  const { email, newPassword, verificationToken } = data;

  if (!newPassword) {
    throw new functions.https.HttpsError("invalid-argument", "New password required");
  }

  if (newPassword.length < 8) {
    throw new functions.https.HttpsError("invalid-argument", "Password must be at least 8 characters");
  }

  const normalizedEmail = email ? email.trim().toLowerCase() : "";

  // Identity proof: a single-use, email-bound reset token minted by
  // verifyPasswordResetOTP. No static string and no client-supplied UID is
  // trusted — this is what closes the unauthenticated account-takeover.
  if (!verificationToken) {
    throw new functions.https.HttpsError("permission-denied", "Identity not verified");
  }
  const tokenRef = db.collection("password_reset_tokens").doc(String(verificationToken));
  const tokenSnap = await tokenRef.get();
  if (!tokenSnap.exists) {
    throw new functions.https.HttpsError("permission-denied", "Invalid or expired reset token. Start over.");
  }
  const tokenData = tokenSnap.data();
  if (!tokenData.expiresAt || tokenData.expiresAt.toDate() < new Date()) {
    await tokenRef.delete();
    throw new functions.https.HttpsError("deadline-exceeded", "Reset token expired. Start over.");
  }
  if (!normalizedEmail || (tokenData.email || "").trim().toLowerCase() !== normalizedEmail) {
    throw new functions.https.HttpsError("permission-denied", "Reset token does not match this account.");
  }
  // Single-use: consume immediately so the token can't be replayed.
  await tokenRef.delete();

  // Resolve UID strictly from the verified email (or a real authenticated
  // session) — never from a client-supplied UID.
  let uid;

  if (context.auth && context.auth.uid && context.auth.token && context.auth.token.email) {
    uid = context.auth.uid;
  } else if (normalizedEmail.length > 0) {
    try {
      const userRecord = await admin.auth().getUserByEmail(normalizedEmail);
      uid = userRecord.uid;
    } catch (err) {
      // User doesn't exist in Firebase Auth — create them so password can be set
      try {
        const newUser = await admin.auth().createUser({
          email: normalizedEmail,
          password: newPassword,
          emailVerified: true,
        });
        uid = newUser.uid;

        // Store the salted credential; strip any legacy hash from the doc.
        await _writeCredential(normalizedEmail, newPassword);
        const opSnap = await db.collectionGroup("operators")
          .where("email", "==", normalizedEmail)
          .limit(1)
          .get();
        if (!opSnap.empty) {
          await opSnap.docs[0].ref.update({ uid: newUser.uid, passwordHash: admin.firestore.FieldValue.delete(), passwordLastChanged: admin.firestore.FieldValue.serverTimestamp(), mustChangePassword: false });
        }

        await _notifyPasswordChanged(normalizedEmail);
        return { success: true, message: "Account created and password set", created: true };
      } catch (createErr) {
        throw new functions.https.HttpsError("internal",
          "Failed to create auth account: " + (createErr.message || createErr));
      }
    }
  } else {
    throw new functions.https.HttpsError("invalid-argument",
      "No user identifier provided");
  }

  try {
    // Best-effort Firebase Auth update (works where a real Auth user exists).
    try {
      await admin.auth().updateUser(uid, { password: newPassword });
    } catch (_) {}

    // Store the salted credential server-side; strip any legacy doc hash.
    if (normalizedEmail.length > 0) {
      await _writeCredential(normalizedEmail, newPassword);
      const opSnap = await db.collectionGroup("operators")
        .where("email", "==", normalizedEmail)
        .limit(1)
        .get();

      if (!opSnap.empty) {
        await opSnap.docs[0].ref.update({
          passwordHash: admin.firestore.FieldValue.delete(),
          passwordLastChanged: admin.firestore.FieldValue.serverTimestamp(),
          mustChangePassword: false,
        });
      }
      const coSnap = await db.collection("companies")
        .where("email", "==", normalizedEmail)
        .limit(1)
        .get();
      if (!coSnap.empty) {
        await coSnap.docs[0].ref.update({
          passwordHash: admin.firestore.FieldValue.delete(),
          passwordLastChanged: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    await _notifyPasswordChanged(normalizedEmail);
    return { success: true, message: "Password updated successfully" };
  } catch (err) {
    throw new functions.https.HttpsError("internal", err.message || "Failed to reset password");
  }
});

// ─── Client-triggered notifications (auth-gated callables) ───────────────────
// For events that happen on the client (Firebase Auth password change / MFA,
// local cloud-backup outcome) where there is no server-side trigger to hook.

exports.notifyPasswordChanged = fns.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  const email = (context.auth.token.email || (data && data.email) || "").toLowerCase();
  await _notifyPasswordChanged(email);
  return { success: true };
});

// Email + SMS + in-app notice that 2FA was turned on/off. Called server-side from
// mfaConfirmEnroll / mfaDisable (the client no longer fires this directly).
async function _notifyMfaChanged(email, enabled) {
  const addr = (email || "").toLowerCase();
  if (!addr) return;
  const state = enabled ? "enabled" : "disabled";
  let phone = null, name = "there", companyId = null;
  try {
    const opSnap = await db.collectionGroup("operators").where("email", "==", addr).limit(1).get();
    if (!opSnap.empty) { const op = opSnap.docs[0].data() || {}; phone = op.phone || null; name = op.name || name; companyId = opSnap.docs[0].ref.parent.parent?.id || null; }
  } catch (e) { console.warn("mfa notify lookup failed:", e.message); }
  await notifyContact({
    to: { email: addr, phone, name },
    companyId,
    critical: true,
    subject: `${BRAND.name}: two-factor authentication ${state}`,
    notif: ({
      category: "account",
      link: "/settings/mfa",
      operatorEmail: addr,
      accent: enabled ? undefined : "danger",
      heading: `2FA ${state}`,
      intro: `Two-factor authentication was just ${state} on your ${BRAND.name} account.`,
      note: enabled
        ? `If this wasn't you, contact ${BRAND.support} immediately.`
        : `If you did NOT disable 2FA, contact ${BRAND.support} immediately — your account may be at risk.`,
    }),
  });
}

exports.notifyMfaChanged = fns.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  const email = (context.auth.token.email || "").toLowerCase();
  if (!email) return { success: false };
  await _notifyMfaChanged(email, !!(data && data.enabled));
  return { success: true };
});

exports.notifyBackupResult = fns.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  if (data && data.success) return { success: true }; // only alert on failure
  const companyId = data && data.companyId ? String(data.companyId) : null;
  const reason = data && data.reason ? String(data.reason).slice(0, 120) : "Unknown error";
  await notifyContact({
    companyId,
    to: companyId ? undefined : { email: context.auth.token.email || null },
    subject: `${BRAND.name}: cloud backup failed`,
    notif: ({
      category: "backup",
      link: "/settings/backup",
      accent: "warn",
      heading: "Cloud backup failed",
      intro: `A scheduled ${BRAND.name} cloud backup did not complete. Your data is safe locally, but the off-site copy was not updated.`,
      rows: [["Status", "Failed"], ["Reason", reason]],
      note: `Open Settings → Integrations to check your backup configuration, or contact ${BRAND.support}.`,
    }),
  });
  return { success: true };
});

// ─── Per-operator FCM token registration (macOS clients) ─────────────────────
// The client (macOS only) obtains an FCM token and registers it here; we store
// it on the caller's operator doc so security alerts can target their devices.

exports.registerFcmToken = fns.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  const token = data && data.token ? String(data.token) : "";
  const email = (context.auth.token.email || "").toLowerCase();
  if (!token || !email) return { success: false };
  try {
    const opSnap = await db.collectionGroup("operators").where("email", "==", email).limit(1).get();
    if (!opSnap.empty) {
      await opSnap.docs[0].ref.update({ fcmTokens: admin.firestore.FieldValue.arrayUnion(token) });
    }
  } catch (e) {
    console.warn("registerFcmToken failed:", e.message);
    return { success: false };
  }
  return { success: true };
});

exports.unregisterFcmToken = fns.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  const token = data && data.token ? String(data.token) : "";
  const email = (context.auth.token.email || "").toLowerCase();
  if (!token || !email) return { success: false };
  try {
    const opSnap = await db.collectionGroup("operators").where("email", "==", email).limit(1).get();
    if (!opSnap.empty) {
      await opSnap.docs[0].ref.update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(token) });
    }
  } catch (e) {
    console.warn("unregisterFcmToken failed:", e.message);
    return { success: false };
  }
  return { success: true };
});

/**
 * updateOperatorEmail - Admin updates an operator's Firebase Auth email.
 * Requires admin context (caller must be authenticated).
 */
exports.updateOperatorEmail = fns.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required");
  }

  const { uid, newEmail } = data;
  if (!uid || !newEmail || !newEmail.includes("@")) {
    throw new functions.https.HttpsError("invalid-argument", "Valid uid and newEmail required");
  }
  // Authorize: an admin may change the sign-in email only for an operator in
  // their OWN company (resolve company from the uid). Closes the IDOR takeover.
  {
    const _es = await _requireAdminSession(data);
    const _opS = await db.collectionGroup("operators").where("uid", "==", uid).limit(1).get();
    if (_opS.empty) throw new functions.https.HttpsError("not-found", "Operator not found.");
    const _opCo = _opS.docs[0].ref.parent.parent ? _opS.docs[0].ref.parent.parent.id : (_opS.docs[0].data().companyId || null);
    if (_opCo !== _es.companyId) {
      throw new functions.https.HttpsError("permission-denied", "Not authorized for this operator.");
    }
  }

  try {
    const newAddr = newEmail.trim().toLowerCase();
    let oldEmail = null;
    try { const u = await admin.auth().getUser(uid); oldEmail = (u.email || "").toLowerCase() || null; } catch (_) { /* best-effort */ }
    await admin.auth().updateUser(uid, { email: newAddr });

    // Security notice to BOTH addresses (mirrors updateCompanyContact). Auth
    // email changes were silent before — a takeover vector.
    try {
      let companyId = null, name = "there";
      const opSnap = await db.collectionGroup("operators").where("uid", "==", uid).limit(1).get();
      if (!opSnap.empty) { const op = opSnap.docs[0].data() || {}; name = op.name || name; companyId = opSnap.docs[0].ref.parent.parent?.id || null; }
      // One in-app entry, targeted to the operator's current identity (old email).
      if (companyId) {
        await _writeInApp({
          companyId, operatorEmail: oldEmail || newAddr, category: "account", severity: "critical", link: "/profile",
          title: "Sign-in email changed",
          body: `The email used to sign in to your ${BRAND.name} account was changed to ${newAddr}. If this wasn't you, contact your administrator immediately.`,
        });
      }
      // Email alert to both old and new (skipInApp avoids a duplicate in-app entry).
      const targets = [newAddr, oldEmail].filter((e, i, a) => e && a.indexOf(e) === i);
      for (const target of targets) {
        await notifyContact({
          to: { email: target, name }, companyId, critical: true, skipInApp: true,
          subject: `${BRAND.name}: your sign-in email was changed`,
          notif: ({
            category: "account", link: "/profile", accent: "danger",
            heading: "Sign-in email changed",
            intro: `The email used to sign in to your ${BRAND.name} account was changed to ${newAddr}.`,
            note: "If you did NOT make this change, contact your administrator immediately — your account may be at risk.",
          }),
        });
      }
    } catch (e) { console.warn("operator-email-change notice failed:", e.message); }
    return { success: true };
  } catch (err) {
    console.warn("updateOperatorEmail failed:", err.message);
    return { success: false, error: err.message };
  }
});

// ─── Face Enrollment ────────────────────────────────────────────────────────
// Receives webcam face snapshots, detects faces, and stores face landmark
// embeddings for future operator verification during login.

exports.validateFaceConsistency = fns.runWith({ timeoutSeconds: 120, memory: "512MB" }).https.onCall(async (data) => {
  const { images, referenceImages } = data;

  if (!images || !images.length) {
    throw new functions.https.HttpsError("invalid-argument", "At least one face image required");
  }

  let Jimp, client;
  try {
    Jimp = require("jimp");
    client = new vision.ImageAnnotatorClient();
  } catch (initErr) {
    functions.logger.error("validateFaceConsistency init error:", initErr);
    throw new functions.https.HttpsError("internal", `Initialization failed: ${initErr.message}`);
  }

  try {
  // Step 1: Detect faces, extract landmarks + pose, and crop to normalized grayscale
  const CROP_SIZE = 64;
  const faceCrops = []; // { pixels, confidence }
  const facePoses = []; // { roll, pan, tilt }
  const faceLandmarks = []; // { noseTip, leftEye, rightEye, leftEarTop, rightEarTop }
  const eyeAspectRatios = []; // EAR per frame

  const getLandmarkPos = (landmarks, type) => {
    const lm = landmarks.find(l => l.type === type);
    return lm ? { x: lm.position.x || 0, y: lm.position.y || 0 } : null;
  };

  const computeEAR = (landmarks) => {
    const leftTop = getLandmarkPos(landmarks, "LEFT_EYE_TOP_BOUNDARY");
    const leftBottom = getLandmarkPos(landmarks, "LEFT_EYE_BOTTOM_BOUNDARY");
    const leftLeft = getLandmarkPos(landmarks, "LEFT_EYE_LEFT_CORNER");
    const leftRight = getLandmarkPos(landmarks, "LEFT_EYE_RIGHT_CORNER");
    const rightTop = getLandmarkPos(landmarks, "RIGHT_EYE_TOP_BOUNDARY");
    const rightBottom = getLandmarkPos(landmarks, "RIGHT_EYE_BOTTOM_BOUNDARY");
    const rightLeft = getLandmarkPos(landmarks, "RIGHT_EYE_LEFT_CORNER");
    const rightRight = getLandmarkPos(landmarks, "RIGHT_EYE_RIGHT_CORNER");

    if (!leftTop || !leftBottom || !leftLeft || !leftRight || !rightTop || !rightBottom || !rightLeft || !rightRight) return null;

    const dist = (a, b) => Math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2);
    const leftEAR = dist(leftTop, leftBottom) / (dist(leftLeft, leftRight) || 1);
    const rightEAR = dist(rightTop, rightBottom) / (dist(rightLeft, rightRight) || 1);
    return (leftEAR + rightEAR) / 2;
  };

  for (const img of images) {
    try {
      const [result] = await client.faceDetection({ image: { content: img } });
      const faces = result.faceAnnotations || [];
      if (faces.length === 0) continue;

      const bestFace = faces.reduce((a, b) =>
        (a.detectionConfidence || 0) > (b.detectionConfidence || 0) ? a : b
      );
      if ((bestFace.detectionConfidence || 0) < 0.7) continue;

      // Extract head pose angles
      facePoses.push({
        roll: bestFace.rollAngle || 0,
        pan: bestFace.panAngle || 0,
        tilt: bestFace.tiltAngle || 0,
      });

      // Extract key landmarks for micro-motion analysis
      const landmarks = bestFace.landmarks || [];
      const noseTip = getLandmarkPos(landmarks, "NOSE_TIP");
      const leftEye = getLandmarkPos(landmarks, "LEFT_EYE");
      const rightEye = getLandmarkPos(landmarks, "RIGHT_EYE");
      if (noseTip && leftEye && rightEye) {
        faceLandmarks.push({ noseTip, leftEye, rightEye });
      }

      // Compute EAR
      const ear = computeEAR(landmarks);
      if (ear !== null) eyeAspectRatios.push(ear);

      // Get bounding box for face crop
      const vertices = bestFace.boundingPoly?.vertices || bestFace.fdBoundingPoly?.vertices;
      if (!vertices || vertices.length < 4) continue;

      const xs = vertices.map(v => v.x || 0);
      const ys = vertices.map(v => v.y || 0);
      let x = Math.max(0, Math.min(...xs));
      let y = Math.max(0, Math.min(...ys));
      let w = Math.max(...xs) - x;
      let h = Math.max(...ys) - y;
      if (w < 20 || h < 20) continue;

      const imgBuf = Buffer.from(img, "base64");
      const jimpImg = await Jimp.read(imgBuf);

      x = Math.min(x, jimpImg.bitmap.width - 1);
      y = Math.min(y, jimpImg.bitmap.height - 1);
      w = Math.min(w, jimpImg.bitmap.width - x);
      h = Math.min(h, jimpImg.bitmap.height - y);

      const cropped = jimpImg.crop(x, y, w, h).resize(CROP_SIZE, CROP_SIZE).greyscale();

      const pixels = new Float64Array(CROP_SIZE * CROP_SIZE);
      for (let py = 0; py < CROP_SIZE; py++) {
        for (let px = 0; px < CROP_SIZE; px++) {
          const rgba = Jimp.intToRGBA(cropped.getPixelColor(px, py));
          pixels[py * CROP_SIZE + px] = rgba.r / 255.0;
        }
      }

      faceCrops.push({ pixels, confidence: bestFace.detectionConfidence });
    } catch (e) {
      functions.logger.warn("Face crop failed for frame:", e.message);
    }
  }

  functions.logger.info(`Face consistency: ${faceCrops.length} valid crops from ${images.length} images`);

  if (faceCrops.length < 4) {
    return {
      success: false,
      facesDetected: faceCrops.length,
      message: `Only ${faceCrops.length} valid face(s) detected. Need at least 4 clear shots. Ensure good lighting and face the camera directly.`,
    };
  }

  // Step 2: Liveness detection — head pose variance, landmark micro-motion, EAR variance
  const variance = (arr) => {
    if (arr.length < 2) return 0;
    const mean = arr.reduce((s, v) => s + v, 0) / arr.length;
    return arr.reduce((s, v) => s + (v - mean) ** 2, 0) / arr.length;
  };

  let livenessPass = true;
  let livenessReason = "";
  const livenessMetrics = {};

  // Check 1: Head pose variance — real faces have natural micro-tilts
  if (facePoses.length >= 4) {
    const rollVar = variance(facePoses.map(p => p.roll));
    const panVar = variance(facePoses.map(p => p.pan));
    const tiltVar = variance(facePoses.map(p => p.tilt));
    const totalPoseVar = rollVar + panVar + tiltVar;
    livenessMetrics.poseVariance = parseFloat(totalPoseVar.toFixed(4));
    livenessMetrics.rollVar = parseFloat(rollVar.toFixed(4));
    livenessMetrics.panVar = parseFloat(panVar.toFixed(4));
    livenessMetrics.tiltVar = parseFloat(tiltVar.toFixed(4));

    // A static photo will have near-zero pose variance (< 0.5 degrees² combined)
    // Real faces naturally vary by 1-5+ degrees across captures
    if (totalPoseVar < 0.15) {
      livenessPass = false;
      livenessReason = "No natural head movement detected between captures. Please face the camera naturally — small movements are expected.";
    }
  }

  // Check 2: Landmark micro-motion — real faces shift position slightly between frames
  if (livenessPass && faceLandmarks.length >= 4) {
    // Normalize landmarks relative to inter-eye distance to be scale-invariant
    const normalizedPositions = faceLandmarks.map(lm => {
      const eyeDist = Math.sqrt((lm.leftEye.x - lm.rightEye.x) ** 2 + (lm.leftEye.y - lm.rightEye.y) ** 2) || 1;
      return {
        noseX: lm.noseTip.x / eyeDist,
        noseY: lm.noseTip.y / eyeDist,
        leftX: lm.leftEye.x / eyeDist,
        leftY: lm.leftEye.y / eyeDist,
      };
    });

    const noseXVar = variance(normalizedPositions.map(p => p.noseX));
    const noseYVar = variance(normalizedPositions.map(p => p.noseY));
    const landmarkVar = noseXVar + noseYVar;
    livenessMetrics.landmarkVariance = parseFloat(landmarkVar.toFixed(6));

    // A held-up photo has near-zero normalized landmark variance
    // Real faces: nose position relative to eyes shifts due to micro head tilts
    if (landmarkVar < 0.0001) {
      livenessPass = false;
      livenessReason = "Face appears static across all captures. Please ensure you are present in person — photos are not accepted.";
    }
  }

  // Check 3: Eye Aspect Ratio variance — natural blinking causes variation
  if (livenessPass && eyeAspectRatios.length >= 4) {
    const earVar = variance(eyeAspectRatios);
    const earMean = eyeAspectRatios.reduce((s, v) => s + v, 0) / eyeAspectRatios.length;
    livenessMetrics.earVariance = parseFloat(earVar.toFixed(6));
    livenessMetrics.earMean = parseFloat(earMean.toFixed(4));

    // Real eyes have micro-fluctuation in openness (natural partial blinks)
    // A photo has perfectly uniform eye openness (variance < 0.0001)
    if (earVar < 0.00005) {
      livenessPass = false;
      livenessReason = "No natural eye movement detected. Please blink naturally between captures — holding eyes open rigidly or using a photo will be rejected.";
    }
  }

  functions.logger.info(`Liveness: pass=${livenessPass}, metrics=${JSON.stringify(livenessMetrics)}`);

  if (!livenessPass) {
    return {
      success: false,
      facesDetected: faceCrops.length,
      liveness: false,
      livenessMetrics,
      message: livenessReason,
    };
  }

  // Step 3: Identity consistency — NCC pixel comparison (same person check)
  const SIMILARITY_THRESHOLD = 0.45;

  const computeNCC = (a, b) => {
    const n = a.length;
    let sumA = 0, sumB = 0;
    for (let i = 0; i < n; i++) { sumA += a[i]; sumB += b[i]; }
    const meanA = sumA / n, meanB = sumB / n;
    let num = 0, denA = 0, denB = 0;
    for (let i = 0; i < n; i++) {
      const da = a[i] - meanA, db = b[i] - meanB;
      num += da * db;
      denA += da * da;
      denB += db * db;
    }
    const den = Math.sqrt(denA * denB);
    return den === 0 ? 0 : num / den;
  };

  const outlierCounts = faceCrops.map((_, i) => {
    let failures = 0;
    for (let j = 0; j < faceCrops.length; j++) {
      if (i === j) continue;
      const ncc = computeNCC(faceCrops[i].pixels, faceCrops[j].pixels);
      if (ncc < SIMILARITY_THRESHOLD) failures++;
    }
    return failures;
  });

  const halfGroup = Math.floor(faceCrops.length / 2);
  const outliers = outlierCounts.filter(c => c >= halfGroup).length;

  let totalNCC = 0, pairCount = 0;
  for (let i = 0; i < faceCrops.length; i++) {
    for (let j = i + 1; j < faceCrops.length; j++) {
      totalNCC += computeNCC(faceCrops[i].pixels, faceCrops[j].pixels);
      pairCount++;
    }
  }
  const avgNCC = pairCount > 0 ? totalNCC / pairCount : 0;
  const avgConfidence = faceCrops.reduce((s, f) => s + f.confidence, 0) / faceCrops.length;

  functions.logger.info(`Face NCC: avg=${avgNCC.toFixed(3)}, outliers=${outliers}/${faceCrops.length}, counts=[${outlierCounts.join(",")}]`);

  if (outliers > 1) {
    return {
      success: false,
      facesDetected: faceCrops.length,
      avgConfidence: parseFloat(avgConfidence.toFixed(3)),
      avgSimilarity: parseFloat(avgNCC.toFixed(3)),
      outliers,
      liveness: true,
      livenessMetrics,
      message: "Multiple different faces detected. Please ensure only one person is in front of the camera and retake.",
    };
  }

  // Step 4: Cross-phase identity check (specs vs no-specs must be same person)
  if (referenceImages && referenceImages.length > 0) {
    const refCrops = [];
    for (const img of referenceImages) {
      try {
        const [result] = await client.faceDetection({ image: { content: img } });
        const faces = result.faceAnnotations || [];
        if (faces.length === 0) continue;
        const bestFace = faces.reduce((a, b) =>
          (a.detectionConfidence || 0) > (b.detectionConfidence || 0) ? a : b
        );
        if ((bestFace.detectionConfidence || 0) < 0.7) continue;
        const vertices = bestFace.boundingPoly?.vertices || bestFace.fdBoundingPoly?.vertices;
        if (!vertices || vertices.length < 4) continue;
        const xs = vertices.map(v => v.x || 0);
        const ys = vertices.map(v => v.y || 0);
        let x = Math.max(0, Math.min(...xs));
        let y = Math.max(0, Math.min(...ys));
        let w = Math.max(...xs) - x;
        let h = Math.max(...ys) - y;
        if (w < 20 || h < 20) continue;
        const imgBuf = Buffer.from(img, "base64");
        const jimpImg = await Jimp.read(imgBuf);
        x = Math.min(x, jimpImg.bitmap.width - 1);
        y = Math.min(y, jimpImg.bitmap.height - 1);
        w = Math.min(w, jimpImg.bitmap.width - x);
        h = Math.min(h, jimpImg.bitmap.height - y);
        const cropped = jimpImg.crop(x, y, w, h).resize(CROP_SIZE, CROP_SIZE).greyscale();
        const pixels = new Float64Array(CROP_SIZE * CROP_SIZE);
        for (let py = 0; py < CROP_SIZE; py++) {
          for (let px = 0; px < CROP_SIZE; px++) {
            const rgba = Jimp.intToRGBA(cropped.getPixelColor(px, py));
            pixels[py * CROP_SIZE + px] = rgba.r / 255.0;
          }
        }
        refCrops.push(pixels);
      } catch (e) {
        functions.logger.warn("Cross-phase ref crop failed:", e.message);
      }
    }

    if (refCrops.length >= 2) {
      // Compare each current crop against reference crops (lower threshold due to glasses difference)
      const CROSS_PHASE_THRESHOLD = 0.30;
      let crossMatches = 0;
      for (const crop of faceCrops) {
        let maxNcc = -1;
        for (const ref of refCrops) {
          const ncc = computeNCC(crop.pixels, ref);
          if (ncc > maxNcc) maxNcc = ncc;
        }
        if (maxNcc >= CROSS_PHASE_THRESHOLD) crossMatches++;
      }

      const crossMatchRatio = crossMatches / faceCrops.length;
      functions.logger.info(`Cross-phase check: ${crossMatches}/${faceCrops.length} matched (ratio=${crossMatchRatio.toFixed(2)}, threshold=${CROSS_PHASE_THRESHOLD})`);

      if (crossMatchRatio < 0.5) {
        return {
          success: false,
          facesDetected: faceCrops.length,
          avgConfidence: parseFloat(avgConfidence.toFixed(3)),
          avgSimilarity: parseFloat(avgNCC.toFixed(3)),
          outliers,
          liveness: true,
          livenessMetrics,
          crossPhaseMatch: false,
          message: "Face in this phase doesn't match the previous phase. The same person must complete both phases.",
        };
      }
    }
  }

  return {
    success: true,
    facesDetected: faceCrops.length,
    avgConfidence: parseFloat(avgConfidence.toFixed(3)),
    avgSimilarity: parseFloat(avgNCC.toFixed(3)),
    outliers,
    liveness: true,
    livenessMetrics,
  };
} catch (err) {
  functions.logger.error("validateFaceConsistency unhandled error:", err);
  if (err instanceof functions.https.HttpsError) throw err;
  throw new functions.https.HttpsError("internal", `Face validation error: ${err.message || err}`);
}
});

exports.enrollOperatorFace = fns.runWith({ timeoutSeconds: 120, memory: "512MB" }).https.onCall(async (data) => {
  const { images, companyId, operatorEmail } = data;

  if (!images || !images.length) {
    throw new functions.https.HttpsError("invalid-argument", "At least one face image required");
  }
  if (!companyId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId required");
  }

  const client = new vision.ImageAnnotatorClient();

  // Detect faces in all provided snapshots — the per-frame Vision round-trip was
  // the dominant latency (one sequential call per image). Run them in parallel,
  // then build results in capture order, keeping each frame's original index.
  const detections = await Promise.all(images.map((img) =>
    client.faceDetection({ image: { content: img } })
      .then(([result]) => result)
      .catch((e) => { functions.logger.warn("Face detection failed for frame:", e.message); return null; })
  ));

  const faceResults = [];
  for (let imgIdx = 0; imgIdx < detections.length; imgIdx++) {
    const result = detections[imgIdx];
    if (!result) continue;
    const faces = result.faceAnnotations || [];
    if (faces.length === 0) continue;

    const bestFace = faces.reduce((a, b) =>
      (a.detectionConfidence || 0) > (b.detectionConfidence || 0) ? a : b
    );

    if ((bestFace.detectionConfidence || 0) < 0.7) continue;

    const landmarks = {};
    for (const lm of (bestFace.landmarks || [])) {
      landmarks[lm.type] = {
        x: lm.position.x,
        y: lm.position.y,
        z: lm.position.z || 0,
      };
    }

    faceResults.push({
      imageIndex: imgIdx,
      confidence: bestFace.detectionConfidence,
      landmarks,
      rollAngle: bestFace.rollAngle || 0,
      panAngle: bestFace.panAngle || 0,
      tiltAngle: bestFace.tiltAngle || 0,
    });
  }

  functions.logger.info(`Face enrollment: ${faceResults.length} valid faces from ${images.length} images`);

  if (faceResults.length < 4) {
    return {
      success: false,
      facesDetected: faceResults.length,
      message: `Only ${faceResults.length} valid face(s) detected. Need at least 4 clear shots. Ensure good lighting and face the camera directly.`,
    };
  }

  // Face consistency validation: identify outliers (faces that don't match the majority)
  const CONSISTENCY_THRESHOLD = 0.75;
  // For each face, count how many others it fails to match
  const outlierCounts = faceResults.map((_, i) => {
    let failures = 0;
    for (let j = 0; j < faceResults.length; j++) {
      if (i === j) continue;
      const sim = computeLandmarkSimilarity(faceResults[i].landmarks, faceResults[j].landmarks);
      if (sim < CONSISTENCY_THRESHOLD) failures++;
    }
    return failures;
  });

  // A face is an outlier if it fails to match more than half the group
  const halfGroup = Math.floor(faceResults.length / 2);
  const outliers = outlierCounts.filter(c => c >= halfGroup).length;

  functions.logger.info(`Face consistency: outliers=${outliers}/${faceResults.length}, outlierCounts=[${outlierCounts.join(",")}]`);

  if (outliers > 1) {
    return {
      success: false,
      facesDetected: faceResults.length,
      outliers,
      message: "Multiple different faces detected in your snapshots. Please ensure only one person is in front of the camera and retake.",
    };
  }

  // Identify non-outlier frame indices
  const validIndices = [];
  for (let i = 0; i < faceResults.length; i++) {
    if (outlierCounts[i] < halfGroup) validIndices.push(i);
  }

  // Resolve the operator's canonical id up-front so reference frames are keyed
  // by operatorId — matching storeFaceFrames/getFaceFrames and the
  // onOperatorDeleted / onCompanyDeleted cleanup. Falls back to the email only
  // when no operator doc exists yet (in which case faceEnrollment isn't saved
  // anyway, so behaviour is unchanged).
  let flatRef = null, companyRef = null, operatorId = null;
  try {
    const flatSnap = await db.collection("operators")
      .where("companyId", "==", companyId)
      .where("email", "==", operatorEmail)
      .limit(1).get();
    if (flatSnap.docs.length > 0) { flatRef = flatSnap.docs[0].ref; }
    const companySnap = await db.collection(`companies/${companyId}/operators`)
      .where("email", "==", operatorEmail)
      .limit(1).get();
    if (companySnap.docs.length > 0) { companyRef = companySnap.docs[0].ref; operatorId = companySnap.docs[0].id; }
  } catch (e) {
    functions.logger.warn("operator lookup for face key failed:", e.message);
  }
  // Key by the COMPANY-scoped operatorId (matches getFaceFrames + the
  // onOperatorDeleted cleanup prefix); the flat operators id differs and must
  // not be used. Fall back to email only when no company operator doc exists.
  const storageKey = operatorId || operatorEmail;

  // Upload non-outlier frames to Cloud Storage, keyed by operatorId.
  const storagePaths = [];
  try {
    const uploadPromises = validIndices.map(async (faceIdx, storageIdx) => {
      // faceIdx indexes faceResults (a filtered list); map back to the original
      // image via the stored imageIndex so a skipped frame can't misalign uploads.
      const imgBase64 = images[faceResults[faceIdx].imageIndex];
      const imgBuffer = Buffer.from(imgBase64, "base64");
      const path = `face-enrollment/${companyId}/${storageKey}/${storageIdx}.jpg`;
      const file = bucket.file(path);
      await file.save(imgBuffer, { contentType: "image/jpeg", metadata: { cacheControl: "private,max-age=31536000" } });
      storagePaths.push(path);
    });
    await Promise.all(uploadPromises);
    functions.logger.info(`Face enrollment: uploaded ${storagePaths.length} reference frames to Storage`);
  } catch (e) {
    functions.logger.warn("Failed to upload face frames to Storage:", e.message);
    // The enrollment record is still written below, but without reference frames
    // face sign-in won't work — alert the admin to re-enroll.
    if (companyId) {
      await _writeInApp({
        companyId, category: "operator", severity: "warn", link: "/operators",
        title: "Face enrollment incomplete",
        body: `Reference photos for ${operatorEmail || "an operator"} couldn't be saved, so face sign-in may not work. Re-run the enrollment.`,
      }).catch((err) => console.warn("face-enroll alert failed:", err.message));
    }
  }

  // Store face enrollment data
  const enrollmentData = {
    enrolledAt: admin.firestore.FieldValue.serverTimestamp(),
    faceCount: faceResults.length,
    validFrameCount: validIndices.length,
    averageConfidence: faceResults.reduce((s, f) => s + f.confidence, 0) / faceResults.length,
    faceLandmarks: averageLandmarks(faceResults.map(f => f.landmarks)),
    referenceFrames: storagePaths,
    enrolled: true,
  };

  // Save to operator document (refs resolved above for the storage key).
  try {
    if (flatRef) await flatRef.update({ faceEnrollment: enrollmentData });
    if (companyRef) await companyRef.update({ faceEnrollment: enrollmentData });
  } catch (e) {
    functions.logger.warn("Could not save face enrollment:", e.message);
    return {
      success: false,
      facesDetected: faceResults.length,
      message: "Failed to save enrollment data. Previous enrollment preserved.",
    };
  }

  // Delete previously stored face frames only after successful enrollment
  try {
    const [existingFiles] = await bucket.getFiles({ prefix: `face-enrollment/${companyId}/${storageKey}/` });
    const oldFiles = existingFiles.filter(f => !storagePaths.includes(f.name));
    if (oldFiles.length > 0) {
      await Promise.all(oldFiles.map(f => f.delete()));
      functions.logger.info(`Face enrollment: deleted ${oldFiles.length} previous frames`);
    }
  } catch (e) {
    functions.logger.warn("Failed to delete previous face frames:", e.message);
  }

  return {
    success: true,
    facesDetected: faceResults.length,
    validFrames: validIndices.length,
    message: "Face enrolled successfully.",
  };
});

// trainOperatorFace - Adds training frames to existing face enrollment with relaxed tolerance.
// Validates new frames against existing reference frames to ensure same person,
// then appends valid new frames to storage.
exports.trainOperatorFace = fns.runWith({ timeoutSeconds: 120, memory: "512MB" }).https.onCall(async (data) => {
  const { images, companyId, operatorEmail } = data;

  if (!images || !images.length) {
    throw new functions.https.HttpsError("invalid-argument", "At least one face image required");
  }
  if (!companyId || !operatorEmail) {
    throw new functions.https.HttpsError("invalid-argument", "companyId and operatorEmail required");
  }

  // Load existing enrollment data from both collection locations
  let existingEnrollment = null;
  let operatorRef = null;
  const opsSnap = await db.collection("operators")
    .where("companyId", "==", companyId)
    .where("email", "==", operatorEmail)
    .limit(1).get();

  if (!opsSnap.empty) {
    operatorRef = opsSnap.docs[0].ref;
    existingEnrollment = opsSnap.docs[0].data().faceEnrollment;
  }

  if (!existingEnrollment || !existingEnrollment.enrolled) {
    const companyOps = await db.collection(`companies/${companyId}/operators`)
      .where("email", "==", operatorEmail)
      .limit(1).get();
    if (!companyOps.empty) {
      operatorRef = companyOps.docs[0].ref;
      existingEnrollment = companyOps.docs[0].data().faceEnrollment;
    }
  }

  if (!existingEnrollment || !existingEnrollment.enrolled) {
    throw new functions.https.HttpsError("failed-precondition", "No existing face enrollment found. Use full enrollment instead.");
  }

  const existingPaths = existingEnrollment.referenceFrames || [];
  const existingLandmarks = existingEnrollment.faceLandmarks;

  if (existingPaths.length === 0 && !existingLandmarks) {
    throw new functions.https.HttpsError("failed-precondition", "No existing reference data found.");
  }

  // Resolve the COMPANY-scoped operatorId for the storage key so new training
  // frames match getFaceFrames + the onOperatorDeleted cleanup prefix (the flat
  // operators id differs). Fall back to email only if no company doc exists.
  let storageKey = operatorEmail;
  try {
    const co = await db.collection(`companies/${companyId}/operators`)
      .where("email", "==", operatorEmail).limit(1).get();
    if (!co.empty) storageKey = co.docs[0].id;
  } catch (_) { /* keep email fallback */ }

  const client = new vision.ImageAnnotatorClient();

  // Detect faces in new images
  const newFaceResults = [];
  for (const img of images) {
    try {
      const [result] = await client.faceDetection({ image: { content: img } });
      const faces = result.faceAnnotations || [];
      if (faces.length === 0) continue;

      const bestFace = faces.reduce((a, b) =>
        (a.detectionConfidence || 0) > (b.detectionConfidence || 0) ? a : b
      );

      if ((bestFace.detectionConfidence || 0) < 0.65) continue;

      const landmarks = {};
      for (const lm of (bestFace.landmarks || [])) {
        landmarks[lm.type] = { x: lm.position.x, y: lm.position.y, z: lm.position.z || 0 };
      }

      newFaceResults.push({
        confidence: bestFace.detectionConfidence,
        landmarks,
        imageIndex: images.indexOf(img),
      });
    } catch (e) {
      functions.logger.warn("trainOperatorFace: face detection failed for frame:", e.message);
    }
  }

  if (newFaceResults.length < 3) {
    return {
      success: false,
      facesDetected: newFaceResults.length,
      message: `Only ${newFaceResults.length} valid face(s) detected. Need at least 3 clear shots for training.`,
    };
  }

  if (!existingLandmarks) {
    throw new functions.https.HttpsError("failed-precondition", "Existing enrollment has no landmark data for comparison.");
  }

  // Compare new frames against existing enrollment landmarks with RELAXED tolerance
  const TRAINING_SIMILARITY_THRESHOLD = 0.55; // relaxed from 0.75 used in full enrollment
  let matchCount = 0;
  for (const face of newFaceResults) {
    const sim = computeLandmarkSimilarity(face.landmarks, existingLandmarks);
    if (sim >= TRAINING_SIMILARITY_THRESHOLD) matchCount++;
  }

  const matchRatio = matchCount / newFaceResults.length;
  functions.logger.info(`trainOperatorFace: ${matchCount}/${newFaceResults.length} frames match existing (ratio=${matchRatio.toFixed(2)}, threshold=${TRAINING_SIMILARITY_THRESHOLD})`);

  if (matchRatio < 0.6) {
    return {
      success: false,
      facesDetected: newFaceResults.length,
      matchedFrames: matchCount,
      message: "New frames don't sufficiently match existing face data. This doesn't appear to be the same person.",
    };
  }

  // Upload new training frames to storage (best-effort, non-fatal)
  const existingCount = existingPaths.length;
  const newStoragePaths = [];
  try {
    const uploadPromises = newFaceResults.map(async (face, idx) => {
      const imgBase64 = images[face.imageIndex];
      const imgBuffer = Buffer.from(imgBase64, "base64");
      const path = `face-enrollment/${companyId}/${storageKey}/train_${existingCount + idx}.jpg`;
      const file = bucket.file(path);
      await file.save(imgBuffer, { contentType: "image/jpeg", metadata: { cacheControl: "private,max-age=31536000" } });
      newStoragePaths.push(path);
    });
    await Promise.all(uploadPromises);
    functions.logger.info(`trainOperatorFace: uploaded ${newStoragePaths.length} training frames`);
  } catch (e) {
    functions.logger.warn("trainOperatorFace: storage upload skipped:", e.message);
  }

  // Update enrollment data
  const allPaths = [...existingPaths, ...newStoragePaths];
  const newAvgConf = newFaceResults.reduce((s, f) => s + f.confidence, 0) / newFaceResults.length;
  const prevCount = existingEnrollment.faceCount || existingCount || 1;
  const blendedConfidence = (existingEnrollment.averageConfidence * prevCount + newAvgConf * newFaceResults.length) / (prevCount + newFaceResults.length);

  const updatedEnrollment = {
    ...existingEnrollment,
    referenceFrames: allPaths,
    validFrameCount: allPaths.length,
    faceCount: (existingEnrollment.faceCount || existingCount) + newFaceResults.length,
    averageConfidence: blendedConfidence,
    lastTrainedAt: admin.firestore.FieldValue.serverTimestamp(),
    trainingSessions: (existingEnrollment.trainingSessions || 0) + 1,
  };

  // Save to both operator document locations
  try {
    const flatOps = await db.collection("operators")
      .where("companyId", "==", companyId)
      .where("email", "==", operatorEmail)
      .limit(1).get();
    if (!flatOps.empty) {
      await flatOps.docs[0].ref.update({ faceEnrollment: updatedEnrollment });
    }
    const companyOps = await db.collection(`companies/${companyId}/operators`)
      .where("email", "==", operatorEmail)
      .limit(1).get();
    if (!companyOps.empty) {
      await companyOps.docs[0].ref.update({ faceEnrollment: updatedEnrollment });
    }
  } catch (e) {
    functions.logger.warn("trainOperatorFace: could not update operator doc:", e.message);
  }

  return {
    success: true,
    facesDetected: newFaceResults.length,
    matchedFrames: matchCount,
    totalFrames: allPaths.length,
    message: "Training data added successfully.",
  };
});

// verifyOperatorFace - Real-time face identification across all enrolled operators in a company.
// Detects face in frame, compares against ALL enrolled operators, returns best match.
exports.verifyOperatorFace = fns.runWith({ timeoutSeconds: 30, memory: "512MB" }).https.onCall(async (data) => {
  const { image, companyId } = data;

  if (!image) {
    throw new functions.https.HttpsError("invalid-argument", "Face image required");
  }
  if (!companyId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId required");
  }

  // Detect face in the provided frame
  const client = new vision.ImageAnnotatorClient();
  let liveLandmarks = null;
  let liveConfidence = 0;

  try {
    const [result] = await client.faceDetection({ image: { content: image } });
    const faces = result.faceAnnotations || [];

    if (faces.length === 0) {
      return { match: false, reason: "no_face", message: "No face detected in the frame." };
    }

    if (faces.length > 1) {
      return { match: false, reason: "multiple_faces", message: "Multiple faces detected. Only the operator should be visible." };
    }

    const face = faces[0];
    liveConfidence = face.detectionConfidence || 0;

    if (liveConfidence < 0.6) {
      return { match: false, reason: "low_confidence", message: "Face detection confidence too low. Ensure good lighting." };
    }

    const blur = face.blurredLikelihood || "UNKNOWN";
    if (blur === "VERY_LIKELY" || blur === "LIKELY") {
      return { match: false, reason: "blurry", message: "Image too blurry. Hold steady and ensure good lighting." };
    }

    liveLandmarks = {};
    for (const lm of (face.landmarks || [])) {
      liveLandmarks[lm.type] = { x: lm.position.x, y: lm.position.y, z: lm.position.z || 0 };
    }
  } catch (e) {
    functions.logger.error("verifyOperatorFace: detection error:", e.message);
    return { match: false, reason: "detection_error", message: "Face detection failed. Try again." };
  }

  // Load ALL operators in this company and filter to enrolled ones in-memory
  // (avoids requiring a composite index on nested map fields)
  let opsSnap = await db.collection(`companies/${companyId}/operators`).get();

  // Fallback: also check flat operators collection
  if (opsSnap.empty) {
    opsSnap = await db.collection("operators")
      .where("companyId", "==", companyId)
      .get();
  }

  // Filter to those with face enrollment
  const enrolledDocs = opsSnap.docs.filter(doc => {
    const fe = doc.data().faceEnrollment;
    return fe && fe.enrolled === true && fe.faceLandmarks;
  });

  if (enrolledDocs.length === 0) {
    return { match: false, reason: "no_enrollments", message: "No enrolled operators found in this company." };
  }

  // Compare against each enrolled operator
  const VERIFY_THRESHOLD = 0.65;
  let bestMatch = null;
  let bestSimilarity = 0;

  for (const doc of enrolledDocs) {
    const opData = doc.data();
    const enrollment = opData.faceEnrollment;

    const similarity = computeLandmarkSimilarity(liveLandmarks, enrollment.faceLandmarks);

    if (similarity > bestSimilarity) {
      bestSimilarity = similarity;
      bestMatch = {
        operatorId: doc.id,
        email: opData.email || "",
        name: opData.name || "",
        isActive: opData.isActive !== false,
        shiftRestricted: opData.shiftRestricted || false,
        shiftStart: opData.shiftStart || "",
        shiftEnd: opData.shiftEnd || "",
        shiftDays: opData.shiftDays || [],
      };
    }
  }

  functions.logger.info(`verifyOperatorFace: best match=${bestMatch?.email || "none"}, similarity=${bestSimilarity.toFixed(3)}, threshold=${VERIFY_THRESHOLD}, candidates=${enrolledDocs.length}`);

  if (bestSimilarity >= VERIFY_THRESHOLD && bestMatch) {
    return {
      match: true,
      confidence: bestSimilarity,
      detectionConfidence: liveConfidence,
      operator: bestMatch,
      message: "Identity verified.",
    };
  } else {
    return {
      match: false,
      reason: "mismatch",
      confidence: bestSimilarity,
      message: "Face does not match any enrolled operator.",
    };
  }
});

// ─── Operator PIN storage (server-only `operator_pins`) ──────────────────────
// PINs are 4-6 digits, so a client-readable hash on the operator doc can be
// brute-forced offline. The hash now lives in the server-only `operator_pins`
// collection; the operator doc carries only a non-sensitive `hasPin` flag.
function _pinDocId(companyId, email) {
  return `${companyId}__${String(email || "").trim().toLowerCase()}`;
}

// Read the PIN hash: operator_pins first, then the operator doc (transition fallback).
async function _readPinHash(companyId, email) {
  const ps = await db.collection("operator_pins").doc(_pinDocId(companyId, email)).get();
  if (ps.exists && ps.data().pinHash) return ps.data().pinHash;
  const nested = await db.collection(`companies/${companyId}/operators`)
    .where("email", "==", email).limit(1).get();
  if (!nested.empty && nested.docs[0].data().pinHash) return nested.docs[0].data().pinHash;
  const flat = await db.collection("operators")
    .where("companyId", "==", companyId).where("email", "==", email).limit(1).get();
  if (!flat.empty && flat.docs[0].data().pinHash) return flat.docs[0].data().pinHash;
  return null;
}

// Write the hash to operator_pins + set hasPin:true on the operator doc(s).
// stripDoc=true also deletes the legacy pinHash from the doc.
async function _writePinHash(companyId, email, pinHash, { stripDoc = true } = {}) {
  const emailLc = String(email || "").trim().toLowerCase();
  await db.collection("operator_pins").doc(_pinDocId(companyId, emailLc)).set({
    pinHash, companyId, email: emailLc,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  const upd = { hasPin: true, pinSetAt: admin.firestore.FieldValue.serverTimestamp() };
  if (stripDoc) upd.pinHash = admin.firestore.FieldValue.delete();
  for (const q of [
    db.collection(`companies/${companyId}/operators`).where("email", "==", emailLc).limit(1),
    db.collection("operators").where("companyId", "==", companyId).where("email", "==", emailLc).limit(1),
  ]) {
    const s = await q.get();
    if (!s.empty) await s.docs[0].ref.update(upd);
  }
}

// verifyOperatorPin - Verify operator PIN for fallback authentication.
// If PIN doesn't match the current operator, checks all operators in the company.
// Returns operatorEmail/operatorName of the matched operator for switch detection.
exports.verifyOperatorPin = fns.https.onCall(async (data) => {
  const { pin, companyId, operatorEmail } = data;

  if (!pin || !companyId) {
    throw new functions.https.HttpsError("invalid-argument", "pin and companyId required");
  }

  // Brute-force throttle — PINs are only 4-6 digits. Keyed per company,
  // server-only (pin_throttle is default-denied to clients).
  const throttleRef = db.collection("pin_throttle").doc(companyId);
  const throttleSnap = await throttleRef.get();
  if (throttleSnap.exists) {
    const t = throttleSnap.data();
    if (t.lockedUntil && t.lockedUntil.toDate() > new Date()) {
      const wait = Math.ceil((t.lockedUntil.toDate().getTime() - Date.now()) / 1000);
      throw new functions.https.HttpsError(
        "resource-exhausted", `Too many incorrect PIN attempts. Try again in ${wait}s.`);
    }
  }

  const crypto = require("crypto");

  // First: try matching against the current operator (fast path)
  if (operatorEmail) {
    let operatorDoc = null;
    const companyOps = await db.collection(`companies/${companyId}/operators`)
      .where("email", "==", operatorEmail)
      .limit(1).get();

    if (!companyOps.empty) {
      operatorDoc = companyOps.docs[0];
    } else {
      const flatOps = await db.collection("operators")
        .where("companyId", "==", companyId)
        .where("email", "==", operatorEmail)
        .limit(1).get();
      if (!flatOps.empty) operatorDoc = flatOps.docs[0];
    }

    if (operatorDoc) {
      const storedHash = await _readPinHash(companyId, operatorEmail);
      if (storedHash) {
        const inputHash = crypto.createHash("sha256").update(pin + operatorEmail).digest("hex");
        if (inputHash === storedHash) {
          await operatorDoc.ref.update({
            lastPinVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          await throttleRef.set({ fails: 0 }, { merge: true });
          return { match: true, message: "PIN verified.", operatorName: operatorDoc.data().name || "", operatorEmail: operatorEmail, isSameOperator: true };
        }
      }
    }
  }

  // Second: check all other operators in the company
  const allOps = await db.collection(`companies/${companyId}/operators`).get();
  for (const doc of allOps.docs) {
    const opData = doc.data();
    const opEmail = opData.email || "";
    if (opEmail === operatorEmail) continue;
    const _ps = await db.collection("operator_pins").doc(_pinDocId(companyId, opEmail)).get();
    const storedHash = (_ps.exists && _ps.data().pinHash) ? _ps.data().pinHash : opData.pinHash;
    if (!storedHash) continue;
    const inputHash = crypto.createHash("sha256").update(pin + opEmail).digest("hex");
    if (inputHash === storedHash) {
      await doc.ref.update({
        lastPinVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await throttleRef.set({ fails: 0 }, { merge: true });
      return { match: true, message: "PIN verified.", operatorName: opData.name || "", operatorEmail: opEmail, isSameOperator: false };
    }
  }

  // No match — record the failed attempt and lock out after 5 in a row.
  const fails = (throttleSnap.exists ? (throttleSnap.data().fails || 0) : 0) + 1;
  if (fails >= 5) {
    await throttleRef.set({
      fails: 0,
      lockedUntil: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 5 * 60 * 1000)),
    }, { merge: true });
  } else {
    await throttleRef.set({ fails }, { merge: true });
  }

  return { match: false, message: "Incorrect PIN." };
});

// setOperatorPin - Set or update operator PIN.
exports.setOperatorPin = fns.https.onCall(async (data) => {
  const { pin, companyId, operatorEmail } = data;

  if (!pin || !companyId || !operatorEmail) {
    throw new functions.https.HttpsError("invalid-argument", "pin, companyId, and operatorEmail required");
  }
  // Caller must be the operator themselves, or an admin of the same company.
  const _sess = await _requireSession(data);
  const _isSelf = _sess.email === String(operatorEmail).trim().toLowerCase();
  const _isAdmin = _sess.role === "admin" || _sess.role === "companyAdmin";
  if (_sess.companyId !== companyId || (!_isSelf && !_isAdmin)) {
    throw new functions.https.HttpsError("permission-denied", "Not authorized to set this PIN.");
  }

  if (pin.length < 4 || pin.length > 6 || !/^\d+$/.test(pin)) {
    throw new functions.https.HttpsError("invalid-argument", "PIN must be 4-6 digits.");
  }

  const crypto = require("crypto");
  const pinHash = crypto.createHash("sha256").update(pin + operatorEmail).digest("hex");
  await _writePinHash(companyId, operatorEmail, pinHash); // server-only store + hasPin flag; strips legacy doc hash

  return { success: true, message: "PIN set successfully." };
});

// ─── Face enrollment frames: store on enroll, fetch for the admin gallery ─────
// Frames are kept (not deleted) so an admin can EXCLUDE specific shots from the
// embedding without losing them. The re-embed itself runs on the local sidecar
// client-side; these functions only handle Storage I/O (admin SDK, no rules).

exports.storeFaceFrames = fns.runWith({ timeoutSeconds: 120, memory: "512MB" }).https.onCall(async (data) => {
  const companyId = String((data && data.companyId) || "").trim();
  const operatorId = String((data && data.operatorId) || "").trim();
  // New shape: frames = [{image, quality, specs}]. Back-compat: images = [b64].
  let frames = Array.isArray(data && data.frames) ? data.frames : null;
  if (!frames && Array.isArray(data && data.images)) {
    frames = data.images.map((image) => ({ image, quality: 0, specs: false }));
  }
  const enrolledAt = String((data && data.enrolledAt) || "");
  if (!companyId || !operatorId || !Array.isArray(frames) || frames.length === 0) {
    throw new functions.https.HttpsError("invalid-argument", "companyId, operatorId and frames required");
  }
  const prefix = `face-enrollment/${companyId}/${operatorId}/`;
  // Replace any previous frames for this operator (re-enrollment overwrites).
  try { await bucket.deleteFiles({ prefix }); } catch (_) {}
  // Compress/resize so the gallery loads fast and getFaceFrames stays well under
  // the callable response limit (full webcam frames are several MB each).
  let Jimp;
  try { Jimp = require("jimp"); } catch (_) { Jimp = null; }
  const meta = new Array(frames.length);
  await Promise.all(frames.map(async (fr, i) => {
    let buf = Buffer.from(fr.image, "base64");
    if (Jimp) {
      try {
        const j = await Jimp.read(buf);
        if (j.bitmap.width > 480) j.resize(480, Jimp.AUTO);
        j.quality(78);
        buf = await j.getBufferAsync(Jimp.MIME_JPEG);
      } catch (_) { /* fall back to original bytes */ }
    }
    const path = `${prefix}frame_${i}.jpg`;
    await bucket.file(path).save(buf, {
      contentType: "image/jpeg",
      metadata: { cacheControl: "private,max-age=0" },
    });
    meta[i] = { path, quality: Number(fr.quality) || 0, specs: fr.specs === true };
  }));
  await db.doc(`companies/${companyId}/operators/${operatorId}`).set(
    { faceFrames: meta, faceFramesEnrolledAt: enrolledAt, excludedFrames: [] },
    { merge: true },
  );
  return { success: true, count: meta.length };
});

exports.getFaceFrames = fns.runWith({ timeoutSeconds: 60, memory: "512MB" }).https.onCall(async (data) => {
  const companyId = String((data && data.companyId) || "").trim();
  const operatorId = String((data && data.operatorId) || "").trim();
  if (!companyId || !operatorId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId and operatorId required");
  }
  const doc = await db.doc(`companies/${companyId}/operators/${operatorId}`).get();
  const d = doc.data() || {};
  // faceFrames is now [{path,quality,specs}]; tolerate the old [path] shape.
  const raw = Array.isArray(d.faceFrames) ? d.faceFrames : [];
  const items = raw.map((e) => (typeof e === "string" ? { path: e, quality: 0, specs: false } : e));
  const excluded = new Set(Array.isArray(d.excludedFrames) ? d.excludedFrames : []);
  const frames = [];
  await Promise.all(items.map(async (it) => {
    try {
      const [buf] = await bucket.file(it.path).download();
      frames.push({
        path: it.path,
        image: buf.toString("base64"),
        quality: Number(it.quality) || 0,
        specs: it.specs === true,
        excluded: excluded.has(it.path),
      });
    } catch (_) { /* skip a frame that's gone missing */ }
  }));
  return { frames, enrolledAt: d.faceFramesEnrolledAt || "" };
});

// sendPinResetChallenge - Begins a verified PIN reset for [email] (the actor).
// If the actor has 2FA, they verify with their authenticator (no OTP sent).
// Otherwise the SAME one-time code is sent to their email and phone.
exports.sendPinResetChallenge = fns.https.onCall(async (data) => {
  const email = (data.email || "").trim().toLowerCase();
  if (!email) throw new functions.https.HttpsError("invalid-argument", "Email required");

  const credSnap = await db.collection("credentials").doc(email).get();
  const cred = credSnap.exists ? credSnap.data() : {};
  if (cred.mfaEnabled && cred.mfaSecret) {
    return { method: "totp" };
  }

  const crypto = require("crypto");
  const otp = generateOTP();
  const otpHash = crypto.createHash("sha256").update(otp).digest("hex");
  const expiresAt = admin.firestore.Timestamp.fromDate(new Date(Date.now() + OTP_EXPIRY_MS));
  await db.collection("verification_otps").doc(email).set({
    otpHash, expiresAt, attempts: 0, type: "pin-reset",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  let phone = "";
  try {
    const opSnap = await db.collectionGroup("operators").where("email", "==", email).limit(1).get();
    if (!opSnap.empty) phone = opSnap.docs[0].data().phone || "";
  } catch (_) {}

  try {
    const heading = "Confirm your PIN reset";
    const intro = `Use this code to confirm you're resetting a verification PIN in ${BRAND.name}.`;
    const securityNote = `If you didn't request this, ignore this message. ${BRAND.name} will never ask you to share this code.`;
    await _sendDesignedEmail(email, `${BRAND.name} PIN reset code: ${otp}`, "otp",
      { eyebrow: "PIN reset", heading, intro, otp, securityNote, company: {} },
      { alt: `${BRAND.name} PIN reset code: ${otp}`, fallbackHtml: buildOtpEmail({ heading, intro, otp, securityNote }) });
  } catch (e) { console.warn("PIN reset email failed:", e.message); }

  let smsSent = false;
  if (phone) {
    const digits = phone.replace(/\D/g, "").slice(-10);
    if (digits.length === 10) {
      try { await _sendOtpSms(digits, otp); smsSent = true; } catch (e) { console.warn("PIN reset SMS failed:", e.message); }
    }
  }
  return { method: "otp", email: true, sms: smsSent };
});

// verifyPinResetCode - Step 1 of a PIN reset: validate the actor's TOTP or OTP.
// On success a short-lived grant is recorded so the new PIN can be set next —
// keeps TOTP (which rotates) from expiring while the user types the new PIN.
exports.verifyPinResetCode = fns.https.onCall(async (data) => {
  const email = (data.email || "").trim().toLowerCase();
  const code = String(data.code || "").replace(/\s/g, "");
  if (!email) throw new functions.https.HttpsError("invalid-argument", "Email required");
  const credSnap = await db.collection("credentials").doc(email).get();
  const cred = credSnap.exists ? credSnap.data() : {};
  const crypto = require("crypto");
  let ok = false;
  if (cred.mfaEnabled && cred.mfaSecret) {
    ok = _verifyTotp(_decryptSecret(cred.mfaSecret), code);
  } else {
    const otpRef = db.collection("verification_otps").doc(email);
    const otpSnap = await otpRef.get();
    if (otpSnap.exists) {
      const od = otpSnap.data();
      if (od.expiresAt.toDate() >= new Date() && (od.attempts || 0) < OTP_MAX_ATTEMPTS) {
        const inputHash = crypto.createHash("sha256").update(code).digest("hex");
        if (inputHash === od.otpHash) { ok = true; await otpRef.delete(); }
        else { await otpRef.update({ attempts: admin.firestore.FieldValue.increment(1) }); }
      }
    }
    if (!ok && code === "000000" && ALLOW_TEST_OTP) ok = true;
  }
  if (!ok) throw new functions.https.HttpsError("permission-denied", "Verification failed. Check the code and try again.");
  await db.collection("pin_reset_grants").doc(email).set({
    grantedAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000)),
  });
  return { ok: true };
});

// resetOperatorPin - Step 2: with a fresh verifyPinResetCode grant, set the PIN.
exports.resetOperatorPin = fns.https.onCall(async (data) => {
  const actorEmail = (data.actorEmail || "").trim().toLowerCase();
  const operatorEmail = (data.operatorEmail || "").trim().toLowerCase();
  const companyId = data.companyId;
  const pin = data.pin;
  if (!actorEmail || !operatorEmail || !companyId || !pin) {
    throw new functions.https.HttpsError("invalid-argument", "actorEmail, operatorEmail, companyId and pin required");
  }
  // Session must belong to the actor; actor may reset only their own PIN, or any
  // operator's if they're an admin of the same company (fixes the grant IDOR).
  const _sess = await _requireSession(data);
  const _isAdmin = _sess.role === "admin" || _sess.role === "companyAdmin";
  if (_sess.companyId !== companyId || _sess.email !== actorEmail ||
      (!(actorEmail === operatorEmail) && !_isAdmin)) {
    throw new functions.https.HttpsError("permission-denied", "Not authorized to reset this PIN.");
  }
  if (pin.length < 4 || pin.length > 6 || !/^\d+$/.test(pin)) {
    throw new functions.https.HttpsError("invalid-argument", "PIN must be 4-6 digits.");
  }
  const grantRef = db.collection("pin_reset_grants").doc(actorEmail);
  const grantSnap = await grantRef.get();
  const grant = grantSnap.exists ? grantSnap.data() : null;
  if (!grant || !grant.expiresAt || grant.expiresAt.toDate() < new Date()) {
    throw new functions.https.HttpsError("failed-precondition", "Verify your identity again before setting a new PIN.");
  }
  const crypto = require("crypto");
  const pinHash = crypto.createHash("sha256").update(pin + operatorEmail).digest("hex");
  await _writePinHash(companyId, operatorEmail, pinHash); // server-only store + hasPin flag; strips legacy doc hash
  await grantRef.delete();
  return { ok: true };
});

// Move a single operator doc's legacy pinHash into operator_pins and strip it.
// Writes operator_pins FIRST, so a failure can never leave the operator pin-less.
async function _relocatePinFromDoc(docRef, opData) {
  if (!opData.pinHash || !opData.email) return false;
  const companyId = opData.companyId || _companyIdFromPath(docRef.path);
  if (!companyId) return false;
  const ref = db.collection("operator_pins").doc(_pinDocId(companyId, opData.email));
  // operator_pins is authoritative — a PIN change (setOperatorPin) writes it
  // directly. NEVER overwrite an existing entry with the doc's possibly-stale
  // copy (e.g. a site-operator doc the strip query missed); only fill a gap.
  // Otherwise a PIN change would silently revert on the next sweep.
  if (!(await ref.get()).exists) {
    await ref.set({
      pinHash: opData.pinHash, companyId, email: String(opData.email).trim().toLowerCase(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await docRef.update({ pinHash: admin.firestore.FieldValue.delete(), hasPin: true });
  return true;
}

// One-time backfill for a company: relocate every legacy doc pinHash (nested,
// site, or flat) into operator_pins. Admin-of-company only. Idempotent.
exports.migratePinHashes = fns.https.onCall(async (data) => {
  const companyId = data.companyId;
  if (!companyId) throw new functions.https.HttpsError("invalid-argument", "companyId required");
  await _requireAdminSession(data, companyId);
  let moved = 0;
  const snap = await db.collectionGroup("operators").get();
  for (const d of snap.docs) {
    const o = d.data();
    if (!o.pinHash || !o.email) continue;
    if ((o.companyId || _companyIdFromPath(d.ref.path)) !== companyId) continue;
    if (await _relocatePinFromDoc(d.ref, o)) moved++;
  }
  return { ok: true, moved };
});

// Hourly backstop: relocate any pinHash that slipped onto a doc (e.g. a new
// registration), so the brute-force exposure window is at most ~1 hour.
exports.sweepPinHashes = fns.pubsub.schedule("every 60 minutes").timeZone("Asia/Kolkata").onRun(async () => {
  const snap = await db.collectionGroup("operators").get();
  let moved = 0;
  for (const d of snap.docs) {
    if (await _relocatePinFromDoc(d.ref, d.data())) moved++;
  }
  if (moved) console.log(`sweepPinHashes relocated ${moved} pin hash(es)`);
  return null;
});

// Compute similarity between two faces using discriminative facial ratios.
// Ratios are scale/position-invariant and capture unique proportions of a face.
function computeLandmarkSimilarity(landmarks1, landmarks2) {
  if (!landmarks1 || !landmarks2) return 0;

  const dist = (a, b) => {
    if (!a || !b) return null;
    return Math.sqrt(Math.pow(a.x - b.x, 2) + Math.pow(a.y - b.y, 2));
  };

  // Extract key facial distances and compute ratios
  const computeRatios = (lms) => {
    const leftEye = lms["LEFT_EYE"] || lms["LEFT_EYE_PUPIL"];
    const rightEye = lms["RIGHT_EYE"] || lms["RIGHT_EYE_PUPIL"];
    const noseTip = lms["NOSE_TIP"];
    const noseBottom = lms["NOSE_BOTTOM_CENTER"];
    const mouth = lms["UPPER_LIP"] || lms["MOUTH_CENTER"];
    const mouthLeft = lms["MOUTH_LEFT"];
    const mouthRight = lms["MOUTH_RIGHT"];
    const chin = lms["CHIN_GNATHION"] || lms["CHIN_LEFT_GONION"];
    const leftEar = lms["LEFT_EAR_TRAGION"];
    const rightEar = lms["RIGHT_EAR_TRAGION"];
    const leftEyebrow = lms["LEFT_OF_LEFT_EYEBROW"];
    const rightEyebrow = lms["RIGHT_OF_RIGHT_EYEBROW"];
    const foreheadMid = lms["FOREHEAD_GLABELLA"] || lms["MIDPOINT_BETWEEN_EYES"];

    const eyeDist = dist(leftEye, rightEye);
    if (!eyeDist || eyeDist < 5) return null;

    const ratios = [];

    // Nose length / eye distance
    const noseLen = dist(foreheadMid || noseTip, noseBottom || noseTip);
    if (noseLen) ratios.push(noseLen / eyeDist);

    // Nose to mouth / eye distance
    const noseToMouth = dist(noseBottom || noseTip, mouth);
    if (noseToMouth) ratios.push(noseToMouth / eyeDist);

    // Mouth width / eye distance
    const mouthWidth = dist(mouthLeft, mouthRight);
    if (mouthWidth) ratios.push(mouthWidth / eyeDist);

    // Nose to chin / eye distance
    const noseToChin = dist(noseBottom || noseTip, chin);
    if (noseToChin) ratios.push(noseToChin / eyeDist);

    // Face width (ear-to-ear) / eye distance
    const faceWidth = dist(leftEar, rightEar);
    if (faceWidth) ratios.push(faceWidth / eyeDist);

    // Left eye to nose / eye distance
    const leftEyeToNose = dist(leftEye, noseTip);
    if (leftEyeToNose) ratios.push(leftEyeToNose / eyeDist);

    // Right eye to nose / eye distance
    const rightEyeToNose = dist(rightEye, noseTip);
    if (rightEyeToNose) ratios.push(rightEyeToNose / eyeDist);

    // Eyebrow span / eye distance
    const browSpan = dist(leftEyebrow, rightEyebrow);
    if (browSpan) ratios.push(browSpan / eyeDist);

    // Forehead to nose / nose to chin (vertical thirds)
    if (foreheadMid && noseTip && chin) {
      const upper = dist(foreheadMid, noseTip);
      const lower = dist(noseTip, chin);
      if (upper && lower && lower > 0) ratios.push(upper / lower);
    }

    // Eye to mouth / eye distance
    const leftEyeToMouth = dist(leftEye, mouth);
    if (leftEyeToMouth) ratios.push(leftEyeToMouth / eyeDist);

    return ratios.length >= 5 ? ratios : null;
  };

  const ratios1 = computeRatios(landmarks1);
  const ratios2 = computeRatios(landmarks2);
  if (!ratios1 || !ratios2) return 0;

  // Compare only ratios that both sets have (same indices)
  const len = Math.min(ratios1.length, ratios2.length);
  if (len < 5) return 0;

  let totalRelDiff = 0;
  for (let i = 0; i < len; i++) {
    const avg = (ratios1[i] + ratios2[i]) / 2;
    if (avg === 0) continue;
    totalRelDiff += Math.abs(ratios1[i] - ratios2[i]) / avg;
  }

  const avgRelDiff = totalRelDiff / len;

  // Convert to 0-1 similarity. Same person typically < 0.15 diff, different person > 0.25
  // Threshold at 0.3: 0 diff = 1.0, 0.3+ diff = 0.0
  return Math.max(0, 1 - avgRelDiff / 0.3);
}

// Average multiple landmark sets into one representative set
function averageLandmarks(landmarkSets) {
  if (!landmarkSets.length) return {};
  const allKeys = new Set();
  for (const lms of landmarkSets) {
    for (const k of Object.keys(lms)) allKeys.add(k);
  }

  const averaged = {};
  for (const k of allKeys) {
    let sumX = 0, sumY = 0, sumZ = 0, count = 0;
    for (const lms of landmarkSets) {
      if (lms[k]) {
        sumX += lms[k].x;
        sumY += lms[k].y;
        sumZ += lms[k].z || 0;
        count++;
      }
    }
    if (count > 0) {
      averaged[k] = { x: sumX / count, y: sumY / count, z: sumZ / count };
    }
  }
  return averaged;
}

// ═══════════════════════════════════════════════════════════════════════════════
// ─── DigiLocker Identity Verification (via Meon Gateway) ─────────────────────
// ═══════════════════════════════════════════════════════════════════════════════
// Aadhaar-only flow. Three Meon REST calls, all server-side so the secret token
// never reaches the client:
//   1. POST /get_access_token        → { client_token, state }
//   2. POST /digi_url                → { url }  (the DigiLocker OAuth URL)
//   3. POST /v2/send_entire_data     → { data: { ...aadhaar fields } }
// The client opens the URL in an in-app webview and polls fetchMeonAadhaar.

const MEON_BASE = process.env.MEON_BASE_URL || "https://digilocker.meon.co.in";
const MEON_COMPANY = process.env.MEON_COMPANY_NAME || "";
const MEON_SECRET = process.env.MEON_SECRET_TOKEN || "";
const MEON_REDIRECT = process.env.MEON_REDIRECT_URL || "https://digilocker.meon.co.in/digilocker/thank-you-page";

async function meonFetch(path, body) {
  const fetch = (await import("node-fetch")).default;
  const res = await fetch(`${MEON_BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new Error(`Meon ${path} non-JSON ${res.status}: ${text.slice(0, 200)}`);
  }
  if (!res.ok) {
    throw new Error(`Meon ${path} error ${res.status}: ${text.slice(0, 200)}`);
  }
  return json;
}

/**
 * initiateMeonDigilocker
 * Mints a Meon access token and a DigiLocker authorization URL (Aadhaar only).
 *
 * Works pre-authentication (admin company step / operator company-code step run
 * before a Firebase Auth account exists) — authorize by session reference, not
 * by context.auth.
 *
 * Input:  { purpose?, documents?, companyId? }
 * Output: { reference, url, redirectUrl }
 */
exports.initiateMeonDigilocker = fns.runWith({ timeoutSeconds: 30 }).https.onCall(async (data, context) => {
  const uid = context.auth?.uid || data.uid || `anon_${Date.now()}`;
  if (!MEON_COMPANY || !MEON_SECRET) {
    throw new functions.https.HttpsError("failed-precondition", "Meon DigiLocker credentials not configured");
  }

  // 1. Access token.
  const tokenRes = await meonFetch("/get_access_token", {
    company_name: MEON_COMPANY,
    secret_token: MEON_SECRET,
  });
  if (!tokenRes.client_token || !tokenRes.state) {
    throw new functions.https.HttpsError("internal", "Meon token response missing client_token/state");
  }

  // 2. DigiLocker URL — force Aadhaar only regardless of caller input.
  const urlRes = await meonFetch("/digi_url", {
    client_token: tokenRes.client_token,
    redirect_url: MEON_REDIRECT,
    company_name: MEON_COMPANY,
    documents: "aadhaar",
  });
  if (!urlRes.url) {
    throw new functions.https.HttpsError("internal", "Meon did not return a DigiLocker URL");
  }

  const reference = db.collection("digilocker_sessions").doc().id;
  await db.collection("digilocker_sessions").doc(reference).set({
    reference,
    gateway: "meon",
    uid,
    purpose: data.purpose || null,
    companyId: data.companyId || null,
    clientToken: tokenRes.client_token,
    state: tokenRes.state,
    status: "initiated",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { reference, url: urlRes.url, redirectUrl: MEON_REDIRECT };
});

/**
 * fetchMeonAadhaar
 * Retrieves exported Aadhaar data for a session, persists the photo to Storage,
 * and returns a normalized result. Returns { verified: false } (no reason) while
 * the user has not completed the flow yet — the client polls this.
 *
 * Input:  { reference }
 * Output: { verified, name, dob, gender, aadhaarLast4, fatherName, address,
 *           locality, dist, state, pincode, photoUrl }
 */
exports.fetchMeonAadhaar = fns.runWith({ timeoutSeconds: 60, memory: "512MB" }).https.onCall(async (data, context) => {
  const uid = context.auth?.uid || data.uid || null;
  const { reference } = data;
  if (!reference) {
    throw new functions.https.HttpsError("invalid-argument", "reference required");
  }

  const ref = db.collection("digilocker_sessions").doc(reference);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Session not found");
  }
  const session = snap.data();
  // Authorize: same signed-in user, or a pre-account (anon_) session.
  if (uid && session.uid && !String(session.uid).startsWith("anon_") && session.uid !== uid) {
    throw new functions.https.HttpsError("permission-denied", "Unauthorized");
  }

  // Return cached result if already fetched.
  if (session.status === "completed" && session.result) {
    return session.result;
  }

  // 3. Retrieve exported data. Until the user finishes, Meon errors or returns
  // no data — treat both as "pending" so the client keeps polling.
  let dataRes;
  try {
    dataRes = await meonFetch("/v2/send_entire_data", {
      client_token: session.clientToken,
      state: session.state,
      status: true,
    });
  } catch (e) {
    functions.logger.info(`Meon fetch pending for ${reference}: ${e.message}`);
    return { verified: false };
  }

  const d = dataRes && dataRes.data;
  if (!d || !(d.aadhar_no || d.name)) {
    return { verified: false };
  }

  // Persist the Aadhaar person-photo to Storage (avoids base64 in Firestore).
  let photoUrl = null;
  try {
    const photoSrc = d.aadhar_img_filename || null;
    if (photoSrc) {
      const fetch = (await import("node-fetch")).default;
      const imgRes = await fetch(photoSrc);
      if (imgRes.ok) {
        const buf = Buffer.from(await imgRes.arrayBuffer());
        const filePath = `kyc/${reference}/photo.jpg`;
        const downloadToken = require("crypto").randomBytes(16).toString("hex");
        await bucket.file(filePath).save(buf, {
          contentType: "image/jpeg",
          metadata: { metadata: { firebaseStorageDownloadTokens: downloadToken } },
        });
        photoUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(filePath)}?alt=media&token=${downloadToken}`;
      }
    }
  } catch (e) {
    functions.logger.warn(`Photo persist failed for ${reference}: ${e.message}`);
  }

  const aadhaarDigits = String(d.aadhar_no || "").replace(/[^0-9]/g, "");
  const result = {
    verified: true,
    name: d.name || null,
    dob: d.dob || null,
    gender: d.gender || null,
    aadhaarLast4: aadhaarDigits ? aadhaarDigits.slice(-4) : null,
    fatherName: d.fathername || null,
    address: d.aadhar_address || null,
    locality: d.locality || null,
    dist: d.dist || null,
    state: d.state || null,
    pincode: d.pincode || null,
    photoUrl,
    reason: null,
  };

  await ref.update({
    status: "completed",
    verified: true,
    name: result.name,
    result,
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return result;
});

// ─── Scheduled Email Report ──────────────────────────────────────────────────
// Runs every day at 8 AM IST (2:30 UTC). Checks each company's emailSchedule
// config and sends a summary report via SendGrid Trigger Email extension.

// Branded HTML for the summary report email — KPIs + top-5 materials as rows,
// in the same shell as every other Tulanam email. (A plain-text body is still
// sent alongside for plain-text clients.)
function _buildReportEmailHtml(periodLabel, totalWeighments, vehicleCount, totalNet, materialTotals) {
  const rows = [
    ["Period", periodLabel],
    ["Total weighments", String(totalWeighments)],
    ["Unique vehicles", String(vehicleCount)],
    ["Net tonnage", `${(totalNet / 1000).toFixed(1)} T`],
  ];
  Object.entries(materialTotals)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .forEach(([m, v]) => rows.push([`Material · ${m}`, `${(v / 1000).toFixed(1)} T`]));
  return buildBrandEmail({
    heading: `Weighment report — ${periodLabel}`,
    intro: `Here is your ${BRAND.name} operations summary.`,
    rows,
    note: `Automated report from ${BRAND.name}.`,
  });
}

exports.scheduledEmailReport = fns.pubsub
  .schedule("30 2 * * *") // 8:00 AM IST daily
  .timeZone("Asia/Kolkata")
  .onRun(async () => {
    const companiesSnap = await db.collection("companies").get();

    for (const companyDoc of companiesSnap.docs) {
      const companyId = companyDoc.id;
      const scheduleDoc = await db.doc(`companies/${companyId}/settings/emailSchedule`).get();
      if (!scheduleDoc.exists) continue;

      const config = scheduleDoc.data();
      if (!config.enabled || !config.recipient) continue;

      // Check frequency
      const now = new Date();
      if (config.frequency === "weekly" && now.getDay() !== 1) continue; // Monday only

      // Gather yesterday's data (or last 7 days for weekly)
      const daysBack = config.frequency === "weekly" ? 7 : 1;
      const startDate = new Date(now);
      startDate.setDate(startDate.getDate() - daysBack);
      startDate.setHours(0, 0, 0, 0);

      // Find all weighbridges
      const sitesSnap = await db.collection(`companies/${companyId}/sites`).get();
      let totalWeighments = 0;
      let totalNet = 0;
      let totalVehicles = new Set();
      const materialTotals = {};
      const hourCounts = new Array(24).fill(0);

      for (const siteDoc of sitesSnap.docs) {
        const wbSnap = await db.collection(`companies/${companyId}/sites/${siteDoc.id}/weighbridges`).get();
        for (const wbDoc of wbSnap.docs) {
          const weighmentsSnap = await db
            .collection(`companies/${companyId}/sites/${siteDoc.id}/weighbridges/${wbDoc.id}/weighments`)
            .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(startDate))
            .where("status", "==", "completed")
            .get();

          for (const w of weighmentsSnap.docs) {
            const d = w.data();
            totalWeighments++;
            totalNet += (d.netWeight || 0);
            if (d.vehicleNumber) totalVehicles.add(d.vehicleNumber);
            const mat = d.material || "Unknown";
            materialTotals[mat] = (materialTotals[mat] || 0) + (d.netWeight || 0);
            if (d.createdAt && d.createdAt.toDate) {
              const istHour = Number(d.createdAt.toDate().toLocaleString("en-US", { hour: "2-digit", hour12: false, timeZone: "Asia/Kolkata" })) % 24;
              if (!Number.isNaN(istHour)) hourCounts[istHour]++;
            }
          }
        }
      }

      // Build email content
      const period = config.frequency === "weekly" ? "Last 7 Days" : "Yesterday";
      const materialLines = Object.entries(materialTotals)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5)
        .map(([m, v]) => `  • ${m}: ${(v / 1000).toFixed(1)} T`)
        .join("\n");

      const body = `
${BRAND.name} Report — ${period}
${"=".repeat(40)}

Total Weighments: ${totalWeighments}
Unique Vehicles: ${totalVehicles.size}
Net Tonnage: ${(totalNet / 1000).toFixed(1)} T

Top Materials:
${materialLines || "  No data"}

---
Generated: ${now.toLocaleString("en-IN", { timeZone: "Asia/Kolkata" })}
This is an automated report from ${BRAND.name}.
      `.trim();

      const subject = `${BRAND.name} Report — ${period} (${totalWeighments} weighments, ${(totalNet / 1000).toFixed(1)}T)`;
      const reportHtml = _buildReportEmailHtml(period, totalWeighments, totalVehicles.size, totalNet, materialTotals);

      // Try the rendered report (inline image + PDF attachment); fall back to HTML.
      const reportData = {
        company: await _companyDetails(companyId),
        subtitle: `${period} · generated ${now.toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Kolkata" })}`,
        kpis: {
          weighments: String(totalWeighments),
          vehicles: String(totalVehicles.size),
          tonnage: (totalNet / 1000).toLocaleString("en-IN", { maximumFractionDigits: 0 }),
        },
        hours: hourCounts.map((c) => ({ count: c })),
        hourLabels: ["12a", "4a", "8a", "12p", "4p", "8p", "12a"],
        materials: Object.entries(materialTotals).sort((a, b) => b[1] - a[1]).slice(0, 5)
          .map(([m, v]) => ({ name: m, tonnes: Math.round(v / 100) / 10 })),
      };
      if (await _consumeQuota(companyId, "email")) {
        const renderedReport = await _renderEmailAssets("report", reportData, await _printerPageSize(companyId));
        if (renderedReport && renderedReport.imageUrl) {
          // Guard the rendered send: a throw here must not abort the whole loop
          // (skipping every other company). Fall back to the mail collection and
          // tell the admin their report had a delivery issue.
          try {
            await _sendRenderedEmail(config.recipient, subject, {
              imageUrl: renderedReport.imageUrl, pdfBase64: renderedReport.pdfBase64,
              pdfName: `report-${period.replace(/\s+/g, "-").toLowerCase()}.pdf`, fallbackHtml: reportHtml, alt: "Weighment report",
            });
          } catch (sendErr) {
            functions.logger.warn(`Rendered report send failed for ${companyId}, queued as plain mail: ${sendErr.message}`);
            await db.collection("mail").add({
              to: config.recipient,
              message: { subject, html: reportHtml, text: body },
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            }).catch(() => {});
            await _writeInApp({
              companyId, category: "system", severity: "warn", link: "/reports",
              title: "Daily report not delivered",
              body: `Your scheduled ${period} report couldn't be sent the usual way and was queued as a plain email. Check your report settings if reports stop arriving.`,
            }).catch(() => {});
          }
        } else {
          // Branded HTML + text, with mail-collection fallback for the Trigger Email extension.
          try {
            const transporter = getMailTransporter();
            const senderEmail = _fnConfig().gmail?.email || process.env.GMAIL_EMAIL;
            await transporter.sendMail({
              from: `"${BRAND.name}" <${senderEmail}>`, to: config.recipient, subject, html: reportHtml, text: body,
            });
          } catch (mailErr) {
            await db.collection("mail").add({
              to: config.recipient,
              message: { subject, html: reportHtml, text: body },
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            functions.logger.warn(`Direct mail failed, wrote to mail collection: ${mailErr.message}`);
          }
        }
      }

      functions.logger.info(`Email report sent to ${config.recipient} for company ${companyId}`);

      // Optional SMS digest — opt-in via emailSchedule.smsDigest. Best-effort.
      if (config.smsDigest === true) {
        const adminContact = await resolveCompanyAdminContact(companyId);
        if (adminContact.phone) {
          await _sendDltSms("dailyDigest", adminContact.phone, [
            String(totalWeighments),
            (totalNet / 1000).toFixed(1),
          ]);
        }
      }
    }

    return null;
  });

// ─── On-demand Report Email (callable) ───────────────────────────────────────
// Admin can trigger a report email immediately from the app

// Allowlist gate for report recipients: the company's own contact address, any
// operator of the company, or the signed-in caller. Stops the company summary
// from being mailed to an arbitrary external destination.
async function _isCompanyReportRecipient(companyId, recipientEmail, callerEmail) {
  const target = (recipientEmail || "").trim().toLowerCase();
  if (!target) return false;
  if (callerEmail && target === (callerEmail || "").trim().toLowerCase()) return true;
  try {
    const coSnap = await db.doc(`companies/${companyId}`).get();
    if (coSnap.exists) {
      const c = coSnap.data() || {};
      const contacts = [c.email, c.contactEmail, c.companyEmail]
        .filter(Boolean).map((x) => String(x).trim().toLowerCase());
      if (contacts.includes(target)) return true;
    }
  } catch (e) {
    console.warn("report-recipient company lookup failed:", e.message);
  }
  try {
    const opSnap = await db.collection(`companies/${companyId}/operators`)
      .where("email", "==", target).limit(1).get();
    if (!opSnap.empty) return true;
  } catch (e) {
    console.warn("report-recipient operator lookup failed:", e.message);
  }
  try {
    // The company's own SAVED scheduled-report recipient: the daily cron mails to
    // this exact address with NO allowlist check, so the interactive "Send Test
    // Now" path must accept it too — otherwise a legitimate, already-working
    // schedule (e.g. an external accountant) reports as invalid.
    const schedSnap = await db.doc(`companies/${companyId}/settings/emailSchedule`).get();
    if (schedSnap.exists) {
      const saved = String((schedSnap.data() || {}).recipient || "").trim().toLowerCase();
      if (saved && saved === target) return true;
    }
  } catch (e) {
    console.warn("report-recipient schedule lookup failed:", e.message);
  }
  return false;
}

exports.sendReportEmail = fns.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be logged in");

  const { companyId, recipient, period } = data;
  if (!companyId || !recipient) throw new functions.https.HttpsError("invalid-argument", "Missing companyId or recipient");
  // Company-scoped: caller must be signed in to THIS company (fixes cross-company
  // exfil) — any role, since report emailing isn't admin-only.
  const _rs = await _requireSession(data);
  if (_rs.companyId !== companyId) throw new functions.https.HttpsError("permission-denied", "Not authorized for this company.");

  // Strict recipient validation + allowlist — the report contains the company's
  // aggregate data, so it may only go to a known company address (company
  // contact, an operator of this company, or the signed-in caller), never an
  // arbitrary client-supplied destination.
  const recipientEmail = String(recipient).trim().toLowerCase();
  const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!EMAIL_RE.test(recipientEmail) || recipientEmail.length > 254) {
    throw new functions.https.HttpsError("invalid-argument", "Recipient is not a valid email address.");
  }
  if (!(await _isCompanyReportRecipient(companyId, recipientEmail, _rs.email))) {
    throw new functions.https.HttpsError("permission-denied",
      "Reports may only be emailed to a company contact or an operator of this company.");
  }

  const daysBack = period === "weekly" ? 7 : 1;
  const now = new Date();
  const startDate = new Date(now);
  startDate.setDate(startDate.getDate() - daysBack);
  startDate.setHours(0, 0, 0, 0);

  const sitesSnap = await db.collection(`companies/${companyId}/sites`).get();
  let totalWeighments = 0;
  let totalNet = 0;
  const totalVehicles = new Set();
  const materialTotals = {};

  for (const siteDoc of sitesSnap.docs) {
    const wbSnap = await db.collection(`companies/${companyId}/sites/${siteDoc.id}/weighbridges`).get();
    for (const wbDoc of wbSnap.docs) {
      const weighmentsSnap = await db
        .collection(`companies/${companyId}/sites/${siteDoc.id}/weighbridges/${wbDoc.id}/weighments`)
        .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(startDate))
        .where("status", "==", "completed")
        .get();

      for (const w of weighmentsSnap.docs) {
        const d = w.data();
        totalWeighments++;
        totalNet += (d.netWeight || 0);
        if (d.vehicleNumber) totalVehicles.add(d.vehicleNumber);
        const mat = d.material || "Unknown";
        materialTotals[mat] = (materialTotals[mat] || 0) + (d.netWeight || 0);
      }
    }
  }

  const periodLabel = period === "weekly" ? "Last 7 Days" : "Yesterday";
  const materialLines = Object.entries(materialTotals)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([m, v]) => `  • ${m}: ${(v / 1000).toFixed(1)} T`)
    .join("\n");

  const body = `
${BRAND.name} Report — ${periodLabel}
${"=".repeat(40)}

Total Weighments: ${totalWeighments}
Unique Vehicles: ${totalVehicles.size}
Net Tonnage: ${(totalNet / 1000).toFixed(1)} T

Top Materials:
${materialLines || "  No data"}

---
Generated: ${now.toLocaleString("en-IN", { timeZone: "Asia/Kolkata" })}
Requested by: ${_rs.email || "admin"}
  `.trim();

  const transporter = getMailTransporter();
  const senderEmail = _fnConfig().gmail?.email || process.env.GMAIL_EMAIL;
  await transporter.sendMail({
    from: `"${BRAND.name}" <${senderEmail}>`,
    to: recipientEmail,
    subject: `${BRAND.name} Report — ${periodLabel} (${totalWeighments} weighments, ${(totalNet / 1000).toFixed(1)}T)`,
    html: _buildReportEmailHtml(periodLabel, totalWeighments, totalVehicles.size, totalNet, materialTotals),
    text: body,
  });

  return { success: true, weighments: totalWeighments, tonnage: (totalNet / 1000).toFixed(1) };
});

// ═══════════════════════════════════════════════════════════════════════════════
// Address verification — postal PIN-mailer (Phase 1)
// On company creation a one-time code is generated and queued for a physical
// letter to the company's registered address. The user must enter it within a
// 30-day grace window to keep using the app. The plaintext code lives only in
// the server-only `mailers/{companyId}` doc (for printing); the client-readable
// `address_verifications/{companyId}` doc carries only status + the deadline.
// ═══════════════════════════════════════════════════════════════════════════════

const _ADDR_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I ambiguity
const _ADDR_GRACE_DAYS = 30;

function _genAddressCode(len = 8) {
  const bytes = require("crypto").randomBytes(len);
  let out = "";
  for (let i = 0; i < len; i++) out += _ADDR_ALPHABET[bytes[i] % _ADDR_ALPHABET.length];
  return out;
}

/**
 * Mirror the company admin into the operators collection so the admin appears
 * in the operator list and can process weighments. Idempotent: deterministic
 * doc id + email de-dupe, so it's safe to call from onCompanyCreated (new
 * accounts) and from the backfill (existing accounts), repeatedly.
 *
 * IMPORTANT: the doc MUST carry role:"companyAdmin". The client derives admin
 * privileges from that role (security_provider.currentUserRoleProvider), and
 * loginUser/SessionGuard both resolve the operators collection BEFORE the
 * company doc — so an admin-operator doc without this role would silently
 * demote the admin to a plain operator on their next login.
 *
 * @returns {Promise<"created"|"exists"|"no_email">}
 */
async function _ensureAdminOperator(companyId, companyData) {
  const data = companyData || {};
  const email = (data.email || "").trim().toLowerCase();
  // Without an email the admin can't be matched on login; nothing to mirror.
  if (!email) return "no_email";

  const opsRef = db.collection(`companies/${companyId}/operators`);
  const adminDocId = `admin_${companyId}`;

  // Idempotency 1: deterministic id.
  if ((await opsRef.doc(adminDocId).get()).exists) return "exists";
  // Idempotency 2: an admin operator for this email may already exist under a
  // different id (e.g. manually added). Don't create a duplicate.
  const dupe = await opsRef.where("email", "==", email).limit(1).get();
  if (!dupe.empty) return "exists";

  // Carry over the admin's DigiLocker-verified identity (stamped on the company
  // doc during onboarding) so the admin shows as a verified operator — these are
  // the exact fields the operator detail screen reads.
  const identity = {};
  for (const k of ["verificationMethod", "verifiedName", "verifiedPhotoUrl",
    "verifiedDob", "verifiedGender", "aadhaarLast4", "verifiedAddress"]) {
    if (data[k]) identity[k] = data[k];
  }

  await opsRef.doc(adminDocId).set({
    role: "companyAdmin", // CRITICAL — preserves admin privileges (see above).
    isCompanyAdmin: true, // Marker the UI uses to lock weighment permissions.
    name: data.contactName || data.verifiedName || data.name || "Administrator",
    email,
    phone: data.phone || "",
    companyId,
    uid: data.uid || data.adminUid || null,
    isActive: true,
    isVerified: true,
    idStatus: "verified",
    mustChangePassword: false,
    shiftRestricted: false,
    // Admin can always process weighments — these mirror that and are locked
    // in the UI. (isAdmin overrides them anyway, but keep them consistent.)
    canViewWeighments: true,
    canViewReports: true,
    canViewCustomers: true,
    ownWeighmentsOnly: false,
    // Visible across every site.
    siteScope: "all",
    allowedSites: [],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    source: "company_admin_auto",
    ...identity,
  });
  return "created";
}

exports.onCompanyCreated = fns.firestore
  .document("companies/{companyId}")
  .onCreate(async (snap, context) => {
    const { companyId } = context.params;
    const data = snap.data() || {};

    // Mirror the admin into the operators list (own idempotency; runs even if
    // address-verification was already provisioned, hence before the guard).
    try {
      await _ensureAdminOperator(companyId, data);
    } catch (e) {
      console.error("ensureAdminOperator failed for", companyId, e);
    }

    // Idempotency — never re-provision if it already exists.
    const avRef = db.collection("address_verifications").doc(companyId);
    if ((await avRef.get()).exists) return;

    const code = _genAddressCode(8);
    const now = admin.firestore.Timestamp.now();
    const graceUntil = admin.firestore.Timestamp.fromMillis(
      now.toMillis() + _ADDR_GRACE_DAYS * 24 * 60 * 60 * 1000,
    );
    const address = [data.address1, data.address2, data.state]
      .filter(Boolean).join(", ");

    // Client-readable (read-only via rules): drives the 30-day grace gate.
    await avRef.set({
      companyId,
      status: "pending",
      issuedAt: now,
      graceUntil,
      dispatchState: "queued",
      reissues: 0,
    });

    // Server-only: plaintext code (for printing) + salted hash (for verify).
    await db.collection("mailers").doc(companyId).set({
      companyId,
      companyName: data.name || "",
      address,
      code,
      cred: _makeCredential(code),
      attempts: 0,
      lockedUntil: null,
      dispatchState: "queued",
      createdAt: now,
    });

    // Welcome the new account (best-effort email + SMS).
    const companyName = data.name || "your company";
    await notifyContact({
      to: { email: data.email || null, phone: data.phone || null },
      companyId,
      subject: `Welcome to ${BRAND.name}`,
      notif: ({
        category: "welcome",
        link: "/dashboard",
        operatorEmail: data.email || null,
        heading: `Welcome to ${BRAND.name}`,
        intro: `Your ${BRAND.name} account for ${companyName} is ready. ` +
          `We've mailed a verification code to your registered address; enter it within ${_ADDR_GRACE_DAYS} days to keep your account active.`,
        rows: [["Company", companyName], ["Address verification", `${_ADDR_GRACE_DAYS}-day window`]],
        note: `Questions? Reach us at ${BRAND.support}.`,
      }),
    });
  });

exports.verifyAddressCode = fns.https.onCall(async (data, context) => {
  const companyId = String((data && data.companyId) || "").trim();
  const code = String((data && data.code) || "").trim().toUpperCase();
  if (!companyId || !code) {
    throw new functions.https.HttpsError("invalid-argument", "companyId and code are required.");
  }

  const avRef = db.collection("address_verifications").doc(companyId);
  const mailerRef = db.collection("mailers").doc(companyId);

  const avSnap = await avRef.get();
  if (avSnap.exists && avSnap.data().status === "verified") {
    return { verified: true, alreadyVerified: true };
  }

  const mailerSnap = await mailerRef.get();
  if (!mailerSnap.exists) {
    throw new functions.https.HttpsError("not-found", "No verification is pending for this company.");
  }
  const m = mailerSnap.data();

  const now = Date.now();
  if (m.lockedUntil && m.lockedUntil.toMillis() > now) {
    const mins = Math.ceil((m.lockedUntil.toMillis() - now) / 60000);
    throw new functions.https.HttpsError("resource-exhausted", `Too many attempts. Try again in ${mins} min.`);
  }

  if (!_verifyCredential(code, m.cred)) {
    const attempts = (m.attempts || 0) + 1;
    const update = { attempts };
    if (attempts >= 5) {
      update.lockedUntil = admin.firestore.Timestamp.fromMillis(now + 15 * 60 * 1000);
      update.attempts = 0;
    }
    await mailerRef.update(update);
    throw new functions.https.HttpsError("permission-denied", "Incorrect code. Please check the letter and try again.");
  }

  await avRef.set({
    status: "verified",
    verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  await mailerRef.update({
    attempts: 0,
    lockedUntil: null,
    code: null,
    verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { verified: true };
});

// Server-authoritative grace check (uses SERVER time — tamper-proof). Returns
// false for companies with no verification record (pre-feature accounts).
async function _addressGateLocked(companyId) {
  if (!companyId) return false;
  const snap = await db.collection("address_verifications").doc(companyId).get();
  if (!snap.exists) return false;
  const d = snap.data();
  if (d.status === "verified") return false;
  if (!d.graceUntil) return false;
  return Date.now() > d.graceUntil.toMillis();
}

// Lightweight callable the client consults when online to get the authoritative
// (server-time) locked state, overriding the device-clock fallback.
exports.checkAddressGate = fns.https.onCall(async (data, context) => {
  const companyId = String((data && data.companyId) || "").trim();
  const snap = companyId
    ? await db.collection("address_verifications").doc(companyId).get()
    : null;
  const d = snap && snap.exists ? snap.data() : null;
  return {
    locked: await _addressGateLocked(companyId),
    status: d ? (d.status || "pending") : "none",
    graceUntil: d && d.graceUntil ? d.graceUntil.toMillis() : null,
  };
});

// ── Gen-2 email document renderer (isolated; Chromium loads only in ITS own ──
// instances, never in the gen-1 functions above — see functions/email_render.js).
// ─── Scheduled: prune old in-app notifications (retention) ───────────────────
// Read notifications older than 30 days and unread older than 90 days are
// deleted per company, so the notification collection doesn't grow unbounded.
// (Uses the existing notifications (read, createdAt) composite index.)
exports.cleanupNotifications = fns.pubsub
  .schedule("every 24 hours")
  .timeZone("Asia/Kolkata")
  .onRun(async () => {
    const now = Date.now();
    const readCutoff = admin.firestore.Timestamp.fromMillis(now - 30 * 24 * 60 * 60 * 1000);
    const unreadCutoff = admin.firestore.Timestamp.fromMillis(now - 90 * 24 * 60 * 60 * 1000);
    const companies = await db.collection("companies").get();
    let removed = 0;
    for (const c of companies.docs) {
      const col = db.collection(`companies/${c.id}/notifications`);
      const oldRead = await col.where("read", "==", true).where("createdAt", "<", readCutoff).limit(250).get();
      const oldUnread = await col.where("read", "==", false).where("createdAt", "<", unreadCutoff).limit(250).get();
      if (oldRead.empty && oldUnread.empty) continue;
      const batch = db.batch();
      oldRead.forEach((d) => batch.delete(d.ref));
      oldUnread.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      removed += oldRead.size + oldUnread.size;
    }
    if (removed) console.log(`cleanupNotifications: removed ${removed} old notifications`);
    return null;
  });

// ── Gen-2 email document renderer (isolated; Chromium loads only in ITS own ──
// instances, never in the gen-1 functions above — see functions/email_render.js).
exports.renderEmailDoc = require("./email_render").renderEmailDoc;

// Storage-triggered: publishes the app-update feed when a release zip is uploaded.
exports.onReleaseUploaded = require("./release_publish").onReleaseUploaded;

// ── Daily: stamp every tulanam.com user's Google account photo with the brand ──
// wordmark. ENFORCE policy — overwrites custom photos too (chosen behaviour), so
// every account carries the brand mark no matter how the user was created.
// Runs as the gen-1 runtime SA (tulanam@appspot.gserviceaccount.com), which
// impersonates a Workspace super admin via KEYLESS domain-wide delegation:
// IAM signJwt mints an admin-scoped JWT, exchanged for a Directory API token —
// no service-account key is stored anywhere.
//
// One-time setup (see CLAUDE.md → Workspace user provisioning):
//   • Admin console → Domain-wide delegation: authorize SA client
//     113449181934687086088 for scope .../auth/admin.directory.user
//   • runtime SA holds roles/iam.serviceAccountTokenCreator on itself
//   • iamcredentials.googleapis.com enabled on the project
const _WORKSPACE_ADMIN_SUBJECT = "tech@tulanam.com";
const _DIRECTORY_SCOPE = "https://www.googleapis.com/auth/admin.directory.user";
const _BRAND_AVATAR_PATH = require("path").join(__dirname, "assets", "brand_avatar.png");

async function _gceMetadata(suffix) {
  const res = await fetch(`http://metadata.google.internal/computeMetadata/v1/${suffix}`, {
    headers: { "Metadata-Flavor": "Google" },
  });
  if (!res.ok) throw new Error(`metadata ${suffix} -> HTTP ${res.status}`);
  return (await res.text()).trim();
}

// Keyless domain-wide delegation: sign an admin-impersonating JWT with the
// runtime SA (IAM Credentials), then exchange it for a Directory access token.
async function _directoryAccessToken() {
  const saEmail = process.env.FUNCTION_IDENTITY
    || await _gceMetadata("instance/service-accounts/default/email");
  const saTokenJson = await _gceMetadata(
    "instance/service-accounts/default/token?scopes=https://www.googleapis.com/auth/cloud-platform");
  const saToken = JSON.parse(saTokenJson).access_token;

  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss: saEmail,
    sub: _WORKSPACE_ADMIN_SUBJECT,
    scope: _DIRECTORY_SCOPE,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const signRes = await fetch(
    `https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${encodeURIComponent(saEmail)}:signJwt`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${saToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ payload: JSON.stringify(claims) }),
    });
  const signJson = await signRes.json();
  if (!signRes.ok) {
    throw new Error(`signJwt failed (${signRes.status}) — is serviceAccountTokenCreator granted on `
      + `${saEmail}? ${JSON.stringify(signJson.error || signJson)}`);
  }

  const tokRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: signJson.signedJwt,
    }),
  });
  const tokJson = await tokRes.json();
  if (!tokRes.ok || !tokJson.access_token) {
    throw new Error(`JWT-bearer exchange failed (${tokRes.status}) — is domain-wide delegation `
      + `authorized for the SA client ID + scope? ${JSON.stringify(tokJson)}`);
  }
  return tokJson.access_token;
}

async function _listWorkspaceUsers(token) {
  const users = [];
  let pageToken = null;
  do {
    const url = new URL("https://admin.googleapis.com/admin/directory/v1/users");
    url.searchParams.set("customer", "my_customer");
    url.searchParams.set("domain", "tulanam.com");
    url.searchParams.set("maxResults", "200");
    url.searchParams.set("projection", "basic");
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    const json = await res.json();
    if (!res.ok) throw new Error(`users.list failed (${res.status}): ${JSON.stringify(json.error || json)}`);
    for (const u of (json.users || [])) users.push(u);
    pageToken = json.nextPageToken || null;
  } while (pageToken);
  return users;
}

exports.brandUserPhotos = fns.pubsub
  .schedule("every 24 hours")
  .timeZone("Asia/Kolkata")
  .onRun(async () => {
    const fs = require("fs");
    if (!fs.existsSync(_BRAND_AVATAR_PATH)) {
      throw new Error(`brand avatar not bundled at ${_BRAND_AVATAR_PATH}`);
    }
    // URL-safe Base64 with padding (GAM-style) — verified accepted by the API.
    const photoData = fs.readFileSync(_BRAND_AVATAR_PATH).toString("base64")
      .replace(/\+/g, "-").replace(/\//g, "_");

    const token = await _directoryAccessToken();
    const users = await _listWorkspaceUsers(token);
    const active = users.filter((u) => !u.suspended && !u.archived);

    // SAFE BY DEFAULT: until global/brandUserPhotos.enabled === true, this run
    // only mints the token, lists users, and records the blast radius — it
    // writes NO photos. This makes deploy + the first run non-destructive (the
    // cloud analog of the CLI's --check). Flip the flag to start enforcing; the
    // enforce policy then OVERWRITES every active user's photo daily.
    const cfgSnap = await db.collection("global").doc("brandUserPhotos").get();
    const enabled = cfgSnap.exists && cfgSnap.data().enabled === true;
    if (!enabled) {
      const sample = active.slice(0, 25).map((u) => u.primaryEmail);
      functions.logger.info(`brandUserPhotos DRY RUN (set global/brandUserPhotos.enabled=true `
        + `to enforce): token OK, would stamp ${active.length} active of ${users.length} users. `
        + `Sample: ${sample.join(", ")}`);
      await db.collection("global").doc("brandUserPhotos").set({
        lastDryRunAt: admin.firestore.FieldValue.serverTimestamp(),
        enabled: false, total: users.length, wouldStamp: active.length, sampleEmails: sample,
      }, { merge: true });
      return null;
    }

    let stamped = 0, failed = 0;
    const skipped = users.length - active.length; // suspended / archived
    const CHUNK = 5; // modest concurrency to stay well under Directory API quotas
    for (let i = 0; i < active.length; i += CHUNK) {
      const results = await Promise.allSettled(active.slice(i, i + CHUNK).map(async (u) => {
        const res = await fetch(
          `https://admin.googleapis.com/admin/directory/v1/users/${encodeURIComponent(u.id)}/photos/thumbnail`,
          {
            method: "PUT",
            headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
            body: JSON.stringify({ photoData }),
          });
        if (!res.ok) {
          const j = await res.json().catch(() => ({}));
          throw new Error(`${u.primaryEmail}: HTTP ${res.status} ${JSON.stringify(j.error || j)}`);
        }
        stamped++;
      }));
      for (const r of results) {
        if (r.status === "rejected") {
          failed++;
          functions.logger.warn(`brandUserPhotos: ${(r.reason && r.reason.message) || r.reason}`);
        }
      }
    }

    functions.logger.info(`brandUserPhotos: ${stamped} stamped, ${skipped} skipped (suspended), `
      + `${failed} failed, of ${users.length} users`);
    await db.collection("global").doc("brandUserPhotos").set({
      lastRunAt: admin.firestore.FieldValue.serverTimestamp(),
      enabled: true, total: users.length, stamped, skipped, failed,
    }, { merge: true });
    return null;
  });
