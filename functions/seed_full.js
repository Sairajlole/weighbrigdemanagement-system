const admin = require("firebase-admin");
const crypto = require("crypto");

if (!admin.apps.length) admin.initializeApp({ projectId: "weighbridge-management" });
const db = admin.firestore();

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════════

const COMPANY_ID = "seed_company";
const SITE_ID = "seed_site";
const WB_ID = "seed_wb";

const CUSTOMER_COUNT = 400;
const WEIGHMENT_COUNT = 1000;

const COMPANY_PATH = `companies/${COMPANY_ID}`;
const SITE_PATH = `${COMPANY_PATH}/sites/${SITE_ID}`;
const WB_PATH = `${SITE_PATH}/weighbridges/${WB_ID}`;

function hashPassword(pw) {
  return crypto.createHash("sha256").update(pw).digest("hex");
}

// ═══════════════════════════════════════════════════════════════════════════════
// DATA POOLS
// ═══════════════════════════════════════════════════════════════════════════════

const firstNames = [
  "Rajesh", "Suresh", "Mahesh", "Ramesh", "Dinesh", "Ganesh", "Mukesh", "Naresh",
  "Priya", "Anita", "Sunita", "Kavita", "Savita", "Rohit", "Amit", "Sumit",
  "Vikas", "Deepak", "Ashok", "Anil", "Sunil", "Vinod", "Pramod", "Manoj",
  "Sanjay", "Vijay", "Ajay", "Ravi", "Kiran", "Mohan", "Sohan", "Rohan",
  "Pooja", "Neha", "Sneha", "Aarti", "Swati", "Jyoti", "Preeti", "Nidhi",
  "Rakesh", "Harish", "Yogesh", "Pankaj", "Sachin", "Gaurav", "Nitin", "Tarun",
  "Meena", "Rekha",
];

const lastNames = [
  "Sharma", "Verma", "Gupta", "Singh", "Kumar", "Patel", "Shah", "Jain",
  "Agarwal", "Mishra", "Pandey", "Tiwari", "Yadav", "Chauhan", "Rawat", "Negi",
  "Thakur", "Mehta", "Chopra", "Malhotra", "Kapoor", "Arora", "Bhatia", "Sethi",
  "Saxena", "Rastogi", "Bansal", "Goel", "Mittal", "Sinha",
];

const addresses = [
  "Sector 12, Noida", "MG Road, Gurgaon", "Civil Lines, Jaipur", "Station Road, Lucknow",
  "Ring Road, Delhi", "Bypass Road, Agra", "Industrial Area, Faridabad", "GT Road, Panipat",
  "Rajpur Road, Dehradun", "Mall Road, Shimla", "Cantonment, Meerut", "Sadar Bazar, Kanpur",
  "Ashok Nagar, Bhopal", "Vijay Nagar, Indore", "Arera Colony, Bhopal", "Tonk Road, Jaipur",
  "Vaishali Nagar, Jaipur", "Mansarovar, Jaipur", "Gomti Nagar, Lucknow", "Aliganj, Lucknow",
  "Lajpat Nagar, Delhi", "Karol Bagh, Delhi", "Connaught Place, Delhi", "Nehru Place, Delhi",
  "Sector 62, Noida", "Sector 18, Noida", "DLF Phase 3, Gurgaon", "Sohna Road, Gurgaon",
  "Malviya Nagar, Jaipur", "C-Scheme, Jaipur",
];

const materialsWeighted = [
  { name: "Sand", weight: 20 },
  { name: "Gravel", weight: 15 },
  { name: "Cement", weight: 12 },
  { name: "Iron Ore", weight: 10 },
  { name: "Coal", weight: 10 },
  { name: "Limestone", weight: 8 },
  { name: "Marble", weight: 5 },
  { name: "Granite", weight: 5 },
  { name: "Fly Ash", weight: 4 },
  { name: "Gypite", weight: 3 },
  { name: "Bauxite", weight: 2 },
  { name: "Clay", weight: 2 },
  { name: "Dolomite", weight: 2 },
  { name: "Quartzite", weight: 1 },
  { name: "Slag", weight: 1 },
];

