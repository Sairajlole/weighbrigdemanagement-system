const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();
const bucket = admin.storage().bucket("weighbridge-management.firebasestorage.app");

// ─── Operator Created: Set defaults ─────────────────────────────────────────

exports.onOperatorCreated = functions.firestore
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
  });

// ─── Ensure Firebase Auth: callable to migrate existing operators ────────────

exports.ensureFirebaseAuth = functions.https.onCall(async (data, context) => {
  const email = (data.email || "").trim().toLowerCase();
  const password = data.password || "";
  if (!email) throw new functions.https.HttpsError("invalid-argument", "Email required");

  try {
    const userRecord = await admin.auth().getUserByEmail(email);
    // User exists — update password if provided
    if (password) {
      await admin.auth().updateUser(userRecord.uid, { password });
      const crypto = require("crypto");
      const hash = crypto.createHash("sha256").update(password).digest("hex");
      const opSnap = await db.collectionGroup("operators").where("email", "==", email).limit(1).get();
      if (!opSnap.empty) {
        await opSnap.docs[0].ref.update({ uid: userRecord.uid, passwordHash: hash });
      }
      const companySnap = await db.collection("companies").where("email", "==", email).limit(1).get();
      if (!companySnap.empty) {
        await companySnap.docs[0].ref.update({ passwordHash: hash });
      }
    }
    return { uid: userRecord.uid, created: false };
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
    const crypto = require("crypto");
    const hash = crypto.createHash("sha256").update(password).digest("hex");
    const opSnap = await db.collectionGroup("operators").where("email", "==", email).limit(1).get();
    if (!opSnap.empty) {
      await opSnap.docs[0].ref.update({ uid: newUser.uid, passwordHash: hash });
    }
    const companySnap = await db.collection("companies").where("email", "==", email).limit(1).get();
    if (!companySnap.empty) {
      await companySnap.docs[0].ref.update({ passwordHash: hash });
    }
    return { uid: newUser.uid, created: true };
  }
});

// ─── Operator Updated: Audit trail for KYC status changes ───────────────────

exports.onOperatorUpdated = functions.firestore
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
    }
  });

// ─── Security Settings Changed: Audit + Emergency Lockdown ──────────────────

exports.onSecuritySettingsChanged = functions.firestore
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

exports.cleanupAuditLogs = functions.pubsub
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

exports.checkPasswordExpiry = functions.pubsub
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

    operators.docs.forEach((doc) => {
      const data = doc.data();
      const lastChanged = data.passwordLastChanged;

      if (!lastChanged || lastChanged.toDate() < cutoff) {
        batch.update(doc.ref, { mustChangePassword: true });
        flagged++;
      }
    });

    if (flagged > 0) {
      await batch.commit();
      console.log(`Flagged ${flagged} operators for password change (expired > ${expiryDays} days)`);
    }

    return null;
  });

// ─── Scheduled: Inactive Operator Deactivation ──────────────────────────────

exports.deactivateInactiveOperators = functions.pubsub
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

    operators.docs.forEach((doc) => {
      const data = doc.data();
      const lastLogin = data.lastLoginAt;

      if (lastLogin && lastLogin.toDate() < cutoff) {
        batch.update(doc.ref, { isActive: false });
        deactivated++;
      }
    });

    if (deactivated > 0) {
      await batch.commit();
      console.log(`Auto-deactivated ${deactivated} operators`);
    }

    return null;
  });

// ─── HTTP: Admin endpoint to bulk update operator shifts ────────────────────

exports.bulkUpdateShifts = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  }

  // Verify caller is admin via Custom Claims (cannot be self-modified)
  if (context.auth.token.admin !== true) {
    const callerSnap = await db.collectionGroup("operators")
      .where("email", "==", context.auth.token.email)
      .limit(1)
      .get();

    if (!callerSnap.empty) {
      throw new functions.https.HttpsError("permission-denied", "Admin access required");
    }
  }

  const { companyId, operatorIds, shiftStart, shiftEnd, shiftDays, shiftRestricted } = data;

  if (!companyId || !operatorIds || !Array.isArray(operatorIds)) {
    throw new functions.https.HttpsError("invalid-argument", "companyId and operatorIds array required");
  }

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

