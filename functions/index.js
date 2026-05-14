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
  .schedule("every 7 days")
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

  // Verify caller is admin (not in operators collection)
  const callerSnap = await db.collection("operators")
    .where("email", "==", context.auth.token.email)
    .limit(1)
    .get();

  if (!callerSnap.empty) {
    const callerData = callerSnap.docs[0].data();
    if (callerData.role !== "admin") {
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
