const admin = require("firebase-admin");

admin.initializeApp({ projectId: "weighbridge-management" });
const db = admin.firestore();

const CUSTOMER_COUNT = 40;
const WEIGHMENT_COUNT = 100;

const firstNames = [
  "Rajesh", "Suresh", "Mahesh", "Ramesh", "Dinesh", "Ganesh", "Mukesh", "Naresh",
  "Priya", "Anita", "Sunita", "Kavita", "Savita", "Rohit", "Amit", "Sumit",
  "Vikas", "Deepak", "Ashok", "Anil", "Sunil", "Vinod", "Pramod", "Manoj",
  "Sanjay", "Vijay", "Ajay", "Ravi", "Kiran", "Mohan", "Sohan", "Rohan",
  "Pooja", "Neha", "Sneha", "Aarti", "Swati", "Jyoti", "Preeti", "Nidhi",
];

const lastNames = [
  "Sharma", "Verma", "Gupta", "Singh", "Kumar", "Patel", "Shah", "Jain",
  "Agarwal", "Mishra", "Pandey", "Tiwari", "Yadav", "Chauhan", "Rawat", "Negi",
  "Thakur", "Mehta", "Chopra", "Malhotra", "Kapoor", "Arora", "Bhatia", "Sethi",
];

const addresses = [
  "Sector 12, Noida", "MG Road, Gurgaon", "Civil Lines, Jaipur", "Station Road, Lucknow",
  "Ring Road, Delhi", "Bypass Road, Agra", "Industrial Area, Faridabad", "GT Road, Panipat",
  "Rajpur Road, Dehradun", "Mall Road, Shimla", "Cantonment, Meerut", "Sadar Bazar, Kanpur",
  "Ashok Nagar, Bhopal", "Vijay Nagar, Indore", "Arera Colony, Bhopal", "Tonk Road, Jaipur",
  "Vaishali Nagar, Jaipur", "Mansarovar, Jaipur", "Gomti Nagar, Lucknow", "Aliganj, Lucknow",
];

const materials = ["Sand", "Gravel", "Cement", "Iron", "Coal", "Limestone", "Marble", "Granite"];

function randomPhone() {
  return "9" + Math.floor(100000000 + Math.random() * 900000000).toString();
}

function randomDate(startMonthsAgo, endMonthsAgo) {
  const now = Date.now();
  const start = now - startMonthsAgo * 30 * 24 * 60 * 60 * 1000;
  const end = now - endMonthsAgo * 30 * 24 * 60 * 60 * 1000;
  return new Date(start + Math.random() * (end - start));
}

// No face data for seeded customers — faces are captured via camera
function fakeFacePath() {
  return null;
}

async function clearCollection(name) {
  const snap = await db.collection(name).get();
  if (snap.empty) return 0;
  const batch = db.batch();
  snap.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  return snap.size;
}

async function seed() {
  console.log("Clearing existing customers...");
  const clearedCustomers = await clearCollection("customers");
  console.log(`  Deleted ${clearedCustomers} customers`);

  console.log("Clearing existing weighments...");
  const clearedWeighments = await clearCollection("weighments");
  console.log(`  Deleted ${clearedWeighments} weighments`);

  console.log("Clearing recycle bin...");
  const clearedBin = await clearCollection("customers_deleted");
  console.log(`  Deleted ${clearedBin} from recycle bin`);

  // Create customers
  console.log(`\nCreating ${CUSTOMER_COUNT} customers...`);
  const customerIds = [];
  const customerNames = [];

  for (let i = 0; i < CUSTOMER_COUNT; i++) {
    const first = firstNames[i % firstNames.length];
    const last = lastNames[i % lastNames.length];
    const name = `${first} ${last}`;
    const phone = randomPhone();
    const address = addresses[i % addresses.length];
    const createdAt = randomDate(12, 1);

    const data = {
      name,
      phone,
      address,
      totalWeighments: 0,
      createdAt: admin.firestore.Timestamp.fromDate(createdAt),
      updatedAt: admin.firestore.Timestamp.fromDate(createdAt),
      firstFace: null,
      lastFace: null,
      faceScannedAt: null,
    };

    const ref = await db.collection("customers").add(data);
    customerIds.push(ref.id);
    customerNames.push(name);
    process.stdout.write(`\r  Created customer ${i + 1}/${CUSTOMER_COUNT}`);
  }
  console.log("");

  // Create weighments
  console.log(`Creating ${WEIGHMENT_COUNT} weighments...`);
  const weighmentCounts = new Array(CUSTOMER_COUNT).fill(0);

  for (let i = 0; i < WEIGHMENT_COUNT; i++) {
    const custIdx = Math.floor(Math.random() * CUSTOMER_COUNT);
    const material = materials[Math.floor(Math.random() * materials.length)];
    const createdAt = randomDate(10, 0);
    const grossWeight = 5000 + Math.floor(Math.random() * 45000);
    const tareWeight = 2000 + Math.floor(Math.random() * 8000);
    const netWeight = grossWeight - tareWeight;

    const data = {
      sessionId: `session_${i}`,
      rstNumber: `${1000 + i}`,
      deviceId: "desktop",
      weighbridgeId: "default",
      vehicleNumber: `RJ${10 + Math.floor(Math.random() * 40)}${String.fromCharCode(65 + Math.floor(Math.random() * 26))}${String.fromCharCode(65 + Math.floor(Math.random() * 26))}${1000 + Math.floor(Math.random() * 9000)}`,
      customerName: customerNames[custIdx],
      customerPhone: "",
      material,
      operatorId: "admin",
      operatorName: "Operator",
      operatorRole: "operator",
      grossWeight,
      grossDateTime: admin.firestore.Timestamp.fromDate(createdAt),
      tareWeight,
      tareDateTime: admin.firestore.Timestamp.fromDate(new Date(createdAt.getTime() + 3600000)),
      netWeight,
      status: "completed",
      currentStep: "complete",
      createdAt: admin.firestore.Timestamp.fromDate(createdAt),
      updatedAt: admin.firestore.Timestamp.fromDate(createdAt),
    };

    await db.collection("weighments").add(data);
    weighmentCounts[custIdx]++;
    process.stdout.write(`\r  Created weighment ${i + 1}/${WEIGHMENT_COUNT}`);
  }
  console.log("");

  // Update totalWeighments on each customer
  console.log("Updating customer weighment counts...");
  for (let i = 0; i < CUSTOMER_COUNT; i++) {
    if (weighmentCounts[i] > 0) {
      await db.collection("customers").doc(customerIds[i]).update({
        totalWeighments: weighmentCounts[i],
      });
    }
  }

  console.log("\nDone! Seeded:");
  console.log(`  ${CUSTOMER_COUNT} customers`);
  console.log(`  ${WEIGHMENT_COUNT} weighments`);
  console.log(`  Materials: ${materials.join(", ")}`);
}

seed().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
