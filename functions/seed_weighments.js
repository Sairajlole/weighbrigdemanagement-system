const admin = require("firebase-admin");

if (!admin.apps.length) admin.initializeApp({ projectId: "weighbridge-management" });
const db = admin.firestore();

const WEIGHMENT_COUNT = 250;

const materials = ["Sand", "Gravel", "Cement", "Iron Ore", "Coal", "Limestone", "Marble", "Granite", "Fly Ash", "Gypsum"];

const vehiclePrefixes = ["RJ", "DL", "UP", "HR", "MP", "MH", "GJ", "PB", "TN", "KA"];

const allCameraLabels = {
  cam1: "Front",
  cam2: "Rear",
  cam3: "Top",
  cam4: "Side-Right",
  cam5: "Side-Left",
  operator: "Operator",
  customer: "Customer",
};

// Distribution: 60% have 5 cams, 15% have 3, 10% have 2, 10% have 1, 5% have 0
function camCountForIndex(i) {
  const r = i % 20;
  if (r < 12) return 5;
  if (r < 15) return 3;
  if (r < 17) return 2;
  if (r < 19) return 1;
  return 0;
}

function cameraLabelsForCount(count) {
  const labels = {};
  const keys = ["cam1", "cam2", "cam3", "cam4", "cam5"];
  for (let c = 0; c < count; c++) {
    labels[keys[c]] = allCameraLabels[keys[c]];
  }
  labels.operator = "Operator";
  labels.customer = "Customer";
  return labels;
}

function snapshotsForPhase(weighmentIdx, phase, camCount) {
  const p = phase === "gross" ? "g" : "t";
  const snap = {};
  const camEntries = [
    ["cam1", `https://picsum.photos/seed/w${weighmentIdx}_${p}_front/640/360`],
    ["cam2", `https://picsum.photos/seed/w${weighmentIdx}_${p}_rear/640/360`],
    ["cam3", `https://picsum.photos/seed/w${weighmentIdx}_${p}_top/640/360`],
    ["cam4", `https://picsum.photos/seed/w${weighmentIdx}_${p}_sideR/640/360`],
    ["cam5", `https://picsum.photos/seed/w${weighmentIdx}_${p}_sideL/640/360`],
  ];
  for (let c = 0; c < camCount; c++) {
    snap[camEntries[c][0]] = camEntries[c][1];
  }
  snap.operator = `https://i.pravatar.cc/300?img=${(weighmentIdx % 70) + 1}`;
  snap.customer = customerPortrait(weighmentIdx, phase);
  return snap;
}

function customerPortrait(idx, phase) {
  const gender = idx % 2 === 0 ? "men" : "women";
  const n = ((idx * 3 + (phase === "tare" ? 50 : 0)) % 100);
  return `https://randomuser.me/api/portraits/${gender}/${n}.jpg`;
}

function randomPhone() {
  return "9" + Math.floor(100000000 + Math.random() * 900000000).toString();
}

function randomDate(startMonthsAgo, endMonthsAgo) {
  const now = Date.now();
  const start = now - startMonthsAgo * 30 * 24 * 60 * 60 * 1000;
  const end = now - endMonthsAgo * 30 * 24 * 60 * 60 * 1000;
  return new Date(start + Math.random() * (end - start));
}

function randomVehicleNumber() {
  const prefix = vehiclePrefixes[Math.floor(Math.random() * vehiclePrefixes.length)];
  const num1 = (10 + Math.floor(Math.random() * 40)).toString();
  const letter1 = String.fromCharCode(65 + Math.floor(Math.random() * 26));
  const letter2 = String.fromCharCode(65 + Math.floor(Math.random() * 26));
  const num2 = (1000 + Math.floor(Math.random() * 9000)).toString();
  return `${prefix}${num1}${letter1}${letter2}${num2}`;
}