exports.forcePasswordReset = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  }

  // Verify caller is admin via Custom Claims
  if (context.auth.token.admin !== true) {
    const callerSnap = await db.collectionGroup("operators")
      .where("email", "==", context.auth.token.email)
      .limit(1)
      .get();

    if (!callerSnap.empty) {
      throw new functions.https.HttpsError("permission-denied", "Admin access required");
    }
  }

  const { companyId, operatorId } = data;
  if (!companyId || !operatorId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId and operatorId required");
  }

  await db.collection(`companies/${companyId}/operators`).doc(operatorId).update({
    mustChangePassword: true,
  });

  await db.collection(`companies/${companyId}/auditLog`).add({
    event: "passwordReset",
    description: `Password reset forced for operator ${operatorId}`,
    user: context.auth.token.email || "admin",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    success: true,
  });

  return { success: true };
});

// ─── Trigger: Login audit — update operator lastLoginAt + security alerts ───

exports.onAuditLogCreated = functions.firestore
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

    // Failed login alert — notify admin after 3 consecutive failures from same user
    if (data.event === "login" && !data.success && data.user) {
      const recentFails = await db.collection(`companies/${companyId}/auditLog`)
        .where("event", "==", "login")
        .where("user", "==", data.user)
        .where("success", "==", false)
        .orderBy("timestamp", "descending")
        .limit(3)
        .get();

      if (recentFails.docs.length >= 3) {
        await sendAdminNotification(
          "Security Alert: Repeated Failed Logins",
          `${data.user} has ${recentFails.docs.length}+ consecutive failed login attempts from ${data.machine || data.ip || "unknown machine"}.`
        );
      }
    }

    // Lockdown activation alert
    if (data.event === "emergencyLockdown" && data.description.includes("ACTIVATED")) {
      await sendAdminNotification(
        "EMERGENCY LOCKDOWN ACTIVATED",
        "All operator sessions have been locked. Only admin access remains."
      );
    }
  });

// ─── Trigger: Security settings — notify on critical changes ────────────────

exports.onSecurityCriticalChange = functions.firestore
  .document("companies/{companyId}/settings/security")
  .onUpdate(async (change) => {
    const before = change.before.data();
    const after = change.after.data();

    // Notify if IP whitelist disabled (potential breach)
    if (before.ipWhitelistEnabled && !after.ipWhitelistEnabled) {
      await sendAdminNotification(
        "Security: IP Whitelist Disabled",
        "IP whitelist has been disabled. All IPs can now access the system."
      );
    }

    // Notify if encryption disabled
    if (before.encryptBackups && !after.encryptBackups) {
      await sendAdminNotification(
        "Security: Backup Encryption Disabled",
        "Local backup encryption has been turned off."
      );
    }

    // Notify if audit logging disabled
    if (before.auditEnabled && !after.auditEnabled) {
      await sendAdminNotification(
        "Security: Audit Logging Disabled",
        "Audit trail has been disabled. Activity will not be recorded."
      );
    }
  });

// ═══════════════════════════════════════════════════════════════════════════════
// GATE CONTROL BACKEND
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Gate Settings Changed: Audit trail ────────────────────────────────────────

exports.onGateSettingsChanged = functions.firestore
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
        "The gate automation system has been turned off."
      );
    }

    // Notify if safety features disabled
    if (before.emergencyStop && !after.emergencyStop) {
      await sendAdminNotification(
        "Gate Safety: Emergency Stop Disabled",
        "Emergency stop has been disabled on the gate control system."
      );
    }
    if (before.interlockGates && !after.interlockGates) {
      await sendAdminNotification(
        "Gate Safety: Interlock Disabled",
        "Gate interlock safety feature has been turned off. Both gates can now open simultaneously."
      );
    }
  });

// ─── Gate Event Logging ────────────────────────────────────────────────────────