const materialsCdf = [];
{
  let cumulative = 0;
  for (const m of materialsWeighted) {
    cumulative += m.weight;
    materialsCdf.push({ name: m.name, threshold: cumulative });
  }
}

function pickMaterial() {
  const r = Math.random() * 100;
  for (const entry of materialsCdf) {
    if (r < entry.threshold) return entry.name;
  }
  return materialsCdf[materialsCdf.length - 1].name;
}

const vehiclePrefixes = ["RJ", "DL", "UP", "HR", "MP", "MH", "GJ", "PB", "TN", "KA", "AP", "TS", "WB", "OR", "CG"];

const allCameraLabels = {
  cam1: "Front", cam2: "Rear", cam3: "Top", cam4: "Side-Right", cam5: "Side-Left",
  operator: "Operator", customer: "Customer",
};

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

function randomPhone() {
  return "+91 9" + Math.floor(100000000 + Math.random() * 900000000).toString();
}

function randomDate(startMonthsAgo, endMonthsAgo) {
  const now = Date.now();
  const start = now - startMonthsAgo * 30 * 24 * 60 * 60 * 1000;
  const end = now - endMonthsAgo * 30 * 24 * 60 * 60 * 1000;
  return new Date(start + Math.random() * (end - start));
}

function biasedRecentDate(monthsBack) {
  // Bias toward recent: use exponential distribution
  const u = Math.random();
  const biased = Math.pow(u, 2); // squares → more recent
  const now = Date.now();
  const range = monthsBack * 30 * 24 * 60 * 60 * 1000;
  const ts = now - biased * range;
  // Bias toward weekdays and business hours
  const d = new Date(ts);
  const day = d.getDay();
  if (day === 0) d.setDate(d.getDate() + 1); // Sun → Mon
  if (day === 6 && Math.random() > 0.3) d.setDate(d.getDate() + 2); // 70% skip Sat
  // Bias hours to 6am-10pm
  const hour = d.getHours();
  if (hour < 6) d.setHours(6 + Math.floor(Math.random() * 4));
  if (hour > 22) d.setHours(18 + Math.floor(Math.random() * 4));
  return d;
}

function randomVehicleNumber() {
  const prefix = vehiclePrefixes[Math.floor(Math.random() * vehiclePrefixes.length)];
  const num1 = (10 + Math.floor(Math.random() * 40)).toString();
  const letter1 = String.fromCharCode(65 + Math.floor(Math.random() * 26));
  const letter2 = String.fromCharCode(65 + Math.floor(Math.random() * 26));
  const num2 = (1000 + Math.floor(Math.random() * 9000)).toString();
  return `${prefix}${num1}${letter1}${letter2}${num2}`;
}

function cameraLabelsForCount(count) {
  const labels = {};
  const keys = ["cam1", "cam2", "cam3", "cam4", "cam5"];
  for (let c = 0; c < count; c++) labels[keys[c]] = allCameraLabels[keys[c]];
  labels.operator = "Operator";
  labels.customer = "Customer";
  return labels;
}

function snapshotsForPhase(idx, phase, camCount) {
  const p = phase === "gross" ? "g" : "t";
  const snap = {};
  const camEntries = [
    ["cam1", `https://picsum.photos/seed/w${idx}_${p}_front/640/360`],
    ["cam2", `https://picsum.photos/seed/w${idx}_${p}_rear/640/360`],
    ["cam3", `https://picsum.photos/seed/w${idx}_${p}_top/640/360`],
    ["cam4", `https://picsum.photos/seed/w${idx}_${p}_sideR/640/360`],
    ["cam5", `https://picsum.photos/seed/w${idx}_${p}_sideL/640/360`],
  ];
  for (let c = 0; c < camCount; c++) snap[camEntries[c][0]] = camEntries[c][1];
  snap.operator = `https://i.pravatar.cc/300?img=${(idx % 70) + 1}`;
  snap.customer = `https://randomuser.me/api/portraits/${idx % 2 === 0 ? "men" : "women"}/${(idx * 3 + (phase === "tare" ? 50 : 0)) % 100}.jpg`;
  return snap;
}

