const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

function parseArgs(argv) {
  const args = {
    sensorId: "d83bda1d5960",
    serviceAccountPath:
      process.env.FIREBASE_SERVICE_ACCOUNT_PATH ||
      process.env.GOOGLE_APPLICATION_CREDENTIALS ||
      null,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if ((token === "--sensor" || token === "-s") && argv[i + 1]) {
      args.sensorId = argv[i + 1].trim();
      i += 1;
      continue;
    }

    if ((token === "--sa" || token === "--service-account") && argv[i + 1]) {
      args.serviceAccountPath = argv[i + 1].trim();
      i += 1;
    }
  }

  return args;
}

function normalizeSensorId(value) {
  return String(value || "")
    .replace(/airgradient:/gi, "")
    .replace(/[^a-fA-F0-9]/g, "")
    .toLowerCase();
}

function toLegacyMac(normalized) {
  if (!normalized || normalized.length !== 12) return null;
  const pairs = normalized.match(/.{1,2}/g);
  return pairs ? pairs.join(":").toUpperCase() : null;
}

function resolveServiceAccountPath(explicitPath) {
  if (explicitPath && fs.existsSync(explicitPath)) {
    return explicitPath;
  }

  const fallback = path.resolve(
    __dirname,
    "..",
    "..",
    "..",
    "Indoorairqualityappv2-main",
    "capstone-air-quality-yu25-firebase-adminsdk-fbsvc-c6638dc5a5.json"
  );

  if (fs.existsSync(fallback)) {
    return fallback;
  }

  return null;
}

function isPlainObject(value) {
  return Object.prototype.toString.call(value) === "[object Object]";
}

function normalizeValue(value) {
  if (value == null) return "";
  if (value && typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (Array.isArray(value)) {
    return JSON.stringify(value);
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return value;
  }
  if (typeof value === "string") {
    return value;
  }
  return JSON.stringify(value);
}

function flattenRow(input, prefix = "", out = {}) {
  if (!isPlainObject(input)) return out;

  for (const [key, value] of Object.entries(input)) {
    const flatKey = prefix ? `${prefix}.${key}` : key;

    if (value && typeof value.toDate === "function") {
      out[flatKey] = value.toDate().toISOString();
      continue;
    }

    if (isPlainObject(value)) {
      flattenRow(value, flatKey, out);
      continue;
    }

    out[flatKey] = normalizeValue(value);
  }

  return out;
}

function csvEscape(value) {
  const text = value == null ? "" : String(value);
  if (/[",\n\r]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

async function fetchAllDocs(collectionRef, orderField) {
  const docs = [];
  let lastDoc = null;

  while (true) {
    let query = collectionRef.orderBy(orderField, "asc").limit(1000);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snap = await query.get();
    if (snap.empty) break;

    docs.push(...snap.docs);
    lastDoc = snap.docs[snap.docs.length - 1];

    if (snap.size < 1000) break;
  }

  return docs;
}

function buildCsv(rows) {
  if (rows.length === 0) {
    return { csvText: "", columns: [] };
  }

  const keys = new Set();
  for (const row of rows) {
    for (const key of Object.keys(row)) {
      keys.add(key);
    }
  }

  const columns = [...keys].sort((a, b) => a.localeCompare(b));
  const lines = [columns.join(",")];

  for (const row of rows) {
    const values = columns.map((column) => csvEscape(row[column]));
    lines.push(values.join(","));
  }

  return {
    csvText: lines.join("\n"),
    columns,
  };
}

async function exportCollection(sensorRef, collectionName, orderField, outputDir, stamp) {
  const docs = await fetchAllDocs(sensorRef.collection(collectionName), orderField);
  const rows = docs.map((doc) => flattenRow(doc.data()));
  const { csvText, columns } = buildCsv(rows);
  const outputPath = path.join(
    outputDir,
    `sensor_${sensorRef.id}_${collectionName}_all_${stamp}.csv`
  );

  fs.writeFileSync(outputPath, csvText, "utf8");

  const columnCount = columns.length;
  return {
    outputPath,
    rowCount: rows.length,
    columnCount,
  };
}

async function resolveSensorRef(db, sensorId) {
  const normalized = normalizeSensorId(sensorId);
  const legacy = toLegacyMac(normalized);
  const candidates = [normalized, legacy].filter(Boolean);

  for (const candidate of candidates) {
    const ref = db.collection("sensors").doc(candidate);
    const snap = await ref.get();
    if (snap.exists) return ref;
  }

  return null;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const serviceAccountPath = resolveServiceAccountPath(args.serviceAccountPath);

  if (!serviceAccountPath) {
    throw new Error(
      "Service account file not found. Pass --sa <path> or set GOOGLE_APPLICATION_CREDENTIALS."
    );
  }

  const serviceAccount = require(serviceAccountPath);
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();

  const sensorRef = await resolveSensorRef(db, args.sensorId);
  if (!sensorRef) {
    throw new Error(`Sensor not found: ${args.sensorId}`);
  }

  const outputDir = path.resolve(__dirname, "..", "..", "..", "exports");
  fs.mkdirSync(outputDir, { recursive: true });

  const stamp = new Date()
    .toISOString()
    .replace(/:/g, "")
    .replace(/\./g, "")
    .replace("T", "_")
    .replace("Z", "Z");

  const history = await exportCollection(sensorRef, "history", "createdAt", outputDir, stamp);
  const series = await exportCollection(sensorRef, "series", "timestamp", outputDir, stamp);

  console.log("SENSOR_DOC=", sensorRef.id);
  console.log("HISTORY_CSV=", history.outputPath);
  console.log("HISTORY_ROWS=", history.rowCount, "HISTORY_COLUMNS=", history.columnCount);
  console.log("SERIES_CSV=", series.outputPath);
  console.log("SERIES_ROWS=", series.rowCount, "SERIES_COLUMNS=", series.columnCount);
}

main().catch((error) => {
  console.error("EXPORT_ERROR:", error.message || error);
  process.exit(1);
});