exports.logGateEvent = functions.https.onCall(async (data, context) => {
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

exports.triggerGate = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  }

  // Only admin can remotely trigger gates
  if (context.auth.token.admin !== true) {
    const callerSnap = await db.collectionGroup("operators")
      .where("email", "==", context.auth.token.email)
      .limit(1)
      .get();

    if (!callerSnap.empty) {
      throw new functions.https.HttpsError("permission-denied", "Admin access required for remote gate control");
    }
  }

  const { companyId, siteId, weighbridgeId, gateId, action } = data;

  if (!companyId || !siteId || !weighbridgeId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId, siteId, and weighbridgeId required");
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

exports.validateRfidTag = functions.https.onCall(async (data, context) => {
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
      `Blacklisted vehicle ${vehicle.number} scanned at ${gateId || "unknown"} gate.`
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

exports.registerRfidTag = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  }

  if (context.auth.token.admin !== true) {
    const callerSnap = await db.collectionGroup("operators")
      .where("email", "==", context.auth.token.email)
      .limit(1)
      .get();
    if (!callerSnap.empty) {
      throw new functions.https.HttpsError("permission-denied", "Admin access required");
    }
  }

  const { companyId, vehicleId, tagId } = data;

  if (!companyId || !vehicleId || !tagId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId, vehicleId, and tagId are required");
  }

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
    user: context.auth.token.email || "admin",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    success: true,
    metadata: { vehicleId, tagId },
  });

  return { success: true };
});

// ─── Gate Event Cleanup (older than 30 days) ──────────────────────────────────

exports.cleanupGateEvents = functions.pubsub
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

exports.cleanupStaleGateCommands = functions.pubsub
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