// Power-law distribution: returns index biased toward lower values
function powerLawIndex(max, exponent = 1.5) {
  const u = Math.random();
  return Math.min(Math.floor(max * Math.pow(u, exponent)), max - 1);
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLEAR EXISTING DATA
// ═══════════════════════════════════════════════════════════════════════════════

async function clearCollection(path) {
  const snap = await db.collection(path).get();
  if (snap.empty) return 0;
  const chunks = [];
  let batch = db.batch();
  let count = 0;
  for (const doc of snap.docs) {
    batch.delete(doc.ref);
    count++;
    if (count % 450 === 0) {
      chunks.push(batch);
      batch = db.batch();
    }
  }
  if (count % 450 !== 0) chunks.push(batch);
  for (const c of chunks) await c.commit();
  return snap.size;
}

// ═══════════════════════════════════════════════════════════════════════════════
// OPERATORS
// ═══════════════════════════════════════════════════════════════════════════════

const operatorProfiles = [
  {
    name: "Admin User", email: "admin@weighbridge.local", phone: "+91 9000000000",
    role: "companyAdmin", isVerified: true, isActive: true, idStatus: "verified",
    shiftRestricted: false, password: hashPassword("admin123"),
  },
  {
    name: "Ravi Kumar", email: "ravi@weighbridge.local", phone: "+91 9876543210",
    role: "operator", isVerified: true, isActive: true, idStatus: "verified",
    shiftRestricted: false, password: hashPassword("password123"),
  },
  {
    name: "Ankit Sharma", email: "ankit@weighbridge.local", phone: "+91 9876543211",
    role: "operator", isVerified: true, isActive: true, idStatus: "verified",
    shiftRestricted: true, shiftStart: "06:00", shiftEnd: "14:00",
    shiftDays: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
    password: hashPassword("password123"),
  },
  {
    name: "Pradeep Singh", email: "pradeep@weighbridge.local", phone: "+91 9876543212",
    role: "operator", isVerified: true, isActive: true, idStatus: "submitted",
    shiftRestricted: true, shiftStart: "14:00", shiftEnd: "22:00",
    shiftDays: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
    password: hashPassword("password123"),
  },
  {
    name: "Sunil Verma", email: "sunil@weighbridge.local", phone: "+91 9876543213",
    role: "operator", isVerified: true, isActive: true, idStatus: "verified",
    shiftRestricted: false, password: hashPassword("password123"),
  },
  {
    name: "Deepak Yadav", email: "deepak@weighbridge.local", phone: "+91 9876543214",
    role: "operator", isVerified: true, isActive: true, idStatus: "submitted",
    shiftRestricted: true, shiftStart: "22:00", shiftEnd: "06:00",
    shiftDays: ["Mon", "Tue", "Wed", "Thu", "Fri"],
    password: hashPassword("password123"),
  },
  {
    name: "Meera Patel", email: "meera@weighbridge.local", phone: "+91 9876543215",
    role: "operator", isVerified: false, isActive: true, idStatus: "not_submitted",
    shiftRestricted: false, password: hashPassword("password123"),
  },
  {
    name: "Kavita Joshi", email: "kavita@weighbridge.local", phone: "+91 9876543216",
    role: "operator", isVerified: false, isActive: false, idStatus: "not_submitted",
    shiftRestricted: false, password: hashPassword("password123"),
  },
];

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN SEED
// ═══════════════════════════════════════════════════════════════════════════════

async function seed() {
  const t0 = Date.now();
  console.log("═══════════════════════════════════════════════════════");
  console.log("  SEED FULL — Weighbridge Management Test Data");
  console.log("═══════════════════════════════════════════════════════\n");

  // ─── Step 1: Clear existing hierarchical data ───────────────────────────
  console.log("Step 1: Clearing existing data...");
  const cleared = {
    weighments: await clearCollection(`${WB_PATH}/weighments`),
    customers: await clearCollection(`${COMPANY_PATH}/customers`),
    operators: await clearCollection(`${SITE_PATH}/operators`),
    flatOps: await clearCollection("operators"),
  };
  console.log(`  Cleared: ${cleared.weighments} weighments, ${cleared.customers} customers, ${cleared.operators}+${cleared.flatOps} operators`);

  // ─── Step 2: Create infrastructure ──────────────────────────────────────
  console.log("\nStep 2: Creating infrastructure...");
  await db.doc(COMPANY_PATH).set({
    name: "Seed Transport Co.",
    adminUid: "seed_admin_uid",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  await db.doc(`${SITE_PATH}`).set({
    name: "Main Yard",
    location: "Industrial Area, Sector 62, Noida",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  await db.doc(`${WB_PATH}`).set({
    name: "WB-01",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log("  Created: company, site, weighbridge");

  // ─── Step 3: Create operators ───────────────────────────────────────────
  console.log("\nStep 3: Creating 8 operators...");
  const operatorIds = [];
  const operatorNames = [];

  const opBatch = db.batch();
  for (const op of operatorProfiles) {
    const data = {
      name: op.name,
      email: op.email,
      phone: op.phone,
      role: op.role,
      isActive: op.isActive,
      isVerified: op.isVerified,
      mustChangePassword: false,
      idStatus: op.idStatus,
      shiftRestricted: op.shiftRestricted,
      password: op.password,
      companyId: COMPANY_ID,
      loginCount: Math.floor(Math.random() * 200),
      createdAt: admin.firestore.Timestamp.fromDate(randomDate(12, 6)),
    };
    if (op.shiftRestricted) {
      data.shiftStart = op.shiftStart;
      data.shiftEnd = op.shiftEnd;
      data.shiftDays = op.shiftDays;
    }
    if (op.role === "companyAdmin") {
      data.uid = "seed_admin_uid";
    }

    // Write to nested site path
    const nestedRef = db.collection(`${SITE_PATH}/operators`).doc();
    opBatch.set(nestedRef, data);
    operatorIds.push(nestedRef.id);
    operatorNames.push(op.name);

    // Also write admin to flat operators collection (for login resolution)
    if (op.role === "companyAdmin") {
      const flatRef = db.collection("operators").doc();
      opBatch.set(flatRef, data);
    }
  }
  await opBatch.commit();
  console.log("  Created 8 operators (admin + 7)");
  console.log(`  Admin login: admin@weighbridge.local / admin123`);

  // ─── Step 4: Create 400 customers ──────────────────────────────────────
  console.log(`\nStep 4: Creating ${CUSTOMER_COUNT} customers...`);
  const customerIds = [];
  const customerNames = [];
  const customerPhones = [];
  const usedNames = new Set();

  // Generate unique names
  while (customerNames.length < CUSTOMER_COUNT) {
    const first = firstNames[Math.floor(Math.random() * firstNames.length)];
    const last = lastNames[Math.floor(Math.random() * lastNames.length)];
    const name = `${first} ${last}`;
    if (!usedNames.has(name)) {
      usedNames.add(name);
      customerNames.push(name);
    }
  }

  // Batch write customers
  let custBatch = db.batch();
  let custBatchCount = 0;

  for (let i = 0; i < CUSTOMER_COUNT; i++) {
    const phone = randomPhone();
    customerPhones.push(phone);
    const createdAt = randomDate(12, 0);

    const data = {
      name: customerNames[i],
      phone,
      totalWeighments: 0,
      createdAt: admin.firestore.Timestamp.fromDate(createdAt),
      updatedAt: admin.firestore.Timestamp.fromDate(createdAt),
    };

    // 70% have address
    if (Math.random() < 0.7) {
      data.address = addresses[Math.floor(Math.random() * addresses.length)];
    }

    // 20% have face data
    if (Math.random() < 0.2) {
      data.firstFace = `https://picsum.photos/seed/face_${i}/200/200`;
      data.faceScannedAt = admin.firestore.Timestamp.fromDate(
        new Date(createdAt.getTime() + Math.random() * 7 * 24 * 60 * 60 * 1000)
      );
    }

    const ref = db.collection(`${COMPANY_PATH}/customers`).doc();
    custBatch.set(ref, data);
    customerIds.push(ref.id);
    custBatchCount++;

    if (custBatchCount >= 450) {
      await custBatch.commit();
      custBatch = db.batch();
      custBatchCount = 0;
    }

    if ((i + 1) % 50 === 0) process.stdout.write(`\r  Created ${i + 1}/${CUSTOMER_COUNT} customers`);
  }
  if (custBatchCount > 0) await custBatch.commit();
  console.log(`\r  Created ${CUSTOMER_COUNT}/${CUSTOMER_COUNT} customers`);

  // ─── Step 5: Create 1000 weighments ─────────────────────────────────────
  console.log(`\nStep 5: Creating ${WEIGHMENT_COUNT} weighments...`);
  const customerWeighmentCounts = {};
  let lastRst = 0;

  let wmBatch = db.batch();
  let wmBatchCount = 0;

  for (let i = 0; i < WEIGHMENT_COUNT; i++) {
    // Power-law customer assignment
    const custIdx = powerLawIndex(CUSTOMER_COUNT);
    const custId = customerIds[custIdx];
    customerWeighmentCounts[custId] = (customerWeighmentCounts[custId] || 0) + 1;

    // Pick operator (admin doesn't usually do weighments)
    const opIdx = 1 + Math.floor(Math.random() * (operatorIds.length - 1)); // skip admin at 0

    const createdAt = biasedRecentDate(12);
    const grossWeight = 8000 + Math.floor(Math.random() * 47000);
    const tareWeight = 3000 + Math.floor(Math.random() * 9000);
    const netWeight = grossWeight - tareWeight;
    const turnaroundMinutes = 15 + Math.floor(Math.random() * 180);
    const secondDate = new Date(createdAt.getTime() + turnaroundMinutes * 60000);
    const firstWeighType = Math.random() > 0.5 ? "gross" : "tare";

    // Status distribution: 850 completed, 100 awaitingTare, 50 pending
    let status;
    if (i < 850) status = "completed";
    else if (i < 950) status = "awaitingTare";
    else status = "pending";

    // Camera count: 55% have cameras
    const hasCameras = Math.random() < 0.55;
    const camCount = hasCameras ? (1 + Math.floor(Math.random() * 5)) : 0;

    const data = {
      sessionId: `session_full_${i}`,
      vehicleNumber: randomVehicleNumber(),
      customerName: customerNames[custIdx],
      customerPhone: customerPhones[custIdx],
      material: pickMaterial(),
      operatorId: operatorIds[opIdx],
      operatorName: operatorNames[opIdx],
      firstWeighType,
      createdAt: admin.firestore.Timestamp.fromDate(createdAt),
    };

    // Optional fields with varied presence
    if (Math.random() < 0.9) {
      const rst = 3000 + i;
      data.rstNumber = `${rst}`;
      lastRst = Math.max(lastRst, rst);
    }
    if (Math.random() < 0.65) data.customerAddress = addresses[Math.floor(Math.random() * addresses.length)];
    if (Math.random() < 0.8) data.operatorRole = "operator";
    if (Math.random() < 0.95) data.deviceId = "desktop";
    if (Math.random() < 0.95) data.weighbridgeId = WB_ID;
    if (Math.random() < 0.85) data.updatedAt = admin.firestore.Timestamp.fromDate(status === "completed" ? secondDate : createdAt);
    if (Math.random() < 0.9) data.currentStep = status === "completed" ? "complete" : (status === "awaitingTare" ? "saveWeighment" : "selectCustomer");

    // Camera data
    if (camCount > 0) {
      data.cameraLabels = cameraLabelsForCount(camCount);
      data.cameraSnapshots = {};
    }

    // Weight data based on status
    if (status === "completed") {
      if (firstWeighType === "gross") {
        data.grossWeight = grossWeight;
        data.grossDateTime = admin.firestore.Timestamp.fromDate(createdAt);
        data.tareWeight = tareWeight;
        data.tareDateTime = admin.firestore.Timestamp.fromDate(secondDate);
        if (camCount > 0) {
          data.cameraSnapshots.gross = snapshotsForPhase(i, "gross", camCount);
          data.cameraSnapshots.tare = snapshotsForPhase(i, "tare", camCount);
        }
      } else {
        data.tareWeight = tareWeight;
        data.tareDateTime = admin.firestore.Timestamp.fromDate(createdAt);
        data.grossWeight = grossWeight;
        data.grossDateTime = admin.firestore.Timestamp.fromDate(secondDate);
        if (camCount > 0) {
          data.cameraSnapshots.tare = snapshotsForPhase(i, "tare", camCount);
          data.cameraSnapshots.gross = snapshotsForPhase(i, "gross", camCount);
        }
      }
      data.netWeight = netWeight;
      data.status = "completed";
    } else if (status === "awaitingTare") {
      if (firstWeighType === "gross") {
        data.grossWeight = grossWeight;
        data.grossDateTime = admin.firestore.Timestamp.fromDate(createdAt);
        if (camCount > 0) data.cameraSnapshots.gross = snapshotsForPhase(i, "gross", camCount);
      } else {
        data.tareWeight = tareWeight;
        data.tareDateTime = admin.firestore.Timestamp.fromDate(createdAt);
        if (camCount > 0) data.cameraSnapshots.tare = snapshotsForPhase(i, "tare", camCount);
      }
      data.status = "awaitingTare";
    } else {
      data.status = "pending";
    }

    const ref = db.collection(`${WB_PATH}/weighments`).doc();
    wmBatch.set(ref, data);
    wmBatchCount++;

    if (wmBatchCount >= 450) {
      await wmBatch.commit();
      wmBatch = db.batch();
      wmBatchCount = 0;
    }

    if ((i + 1) % 50 === 0) process.stdout.write(`\r  Created ${i + 1}/${WEIGHMENT_COUNT} weighments`);
  }
  if (wmBatchCount > 0) await wmBatch.commit();
  console.log(`\r  Created ${WEIGHMENT_COUNT}/${WEIGHMENT_COUNT} weighments`);

  // ─── Step 6: Update customer totalWeighments ────────────────────────────
  console.log("\nStep 6: Updating customer weighment counts...");
  let updateBatch = db.batch();
  let updateCount = 0;
  for (const [custId, count] of Object.entries(customerWeighmentCounts)) {
    updateBatch.update(db.doc(`${COMPANY_PATH}/customers/${custId}`), { totalWeighments: count });
    updateCount++;
    if (updateCount % 450 === 0) {
      await updateBatch.commit();
      updateBatch = db.batch();
    }
  }
  if (updateCount % 450 !== 0) await updateBatch.commit();
  console.log(`  Updated ${Object.keys(customerWeighmentCounts).length} customers`);

  // ─── Step 7: Set RST counter ────────────────────────────────────────────
  console.log("\nStep 7: Setting RST counter...");
  await db.doc(`${WB_PATH}/counters/weighments`).set({ lastRst: lastRst });
  console.log(`  RST counter set to ${lastRst}`);

  // ─── Summary ────────────────────────────────────────────────────────────
  const elapsed = ((Date.now() - t0) / 1000).toFixed(1);
  console.log("\n═══════════════════════════════════════════════════════");
  console.log("  DONE!");
  console.log("═══════════════════════════════════════════════════════");
  console.log(`  Company:      Seed Transport Co. (${COMPANY_ID})`);
  console.log(`  Site:         Main Yard (${SITE_ID})`);
  console.log(`  Weighbridge:  WB-01 (${WB_ID})`);
  console.log(`  Operators:    8 (1 admin + 7)`);
  console.log(`  Customers:    ${CUSTOMER_COUNT}`);
  console.log(`  Weighments:   ${WEIGHMENT_COUNT} (850 completed, 100 awaitingTare, 50 pending)`);
  console.log(`  RST counter:  ${lastRst}`);
  console.log(`  Elapsed:      ${elapsed}s`);
  console.log("");
  console.log("  Login: admin@weighbridge.local / admin123");
  console.log("═══════════════════════════════════════════════════════");
}

seed().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