async function seed() {
  // --- Step 1: Add 5 operators ---
  console.log("Adding 5 sample operators...");
  const operators = [
    { name: "Ravi Kumar", email: "ravi@weighbridge.local", phone: "9876543210" },
    { name: "Ankit Sharma", email: "ankit@weighbridge.local", phone: "9876543211" },
    { name: "Pradeep Singh", email: "pradeep@weighbridge.local", phone: "9876543212" },
    { name: "Sunil Verma", email: "sunil@weighbridge.local", phone: "9876543213" },
    { name: "Deepak Yadav", email: "deepak@weighbridge.local", phone: "9876543214" },
  ];

  const operatorIds = [];
  const operatorNames = [];

  for (const op of operators) {
    const ref = await db.collection("operators").add({
      name: op.name,
      email: op.email,
      phone: op.phone,
      isActive: true,
      isVerified: true,
      mustChangePassword: false,
      role: "operator",
      idStatus: "verified",
      shiftRestricted: false,
      loginCount: Math.floor(Math.random() * 100),
      createdAt: admin.firestore.Timestamp.fromDate(randomDate(12, 6)),
    });
    operatorIds.push(ref.id);
    operatorNames.push(op.name);
    console.log(`  Added operator: ${op.name}`);
  }

  // --- Step 2: Get existing customers ---
  console.log("\nFetching existing customers...");
  const customerSnap = await db.collection("customers").get();
  const customers = customerSnap.docs.map(d => ({
    id: d.id,
    name: d.data().name || "Walk-in",
    phone: d.data().phone || "",
  }));
  console.log(`  Found ${customers.length} customers`);

  if (customers.length === 0) {
    console.error("No customers found! Run seed.js first.");
    process.exit(1);
  }

  // --- Step 3: Clear existing weighments ---
  console.log("\nClearing existing weighments...");
  const existingWeighments = await db.collection("weighments").get();
  if (!existingWeighments.empty) {
    const chunks = [];
    let chunk = db.batch();
    let count = 0;
    for (const doc of existingWeighments.docs) {
      chunk.delete(doc.ref);
      count++;
      if (count % 450 === 0) {
        chunks.push(chunk);
        chunk = db.batch();
      }
    }
    chunks.push(chunk);
    for (const c of chunks) await c.commit();
    console.log(`  Deleted ${existingWeighments.size} weighments`);
  }

  // --- Step 4: Create 250 weighments ---
  console.log(`\nCreating ${WEIGHMENT_COUNT} weighments...`);
  const customerWeighmentCounts = {};

  for (let i = 0; i < WEIGHMENT_COUNT; i++) {
    const customer = customers[Math.floor(Math.random() * customers.length)];
    const opIdx = Math.floor(Math.random() * operatorIds.length);
    const material = materials[Math.floor(Math.random() * materials.length)];
    const createdAt = randomDate(10, 0);
    const grossWeight = 5000 + Math.floor(Math.random() * 45000);
    const tareWeight = 2000 + Math.floor(Math.random() * 8000);
    const isCompleted = Math.random() > 0.12;
    const firstWeighType = Math.random() > 0.5 ? "gross" : "tare";
    const netWeight = isCompleted ? grossWeight - tareWeight : null;
    const turnaroundMinutes = 15 + Math.floor(Math.random() * 120);
    const secondDate = new Date(createdAt.getTime() + turnaroundMinutes * 60000);

    const camCount = camCountForIndex(i);
    const data = {
      sessionId: `session_${Date.now()}_${i}`,
      rstNumber: `${2000 + i}`,
      deviceId: "desktop",
      weighbridgeId: "default",
      vehicleNumber: randomVehicleNumber(),
      customerName: customer.name,
      customerPhone: customer.phone,
      material,
      operatorId: operatorIds[opIdx],
      operatorName: operatorNames[opIdx],
      operatorRole: "operator",
      firstWeighType,
      cameraLabels: cameraLabelsForCount(camCount),
      createdAt: admin.firestore.Timestamp.fromDate(createdAt),
      updatedAt: admin.firestore.Timestamp.fromDate(isCompleted ? secondDate : createdAt),
    };

    if (firstWeighType === "gross") {
      data.grossWeight = grossWeight;
      data.grossDateTime = admin.firestore.Timestamp.fromDate(createdAt);
      data.cameraSnapshots = camCount > 0 ? { gross: snapshotsForPhase(i, "gross", camCount) } : {};
      if (isCompleted) {
        data.tareWeight = tareWeight;
        data.tareDateTime = admin.firestore.Timestamp.fromDate(secondDate);
        data.netWeight = netWeight;
        if (camCount > 0) data.cameraSnapshots.tare = snapshotsForPhase(i, "tare", camCount);
        data.status = "completed";
        data.currentStep = "complete";
      } else {
        data.status = "awaitingTare";
        data.currentStep = "saveWeighment";
      }
    } else {
      data.tareWeight = tareWeight;
      data.tareDateTime = admin.firestore.Timestamp.fromDate(createdAt);
      data.cameraSnapshots = camCount > 0 ? { tare: snapshotsForPhase(i, "tare", camCount) } : {};
      if (isCompleted) {
        data.grossWeight = grossWeight;
        data.grossDateTime = admin.firestore.Timestamp.fromDate(secondDate);
        if (camCount > 0) data.cameraSnapshots.gross = snapshotsForPhase(i, "gross", camCount);
        data.netWeight = netWeight;
        data.status = "completed";
        data.currentStep = "complete";
      } else {
        data.status = "awaitingTare";
        data.currentStep = "saveWeighment";
      }
    }

    await db.collection("weighments").add(data);
    customerWeighmentCounts[customer.id] = (customerWeighmentCounts[customer.id] || 0) + 1;

    if ((i + 1) % 10 === 0) process.stdout.write(`\r  Created ${i + 1}/${WEIGHMENT_COUNT}`);
  }
  console.log(`\r  Created ${WEIGHMENT_COUNT}/${WEIGHMENT_COUNT}`);

  // --- Step 5: Update customer totalWeighments ---
  console.log("\nUpdating customer weighment counts...");
  for (const [custId, count] of Object.entries(customerWeighmentCounts)) {
    await db.collection("customers").doc(custId).update({ totalWeighments: count });
  }
  console.log(`  Updated ${Object.keys(customerWeighmentCounts).length} customers`);

  console.log("\n✓ Done! Seeded:");
  console.log(`  5 operators`);
  console.log(`  ${WEIGHMENT_COUNT} weighments`);
  console.log(`  Materials: ${materials.join(", ")}`);
  console.log(`  ~88% completed, ~12% pending (mix of gross-first and tare-first)`);
  console.log(`  Camera distribution: 60% 5-cam, 15% 3-cam, 10% 2-cam, 10% 1-cam, 5% 0-cam`);
  console.log(`  Schema: cameraSnapshots.{gross|tare}.{cam1-5,operator,customer}`);
}

seed().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
