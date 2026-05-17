const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// ─── Operator Created: Set defaults ─────────────────────────────────────────

exports.onOperatorCreated = functions.firestore
  .document("operators/{operatorId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const defaults = {};

    if (!data.createdAt) defaults.createdAt = admin.firestore.FieldValue.serverTimestamp();
    if (!data.isActive) defaults.isActive = true;
    if (!data.isVerified) defaults.isVerified = false;
    if (!data.idStatus) defaults.idStatus = "not_submitted";
    if (!data.loginCount) defaults.loginCount = 0;
    if (data.mustChangePassword === undefined) defaults.mustChangePassword = true;
    if (!data.shiftRestricted) defaults.shiftRestricted = false;

    if (Object.keys(defaults).length > 0) {
      await snap.ref.update(defaults);
    }
  });

// ─── Operator Updated: Audit trail for KYC status changes ───────────────────

exports.onOperatorUpdated = functions.firestore
  .document("operators/{operatorId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Log KYC status change
    if (before.idStatus !== after.idStatus) {
      await db.collection("auditLog").add({
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
      await db.collection("auditLog").add({
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
      await db.collection("auditLog").add({
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
  .document("settings/security")
  .onUpdate(async (change, context) => {
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
      await db.collection("auditLog").add({
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
      await db.collection("auditLog").add({
        event: "emergencyLockdown",
        description: "Emergency lockdown ACTIVATED — all operator sessions locked",
        user: "admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
      });
    }

    if (before.emergencyLockdown && !after.emergencyLockdown) {
      await db.collection("auditLog").add({
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
    const secDoc = await db.collection("settings").doc("security").get();
    if (!secDoc.exists) return null;

    const settings = secDoc.data();
    const retentionDays = settings.auditRetentionDays || 365;
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - retentionDays);

    const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoff);
    const batch = db.batch();
    let count = 0;

    const snap = await db.collection("auditLog")
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
    const secDoc = await db.collection("settings").doc("security").get();
    if (!secDoc.exists) return null;

    const settings = secDoc.data();
    const expiryDays = settings.passwordExpiryDays || 0;
    if (expiryDays === 0) return null;

    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - expiryDays);
    const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoff);

    const operators = await db.collection("operators")
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
    cutoff.setDate(cutoff.getDate() - 90); // 90 days inactive
    const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoff);

    const operators = await db.collection("operators")
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

      await db.collection("auditLog").add({
        event: "autoDeactivation",
        description: `${deactivated} operators auto-deactivated (90+ days inactive)`,
        user: "system",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
      });

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
    // Fallback: check if user is NOT in operators collection (owner/admin account)
    const callerSnap = await db.collection("operators")
      .where("email", "==", context.auth.token.email)
      .limit(1)
      .get();

    if (!callerSnap.empty) {
      throw new functions.https.HttpsError("permission-denied", "Admin access required");
    }
  }

  const { operatorIds, shiftStart, shiftEnd, shiftDays, shiftRestricted } = data;

  if (!operatorIds || !Array.isArray(operatorIds)) {
    throw new functions.https.HttpsError("invalid-argument", "operatorIds must be an array");
  }

  const batch = db.batch();
  for (const id of operatorIds) {
    const ref = db.collection("operators").doc(id);
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
    const callerSnap = await db.collection("operators")
      .where("email", "==", context.auth.token.email)
      .limit(1)
      .get();

    if (!callerSnap.empty) {
      throw new functions.https.HttpsError("permission-denied", "Admin access required");
    }
  }

  const { operatorId } = data;
  if (!operatorId) {
    throw new functions.https.HttpsError("invalid-argument", "operatorId required");
  }

  await db.collection("operators").doc(operatorId).update({
    mustChangePassword: true,
  });

  await db.collection("auditLog").add({
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
  .document("auditLog/{logId}")
  .onCreate(async (snap) => {
    const data = snap.data();

    // Update operator login stats
    if (data.event === "login" && data.success) {
      const email = data.user;
      if (email && email !== "unknown") {
        const opSnap = await db.collection("operators")
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
      const recentFails = await db.collection("auditLog")
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
  .document("settings/security")
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
  .document("settings/gateControl")
  .onUpdate(async (change, context) => {
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

    await db.collection("auditLog").add({
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

  const { gateId, action, success, message, weighmentId, vehicleNumber, rfidTag, responseTimeMs } = data;

  if (!gateId || !action) {
    throw new functions.https.HttpsError("invalid-argument", "gateId and action are required");
  }

  const validActions = ["open", "close", "test", "emergency_stop", "auto_close", "rfid_trigger"];
  if (!validActions.includes(action)) {
    throw new functions.https.HttpsError("invalid-argument", `Invalid action: ${action}`);
  }

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

  await db.collection("gateEvents").add(event);

  // Also log to main audit log for critical actions
  if (action === "emergency_stop" || (!success && action !== "test")) {
    await db.collection("auditLog").add({
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
    const callerSnap = await db.collection("operators")
      .where("email", "==", context.auth.token.email)
      .limit(1)
      .get();

    if (!callerSnap.empty) {
      throw new functions.https.HttpsError("permission-denied", "Admin access required for remote gate control");
    }
  }

  const { gateId, action } = data;

  if (!gateId || !["entry", "exit"].includes(gateId)) {
    throw new functions.https.HttpsError("invalid-argument", "gateId must be 'entry' or 'exit'");
  }
  if (!action || !["open", "close"].includes(action)) {
    throw new functions.https.HttpsError("invalid-argument", "action must be 'open' or 'close'");
  }

  // Load current gate config
  const configDoc = await db.collection("settings").doc("gateControl").get();
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
    const recentEvents = await db.collection("gateEvents")
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
  await db.collection("gateCommands").add({
    gateId,
    action,
    requestedBy: context.auth.token.email || "admin",
    status: "pending",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Log the remote trigger
  await db.collection("gateEvents").add({
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

  const { tagId, gateId } = data;

  if (!tagId) {
    throw new functions.https.HttpsError("invalid-argument", "tagId is required");
  }

  // Check gate config
  const configDoc = await db.collection("settings").doc("gateControl").get();
  if (!configDoc.exists || !configDoc.data().rfidEnabled) {
    return { valid: false, reason: "RFID not enabled" };
  }

  // Look up tag in registered vehicles
  const vehicleSnap = await db.collection("vehicles")
    .where("rfidTag", "==", tagId)
    .where("active", "==", true)
    .limit(1)
    .get();

  if (vehicleSnap.empty) {
    // Log failed RFID scan
    await db.collection("gateEvents").add({
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
    await db.collection("gateEvents").add({
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
  await db.collection("gateEvents").add({
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
    const callerSnap = await db.collection("operators")
      .where("email", "==", context.auth.token.email)
      .limit(1)
      .get();
    if (!callerSnap.empty) {
      throw new functions.https.HttpsError("permission-denied", "Admin access required");
    }
  }

  const { vehicleId, tagId } = data;

  if (!vehicleId || !tagId) {
    throw new functions.https.HttpsError("invalid-argument", "vehicleId and tagId are required");
  }

  // Check tag not already assigned
  const existing = await db.collection("vehicles")
    .where("rfidTag", "==", tagId)
    .limit(1)
    .get();

  if (!existing.empty && existing.docs[0].id !== vehicleId) {
    throw new functions.https.HttpsError(
      "already-exists",
      `Tag already assigned to vehicle ${existing.docs[0].data().number}`
    );
  }

  await db.collection("vehicles").doc(vehicleId).update({
    rfidTag: tagId,
    rfidRegisteredAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await db.collection("auditLog").add({
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

    const snap = await db.collection("gateEvents")
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
    cutoff.setMinutes(cutoff.getMinutes() - 5); // Commands older than 5 min are stale
    const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoff);

    const batch = db.batch();
    let count = 0;

    const snap = await db.collection("gateCommands")
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

  // Get config
  const configDoc = await db.collection("settings").doc("gateControl").get();
  const config = configDoc.exists ? configDoc.data() : {};

  // Get last events for each gate
  const [entryEvents, exitEvents] = await Promise.all([
    db.collection("gateEvents")
      .where("gateId", "==", "entry")
      .where("success", "==", true)
      .orderBy("timestamp", "desc")
      .limit(5)
      .get(),
    db.collection("gateEvents")
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

  const todayEvents = await db.collection("gateEvents")
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
  .document("weighments/{weighmentId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const updates = {};

    // Auto-assign RST number if not already set
    if (!data.rst) {
      const counterRef = db.collection("counters").doc("weighments");
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
      const custSnap = await db.collection("customers")
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
    await db.collection("auditLog").add({
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
  .document("weighments/{weighmentId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Status changed to completed — update customer stats for net weight
    if (before.status !== "completed" && after.status === "completed") {
      const customerName = after.customerName;
      if (customerName && customerName !== "[Archived]") {
        const custSnap = await db.collection("customers")
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
      await db.collection("auditLog").add({
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
        const oldCust = await db.collection("customers")
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
        const newCust = await db.collection("customers")
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
      await db.collection("auditLog").add({
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

    // Camera face sync (existing logic, moved here)
    if (after.status === "completed") {
      const customerName = after.customerName;
      if (customerName && customerName !== "[Archived]") {
        const snaps = after.cameraSnapshots;
        if (snaps) {
          const face = snaps.tare?.customer || snaps.gross?.customer;
          if (face) {
            const custSnap = await db.collection("customers")
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
  .document("weighments/{weighmentId}")
  .onDelete(async (snap, context) => {
    const data = snap.data();
    const customerName = data.customerName;

    if (customerName && customerName !== "[Archived]") {
      const custSnap = await db.collection("customers")
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

    await db.collection("auditLog").add({
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
  .document("customers/{customerId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const defaults = {};

    if (!data.createdAt) defaults.createdAt = admin.firestore.FieldValue.serverTimestamp();
    if (data.totalWeighments === undefined) defaults.totalWeighments = 0;
    if (data.totalNetWeight === undefined) defaults.totalNetWeight = 0;

    if (Object.keys(defaults).length > 0) {
      await snap.ref.update(defaults);
    }

    await db.collection("auditLog").add({
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
  .document("customers_deleted/{customerId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();

    await db.collection("auditLog").add({
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
  .document("customers_deleted/{customerId}")
  .onDelete(async (snap, context) => {
    const data = snap.data();

    // Check if the customer was actually restored (not permanently deleted)
    const restoredDoc = await db.collection("customers").doc(context.params.customerId).get();
    if (restoredDoc.exists) {
      await db.collection("auditLog").add({
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
  .document("customer_merges/{mergeId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();

    await db.collection("auditLog").add({
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
  .document("customer_merges/{mergeId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    if (!before.reverted && after.reverted) {
      await db.collection("auditLog").add({
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
  .document("customers/{customerId}")
  .onUpdate(async (change, context) => {
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
      await db.collection("auditLog").add({
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
  .document("operators/{operatorId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Archive event
    if (!before.isArchived && after.isArchived) {
      await db.collection("auditLog").add({
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
      await db.collection("auditLog").add({
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
      await db.collection("auditLog").add({
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
      await db.collection("auditLog").add({
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