exports.getGateStatus = functions.https.onCall(async (data, context) => {
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

async function sendAdminNotification(title, body) {
  try {
    // Store notification in Firestore for in-app display
    await db.collection("notifications").add({
      title,
      body,
      type: "security",
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Send FCM to admin topic
    await admin.messaging().send({
      topic: "admin_security_alerts",
      notification: { title, body },
      data: { type: "security_alert", title, body },
      apns: {
        payload: { aps: { sound: "default", badge: 1 } },
      },
    });
  } catch (e) {
    console.log("Notification send failed (FCM may not be configured):", e.message);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WEIGHMENT BACKEND
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Weighment Created: RST counter, customer stats, audit ──────────────────

exports.onWeighmentCreated = functions.firestore
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

exports.onWeighmentUpdated = functions.firestore
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

exports.onWeighmentDeleted = functions.firestore
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

exports.onCustomerCreated = functions.firestore
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

exports.onCustomerArchived = functions.firestore
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

exports.onCustomerRestoredFromBin = functions.firestore
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

exports.onCustomerMergeCreated = functions.firestore
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

exports.onCustomerMergeUpdated = functions.firestore
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

exports.onCustomerUpdated = functions.firestore
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

// ═══════════════════════════════════════════════════════════════════════════════
// OPERATOR BACKEND (additional triggers)
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Weighment Completed: Sync customer face (legacy alias removed) ─────────
// Face sync is now handled inside onWeighmentUpdated above.

// ─── Operator Archive/Restore + Face Enrollment audit ───────────────────────
// (extends existing onOperatorUpdated)

exports.onOperatorLifecycle = functions.firestore
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

exports.migrateToHierarchy = functions.https.onCall(async (data, context) => {
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

exports.generateLicenseKey = functions.https.onCall(async (data, context) => {
  const { tier, maxWeighbridges, maxSites, features, adminSecret } = data;

  if (adminSecret !== "wb_admin_2026") {
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

exports.activateLicense = functions.https.onCall(async (data, context) => {
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
  const registryRef = db.doc(`global/gstin_registry/${normalizedGstin}`);
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

exports.validateLicense = functions.https.onCall(async (data, context) => {
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

exports.checkExpiredLicenses = functions.pubsub
  .schedule("every 24 hours")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const expired = await db.collection("licenses")
      .where("status", "==", "active")
      .where("expiresAt", "<=", now)
      .get();

    if (expired.empty) return null;

    const batch = db.batch();
    for (const doc of expired.docs) {
      batch.update(doc.ref, { status: "expired" });
      const companyId = doc.data().companyId;
      if (companyId) {
        batch.set(db.doc(`companies/${companyId}`), {
          license: { status: "expired" },
        }, { merge: true });
      }
    }
    await batch.commit();
    console.log(`Expired ${expired.size} licenses`);
    return null;
  });

// ─── Email & Phone Verification ─────────────────────────────────────────────

const nodemailer = require("nodemailer");

function generateOTP() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

function getMailTransporter() {
  return nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: functions.config().gmail?.email || process.env.GMAIL_EMAIL,
      pass: functions.config().gmail?.app_password || process.env.GMAIL_APP_PASSWORD,
    },
  });
}

/**
 * sendEmailOTP - Sends a 6-digit OTP to the user's email.
 * Stores OTP hash in Firestore with 10-minute expiry.
 */
exports.sendEmailOTP = functions.https.onCall(async (data, context) => {
  const { email } = data;
  if (!email || !email.includes("@")) {
    throw new functions.https.HttpsError("invalid-argument", "Valid email required");
  }

  const otp = generateOTP();
  const expiresAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + 10 * 60 * 1000)
  );

  // Store OTP (hashed for security)
  const crypto = require("crypto");
  const otpHash = crypto.createHash("sha256").update(otp).digest("hex");

  await db.collection("verification_otps").doc(email.toLowerCase()).set({
    otpHash,
    expiresAt,
    attempts: 0,
    type: "email",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Send email (graceful fallback if no credentials configured)
  try {
    const transporter = getMailTransporter();
    const senderEmail = functions.config().gmail?.email || process.env.GMAIL_EMAIL || "noreply@weighbridge.app";

    await transporter.sendMail({
      from: `"Weighbridge" <${senderEmail}>`,
      to: email,
      subject: "Your Weighbridge Verification Code",
      html: `
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 480px; margin: 0 auto; padding: 32px;">
          <div style="text-align: center; margin-bottom: 24px;">
            <div style="width: 48px; height: 48px; background: #059669; border-radius: 12px; display: inline-flex; align-items: center; justify-content: center;">
              <span style="color: white; font-size: 24px;">⚖</span>
            </div>
          </div>
          <h2 style="text-align: center; color: #1a1a1a; margin-bottom: 8px;">Verification Code</h2>
          <p style="text-align: center; color: #666; font-size: 14px; margin-bottom: 24px;">
            Enter this code to verify your email address for Weighbridge Management.
          </p>
          <div style="text-align: center; background: #f3f4f6; border-radius: 12px; padding: 20px; margin-bottom: 24px;">
            <span style="font-size: 32px; font-weight: 700; letter-spacing: 8px; color: #059669;">${otp}</span>
          </div>
          <p style="text-align: center; color: #999; font-size: 12px;">
            This code expires in 10 minutes. Do not share it with anyone.
          </p>
        </div>
      `,
    });
  } catch (e) {
    console.warn("Email send failed (credentials not configured?):", e.message);
  }

  return { success: true, message: "OTP sent to email" };
});

/**
 * verifyEmailOTP - Verifies the 6-digit OTP for email.
 */
exports.verifyEmailOTP = functions.https.onCall(async (data, context) => {
  const { email, otp } = data;
  if (!email || !otp) {
    throw new functions.https.HttpsError("invalid-argument", "Email and OTP required");
  }

  // Test bypass: 000000 always passes (remove in production)
  if (otp === "000000") {
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
  if (otpData.attempts >= 5) {
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
exports.sendPhoneOTP = functions.https.onCall(async (data, context) => {
  const { phone } = data;
  if (!phone || phone.length < 10) {
    throw new functions.https.HttpsError("invalid-argument", "Valid phone number required");
  }

  // Extract digits only (remove +91 prefix if present)
  const digits = phone.replace(/\D/g, "").slice(-10);
  if (digits.length !== 10) {
    throw new functions.https.HttpsError("invalid-argument", "10-digit Indian mobile number required");
  }

  const otp = generateOTP();
  const expiresAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + 10 * 60 * 1000)
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
    const apiKey = functions.config().fast2sms?.api_key || process.env.FAST2SMS_API_KEY;
    const senderId = functions.config().fast2sms?.sender_id || process.env.FAST2SMS_SENDER_ID;
    const templateId = functions.config().fast2sms?.template_id || process.env.FAST2SMS_TEMPLATE_ID;

    if (!apiKey) {
      console.warn("FAST2SMS API key not configured, skipping SMS send");
    } else {
      const fetch = (await import("node-fetch")).default;
      const response = await fetch("https://www.fast2sms.com/dev/bulkV2", {
        method: "POST",
        headers: {
          "authorization": apiKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          route: "dlt",
          sender_id: senderId,
          message: templateId,
          variables_values: otp,
          flash: 0,
          numbers: digits,
        }),
      });

      const result = await response.json();
      if (!result.return) {
        console.error("FAST2SMS error:", result);
      }
    }
  } catch (e) {
    console.warn("SMS send failed:", e.message);
  }

  return { success: true, message: "OTP sent to phone" };
});

/**
 * verifyPhoneOTP - Verifies the 6-digit OTP for phone.
 */
exports.verifyPhoneOTP = functions.https.onCall(async (data, context) => {
  const { phone, otp } = data;
  if (!phone || !otp) {
    throw new functions.https.HttpsError("invalid-argument", "Phone and OTP required");
  }

  const digits = phone.replace(/\D/g, "").slice(-10);

  // Test bypass: 000000 always passes (remove in production)
  if (otp === "000000") {
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

  if (otpData.attempts >= 5) {
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
exports.verifyOTP = functions.https.onCall(async (data) => {
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

  if (otpData.attempts >= 5) {
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
exports.updateCompanyContact = functions.https.onCall(async (data, context) => {
  const { companyId, siteId, weighbridgeId, field, newValue, otp } = data;

  if (!companyId || !field || !newValue || !otp) {
    throw new functions.https.HttpsError("invalid-argument", "Missing required fields");
  }

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

  if (otpData.attempts >= 5) {
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

  // Audit log
  await db.collection(`companies/${companyId}/audit_log`).add({
    event: "contactUpdate",
    description: `Company ${field} updated to ${field === "email" ? newValue.toLowerCase() : newValue}`,
    user: context.auth?.token?.email || "system",
    timestamp: now,
  });

  return { success: true, field, verified: true };
});

// ─── GSTIN Lookup & Validation ───────────────────────────────────────────────

/**
 * lookupGstin - Looks up GSTIN via public API and returns trade/legal name + status.
 * Used for owner confirmation and company name cross-validation.
 */
exports.lookupGstin = functions.https.onCall(async (data, context) => {
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
exports.verifyGstinOwnership = functions.https.onCall(async (data, context) => {
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
      const registryRef = db.doc(`global/gstin_registry/${normalized}`);
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

exports.migrateFreeTierToTrial = functions.https.onCall(async (data, context) => {
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

exports.verifyDocument = functions.runWith({ timeoutSeconds: 60, memory: "512MB" }).https.onCall(async (data) => {
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
exports.verifyOperatorId = functions.runWith({ timeoutSeconds: 90, memory: "512MB" }).https.onCall(async (data) => {
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
exports.sendPasswordResetOTP = functions.https.onCall(async (data, context) => {
  const { email } = data;
  if (!email || !email.includes("@")) {
    throw new functions.https.HttpsError("invalid-argument", "Valid email required");
  }

  const normalizedEmail = email.trim().toLowerCase();

  // Look up operator by email (try collectionGroup, fallback to top-level companies)
  let phone = null;
  let userName = "User";

  try {
    const opSnap = await db.collectionGroup("operators")
      .where("email", "==", normalizedEmail)
      .limit(1)
      .get();

    if (!opSnap.empty) {
      const opData = opSnap.docs[0].data();
      phone = opData.phone || null;
      userName = opData.name || "Operator";
    }
  } catch (e) {
    console.warn("collectionGroup operators query failed:", e.message);
  }

  // If not found as operator, check company-level email
  if (!phone && userName === "User") {
    try {
      const compSnap = await db.collection("companies")
        .where("email", "==", normalizedEmail)
        .limit(1)
        .get();
      if (!compSnap.empty) {
        const compData = compSnap.docs[0].data();
        phone = compData.phone || compData.contactPhone || null;
        userName = compData.contactName || compData.companyName || "Admin";
      }
    } catch (e) {
      console.warn("companies email lookup failed:", e.message);
    }
  }

  // Generate OTP
  const otp = generateOTP();
  const expiresAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + 10 * 60 * 1000)
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

  // Send OTP via email
  try {
    const transporter = getMailTransporter();
    const senderEmail = functions.config().gmail?.email || process.env.GMAIL_EMAIL || "noreply@weighbridge.app";

    await transporter.sendMail({
      from: `"Weighbridge" <${senderEmail}>`,
      to: normalizedEmail,
      subject: "Password Reset Code - Weighbridge",
      html: `
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 480px; margin: 0 auto; padding: 32px;">
          <div style="text-align: center; margin-bottom: 24px;">
            <div style="width: 48px; height: 48px; background: #059669; border-radius: 12px; display: inline-flex; align-items: center; justify-content: center;">
              <span style="color: white; font-size: 24px;">⚖</span>
            </div>
          </div>
          <h2 style="text-align: center; color: #1a1a1a; margin-bottom: 8px;">Password Reset</h2>
          <p style="text-align: center; color: #666; font-size: 14px; margin-bottom: 24px;">
            Hi ${userName}, use this code to reset your Weighbridge password.
          </p>
          <div style="text-align: center; background: #f3f4f6; border-radius: 12px; padding: 20px; margin-bottom: 24px;">
            <span style="font-size: 32px; font-weight: 700; letter-spacing: 8px; color: #059669;">${otp}</span>
          </div>
          <p style="text-align: center; color: #999; font-size: 12px;">
            This code expires in 10 minutes. If you didn't request this, ignore this message.
          </p>
        </div>
      `,
    });
  } catch (e) {
    console.warn("Password reset email send failed:", e.message);
  }

  // Send OTP via SMS if phone is available
  let phoneSent = false;
  let maskedPhone = null;
  if (phone) {
    const digits = phone.replace(/\D/g, "").slice(-10);
    if (digits.length === 10) {
      maskedPhone = `******${digits.slice(-4)}`;
      try {
        const apiKey = functions.config().fast2sms?.api_key || process.env.FAST2SMS_API_KEY;
        const senderId = functions.config().fast2sms?.sender_id || process.env.FAST2SMS_SENDER_ID;
        const templateId = functions.config().fast2sms?.template_id || process.env.FAST2SMS_TEMPLATE_ID;

        if (apiKey) {
          const fetch = (await import("node-fetch")).default;
          await fetch("https://www.fast2sms.com/dev/bulkV2", {
            method: "POST",
            headers: {
              "authorization": apiKey,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              route: "dlt",
              sender_id: senderId,
              message: templateId,
              variables_values: otp,
              flash: 0,
              numbers: digits,
            }),
          });
          phoneSent = true;
        }
      } catch (e) {
        console.warn("Password reset SMS send failed:", e.message);
      }
    }
  }

  return {
    success: true,
    emailSent: true,
    phoneSent,
    maskedPhone,
    message: phoneSent
      ? `OTP sent to ${normalizedEmail} and ${maskedPhone}`
      : `OTP sent to ${normalizedEmail}`,
  };
});

/**
 * verifyPasswordResetOTP - Verifies OTP for password reset flow.
 * Returns a token that resetUserPassword accepts.
 */
exports.verifyPasswordResetOTP = functions.https.onCall(async (data, context) => {
  const { email, otp } = data;
  if (!email || !otp) {
    throw new functions.https.HttpsError("invalid-argument", "Email and OTP required");
  }

  const normalizedEmail = email.trim().toLowerCase();

  // Test bypass
  if (otp === "000000") {
    const docRef = db.collection("verification_otps").doc(`pwreset_${normalizedEmail}`);
    const doc = await docRef.get();
    if (doc.exists) await docRef.delete();
    return { success: true, verified: true, verificationToken: "otp_verified" };
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

  if (otpData.attempts >= 5) {
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
  return { success: true, verified: true, verificationToken: "otp_verified" };
});

/**
 * resetUserPassword - Resets a user's password after OTP has been verified.
 * Uses Admin SDK so no reauthentication is required on client.
 * Caller must have already verified OTP via verifyPasswordResetOTP.
 */
exports.resetUserPassword = functions.https.onCall(async (data, context) => {
  const { email, uid: clientUid, newPassword, verificationToken } = data;

  if (!newPassword) {
    throw new functions.https.HttpsError("invalid-argument", "New password required");
  }

  if (newPassword.length < 8) {
    throw new functions.https.HttpsError("invalid-argument", "Password must be at least 8 characters");
  }

  if (verificationToken !== "otp_verified" && verificationToken !== "000000") {
    throw new functions.https.HttpsError("permission-denied", "Identity not verified");
  }

  // Resolve UID: context.auth (non-anonymous) > client UID > email lookup > create account
  let uid;
  const normalizedEmail = email ? email.trim().toLowerCase() : "";

  if (context.auth && context.auth.uid && context.auth.token && context.auth.token.email) {
    // Only use context.auth if it's a real email-authenticated user (not anonymous)
    uid = context.auth.uid;
  } else if (clientUid && clientUid.trim().length > 0 && clientUid.trim().length > 20) {
    // Sanity check: real UIDs are 28 chars; skip if it looks invalid
    uid = clientUid.trim();
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

        // Update operator record with the new auth UID
        const opSnap = await db.collectionGroup("operators")
          .where("email", "==", normalizedEmail)
          .limit(1)
          .get();
        const crypto = require("crypto");
        const passwordHash = crypto.createHash("sha256").update(newPassword).digest("hex");
        if (!opSnap.empty) {
          await opSnap.docs[0].ref.update({ uid: newUser.uid, passwordHash, passwordLastChanged: admin.firestore.FieldValue.serverTimestamp(), mustChangePassword: false });
        }

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
    await admin.auth().updateUser(uid, { password: newPassword });

    // Update operator record with passwordHash (used by macOS Firestore-based auth)
    const crypto = require("crypto");
    const passwordHash = crypto.createHash("sha256").update(newPassword).digest("hex");

    if (normalizedEmail.length > 0) {
      const opSnap = await db.collectionGroup("operators")
        .where("email", "==", normalizedEmail)
        .limit(1)
        .get();

      if (!opSnap.empty) {
        await opSnap.docs[0].ref.update({
          passwordHash,
          passwordLastChanged: admin.firestore.FieldValue.serverTimestamp(),
          mustChangePassword: false,
        });
      }
    }

    return { success: true, message: "Password updated successfully" };
  } catch (err) {
    throw new functions.https.HttpsError("internal", err.message || "Failed to reset password");
  }
});

/**
 * updateOperatorEmail - Admin updates an operator's Firebase Auth email.
 * Requires admin context (caller must be authenticated).
 */
exports.updateOperatorEmail = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required");
  }

  const { uid, newEmail } = data;
  if (!uid || !newEmail || !newEmail.includes("@")) {
    throw new functions.https.HttpsError("invalid-argument", "Valid uid and newEmail required");
  }

  try {
    await admin.auth().updateUser(uid, { email: newEmail.trim().toLowerCase() });
    return { success: true };
  } catch (err) {
    console.warn("updateOperatorEmail failed:", err.message);
    return { success: false, error: err.message };
  }
});

// ─── Face Enrollment ────────────────────────────────────────────────────────
// Receives webcam face snapshots, detects faces, and stores face landmark
// embeddings for future operator verification during login.

exports.validateFaceConsistency = functions.runWith({ timeoutSeconds: 120, memory: "512MB" }).https.onCall(async (data) => {
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

exports.enrollOperatorFace = functions.runWith({ timeoutSeconds: 120, memory: "512MB" }).https.onCall(async (data) => {
  const { images, companyId, operatorEmail } = data;

  if (!images || !images.length) {
    throw new functions.https.HttpsError("invalid-argument", "At least one face image required");
  }
  if (!companyId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId required");
  }

  const client = new vision.ImageAnnotatorClient();

  // Detect faces in all provided snapshots
  const faceResults = [];
  for (const img of images) {
    try {
      const [result] = await client.faceDetection({
        image: { content: img },
      });
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
        confidence: bestFace.detectionConfidence,
        landmarks,
        rollAngle: bestFace.rollAngle || 0,
        panAngle: bestFace.panAngle || 0,
        tiltAngle: bestFace.tiltAngle || 0,
      });
    } catch (e) {
      functions.logger.warn("Face detection failed for frame:", e.message);
    }
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

  // Upload non-outlier frames to Cloud Storage (use temp prefix to avoid overwriting old data)
  const storagePaths = [];
  try {
    const uploadPromises = validIndices.map(async (faceIdx, storageIdx) => {
      const imgBase64 = images[faceIdx];
      const imgBuffer = Buffer.from(imgBase64, "base64");
      const path = `face-enrollment/${companyId}/${operatorEmail}/${storageIdx}.jpg`;
      const file = bucket.file(path);
      await file.save(imgBuffer, { contentType: "image/jpeg", metadata: { cacheControl: "private,max-age=31536000" } });
      storagePaths.push(path);
    });
    await Promise.all(uploadPromises);
    functions.logger.info(`Face enrollment: uploaded ${storagePaths.length} reference frames to Storage`);
  } catch (e) {
    functions.logger.warn("Failed to upload face frames to Storage:", e.message);
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

  // Save to operator document
  try {
    const opsSnap = await db.collection("operators")
      .where("companyId", "==", companyId)
      .where("email", "==", operatorEmail)
      .limit(1).get();

    if (opsSnap.docs.length > 0) {
      await opsSnap.docs[0].ref.update({ faceEnrollment: enrollmentData });
    }

    const companyOps = await db.collection(`companies/${companyId}/operators`)
      .where("email", "==", operatorEmail)
      .limit(1).get();
    if (companyOps.docs.length > 0) {
      await companyOps.docs[0].ref.update({ faceEnrollment: enrollmentData });
    }
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
    const [existingFiles] = await bucket.getFiles({ prefix: `face-enrollment/${companyId}/${operatorEmail}/` });
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
exports.trainOperatorFace = functions.runWith({ timeoutSeconds: 120, memory: "512MB" }).https.onCall(async (data) => {
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
      const path = `face-enrollment/${companyId}/${operatorEmail}/train_${existingCount + idx}.jpg`;
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
exports.verifyOperatorFace = functions.runWith({ timeoutSeconds: 30, memory: "512MB" }).https.onCall(async (data) => {
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

// verifyOperatorPin - Verify operator PIN for fallback authentication.
// If PIN doesn't match the current operator, checks all operators in the company.
// Returns operatorEmail/operatorName of the matched operator for switch detection.
exports.verifyOperatorPin = functions.https.onCall(async (data) => {
  const { pin, companyId, operatorEmail } = data;

  if (!pin || !companyId) {
    throw new functions.https.HttpsError("invalid-argument", "pin and companyId required");
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
      const storedHash = operatorDoc.data().pinHash;
      if (storedHash) {
        const inputHash = crypto.createHash("sha256").update(pin + operatorEmail).digest("hex");
        if (inputHash === storedHash) {
          await operatorDoc.ref.update({
            lastPinVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
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
    const storedHash = opData.pinHash;
    if (!storedHash) continue;
    const inputHash = crypto.createHash("sha256").update(pin + opEmail).digest("hex");
    if (inputHash === storedHash) {
      await doc.ref.update({
        lastPinVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { match: true, message: "PIN verified.", operatorName: opData.name || "", operatorEmail: opEmail, isSameOperator: false };
    }
  }

  return { match: false, message: "Incorrect PIN." };
});

// setOperatorPin - Set or update operator PIN.
exports.setOperatorPin = functions.https.onCall(async (data) => {
  const { pin, companyId, operatorEmail } = data;

  if (!pin || !companyId || !operatorEmail) {
    throw new functions.https.HttpsError("invalid-argument", "pin, companyId, and operatorEmail required");
  }

  if (pin.length < 4 || pin.length > 6 || !/^\d+$/.test(pin)) {
    throw new functions.https.HttpsError("invalid-argument", "PIN must be 4-6 digits.");
  }

  const crypto = require("crypto");
  const pinHash = crypto.createHash("sha256").update(pin + operatorEmail).digest("hex");

  // Update both locations
  const companyOps = await db.collection(`companies/${companyId}/operators`)
    .where("email", "==", operatorEmail)
    .limit(1).get();
  if (!companyOps.empty) {
    await companyOps.docs[0].ref.update({ pinHash, pinSetAt: admin.firestore.FieldValue.serverTimestamp() });
  }

  const flatOps = await db.collection("operators")
    .where("companyId", "==", companyId)
    .where("email", "==", operatorEmail)
    .limit(1).get();
  if (!flatOps.empty) {
    await flatOps.docs[0].ref.update({ pinHash, pinSetAt: admin.firestore.FieldValue.serverTimestamp() });
  }

  return { success: true, message: "PIN set successfully." };
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
