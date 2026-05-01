const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

function parseArgs(argv) {
  const args = {
    sensorId: 'd83bda1d5960',
    serviceAccountPath: process.env.FIREBASE_SERVICE_ACCOUNT_PATH || process.env.GOOGLE_APPLICATION_CREDENTIALS || null,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if ((token === '--sensor' || token === '-s') && argv[i + 1]) {
      args.sensorId = argv[i + 1].trim();
      i += 1;
      continue;
    }
    if ((token === '--sa' || token === '--service-account') && argv[i + 1]) {
      args.serviceAccountPath = argv[i + 1].trim();
      i += 1;
    }
  }

  return args;
}

function normalizeSensorId(value) {
  return (value || '')
    .replace(/airgradient:/gi, '')
    .replace(/[^a-fA-F0-9]/g, '')
    .toLowerCase();
}

function toLegacyMac(normalized) {
  if (!normalized || normalized.length !== 12) return null;
  return normalized.match(/.{1,2}/g).join(':').toUpperCase();
}

function resolveServiceAccountPath(explicitPath) {
  if (explicitPath && fs.existsSync(explicitPath)) {
    return explicitPath;
  }

  const fallback = path.resolve(
    __dirname,
    '..',
    '..',
    '..',
    'Indoorairqualityappv2-main',
    'capstone-air-quality-yu25-firebase-adminsdk-fbsvc-c6638dc5a5.json',
  );

  if (fs.existsSync(fallback)) {
    return fallback;
  }

  return null;
}

function heartbeatState(diffSec) {
  if (diffSec == null) return 'NO_HEARTBEAT';
  if (diffSec <= 30) return 'ONLINE';
  if (diffSec <= 180) return 'DEGRADED';
  return 'STALE';
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const normalized = normalizeSensorId(args.sensorId);
  const legacy = toLegacyMac(normalized);

  if (!normalized) {
    throw new Error('Invalid sensor id. Use --sensor d83bda1d5960 or MAC format.');
  }

  const serviceAccountPath = resolveServiceAccountPath(args.serviceAccountPath);
  if (!serviceAccountPath) {
    throw new Error(
      'Service account file not found. Pass --sa <path> or set GOOGLE_APPLICATION_CREDENTIALS.',
    );
  }

  const serviceAccount = require(serviceAccountPath);
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();

  const docIdsToCheck = [normalized];
  if (legacy) docIdsToCheck.push(legacy);

  let selectedDoc = null;
  let selectedData = null;

  for (const docId of docIdsToCheck) {
    const snapshot = await db.collection('sensors').doc(docId).get();
    if (snapshot.exists) {
      selectedDoc = docId;
      selectedData = snapshot.data() || {};
      break;
    }
  }

  console.log('--- SENSOR STATUS ---');
  console.log('input.sensorId =', args.sensorId);
  console.log('normalized    =', normalized);
  if (legacy) console.log('legacy.mac    =', legacy);
  console.log('serviceAccount=', serviceAccountPath);

  if (!selectedDoc) {
    console.log('sensor.doc    = NOT_FOUND');
    console.log('result        = OFFLINE_OR_WRONG_SENSOR_ID');
    process.exit(0);
  }

  const now = new Date();
  const lastSeenDate = selectedData.lastSeen && selectedData.lastSeen.toDate
    ? selectedData.lastSeen.toDate()
    : null;
  const diffSec = lastSeenDate ? Math.round((now - lastSeenDate) / 1000) : null;

  console.log('sensor.doc    =', selectedDoc);
  console.log('lastSeen      =', lastSeenDate ? lastSeenDate.toISOString() : 'null');
  console.log('diff.sec      =', diffSec == null ? 'null' : diffSec);
  console.log('heartbeat     =', heartbeatState(diffSec));
  console.log('latest.keys   =', Object.keys(selectedData.latest || {}).join(',') || '(none)');

  const bindingSnapshots = await Promise.all([
    db.collection('devices').where('sensorId', '==', normalized).get(),
    legacy ? db.collection('devices').where('sensorId', '==', legacy).get() : Promise.resolve(null),
  ]);

  const docsById = new Map();
  for (const snap of bindingSnapshots) {
    if (!snap) continue;
    for (const doc of snap.docs) {
      if (!docsById.has(doc.id)) {
        docsById.set(doc.id, doc.data() || {});
      }
    }
  }

  console.log('--- BINDINGS ---');
  console.log('bound.count   =', docsById.size);
  for (const [docId, data] of docsById.entries()) {
    console.log(
      'device.doc    =',
      docId,
      '| sensorId =',
      data.sensorId || null,
      '| path =',
      data.firestoreDocPath || null,
      '| platform =',
      data.platform || null,
    );
  }

  if (diffSec != null && diffSec <= 30 && docsById.size > 0) {
    console.log('result        = CLOUD_OK_AND_BOUND');
  } else if (diffSec != null && diffSec <= 30) {
    console.log('result        = CLOUD_OK_BUT_NOT_BOUND');
  } else if (docsById.size > 0) {
    console.log('result        = BOUND_BUT_NO_LIVE_INGEST');
  } else {
    console.log('result        = NOT_BOUND_AND_NO_LIVE_INGEST');
  }

  process.exit(0);
}

main().catch((error) => {
  console.error('ERROR:', error.message || error);
  process.exit(1);
});
