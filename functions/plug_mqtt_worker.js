const admin = require("firebase-admin");
const mqtt = require("mqtt");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

const mqttUrl = String(process.env.MQTT_URL || "").trim();
const mqttUsername = process.env.MQTT_USERNAME || undefined;
const mqttPassword = process.env.MQTT_PASSWORD || undefined;
const workerId = String(process.env.WORKER_ID || "plug-mqtt-worker").trim();
const pollIntervalMs = Math.max(500, Number(process.env.WORKER_POLL_INTERVAL_MS || 1500));
const commandTimeoutMs = Math.max(3000, Number(process.env.WORKER_COMMAND_TIMEOUT_MS || 15000));
const plugLogRetentionDays = Math.max(1, Number(process.env.PLUG_LOG_RETENTION_DAYS || 90));
const enableExpireAtTtlWrites = process.env.ENABLE_EXPIREAT_TTL_WRITES === undefined
  ? true
  : ["1", "true", "yes", "y", "on"].includes(String(process.env.ENABLE_EXPIREAT_TTL_WRITES).trim().toLowerCase());
const publishQos = [0, 1, 2].includes(Number(process.env.WORKER_PUBLISH_QOS))
  ? Number(process.env.WORKER_PUBLISH_QOS)
  : 1;
const subscribeQos = [0, 1, 2].includes(Number(process.env.WORKER_SUBSCRIBE_QOS))
  ? Number(process.env.WORKER_SUBSCRIBE_QOS)
  : 1;

if (!mqttUrl) {
  throw new Error("MQTT_URL environment variable is required");
}

const client = mqtt.connect(mqttUrl, {
  username: mqttUsername,
  password: mqttPassword,
  reconnectPeriod: 2000,
  clean: true,
  keepalive: 30,
});

const pendingByRequest = new Map();
const pendingByTopic = new Map();
let pollInFlight = false;

function nowIso() {
  return new Date().toISOString();
}

function plusDays(baseDate, days) {
  return new Date(baseDate.getTime() + days * 24 * 60 * 60 * 1000);
}

function computeExpireAt(baseDate = new Date()) {
  if (!enableExpireAtTtlWrites) {
    return null;
  }
  return admin.firestore.Timestamp.fromDate(plusDays(baseDate, plugLogRetentionDays));
}

function normalizePowerState(rawValue) {
  const value = String(rawValue || "").trim().toUpperCase();
  if (value === "ON" || value === "OFF") {
    return value;
  }
  return "UNKNOWN";
}

function parseStateFromPayload(payloadText) {
  if (!payloadText) return "UNKNOWN";

  const upper = payloadText.trim().toUpperCase();
  if (upper === "ON" || upper === "OFF") {
    return upper;
  }

  try {
    const parsed = JSON.parse(payloadText);
    if (parsed && typeof parsed === "object") {
      if (parsed.POWER !== undefined) {
        return normalizePowerState(parsed.POWER);
      }
      if (parsed.Power !== undefined) {
        return normalizePowerState(parsed.Power);
      }
    }
  } catch (_) {
    // Ignore invalid JSON payloads and fallback to UNKNOWN.
  }

  return "UNKNOWN";
}

function toBooleanOrNull(value) {
  if (typeof value === "boolean") return value;
  if (value === "true" || value === "1" || value === 1) return true;
  if (value === "false" || value === "0" || value === 0) return false;
  return null;
}

function toTimestampMs(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") {
    const ms = value.toMillis();
    return Number.isFinite(ms) ? ms : null;
  }
  if (typeof value.toDate === "function") {
    const ms = value.toDate().getTime();
    return Number.isFinite(ms) ? ms : null;
  }
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : null;
}

function extractTopicName(fullTopic) {
  const segments = String(fullTopic || "").split("/");
  if (segments.length < 2) return "";
  return String(segments[1] || "").trim();
}

function enqueuePendingByTopic(topicName, requestId) {
  const key = topicName.toLowerCase();
  const queue = pendingByTopic.get(key) || [];
  queue.push(requestId);
  pendingByTopic.set(key, queue);
}

function dequeuePendingByTopic(topicName) {
  const key = topicName.toLowerCase();
  const queue = pendingByTopic.get(key);
  if (!queue || !queue.length) return null;
  const requestId = queue.shift() || null;
  if (!queue.length) {
    pendingByTopic.delete(key);
  } else {
    pendingByTopic.set(key, queue);
  }
  return requestId;
}

function removePendingByTopic(topicName, requestId) {
  const key = topicName.toLowerCase();
  const queue = pendingByTopic.get(key);
  if (!queue || !queue.length) return;

  const nextQueue = queue.filter((id) => id !== requestId);
  if (!nextQueue.length) {
    pendingByTopic.delete(key);
    return;
  }
  pendingByTopic.set(key, nextQueue);
}

function publishAsync(topic, payload) {
  return new Promise((resolve, reject) => {
    client.publish(topic, payload, { qos: publishQos }, (error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
}

async function finalizeRequest({
  requestId,
  plugId,
  status,
  responseTopic,
  responsePayloadRaw,
  errorMessage,
  actualState,
  online,
  latencyMs,
}) {
  const requestRef = db.collection("plug_command_requests").doc(requestId);
  const queueRef = db.collection("plug_command_queue").doc(requestId);
  const responseRef = db.collection("plug_command_responses").doc();
  const nowTs = admin.firestore.FieldValue.serverTimestamp();
  const nowDate = new Date();
  const expireAt = computeExpireAt(nowDate);

  const safeState = normalizePowerState(actualState);
  const safeOnline = typeof online === "boolean" ? online : null;
  const safeLatency = Number.isFinite(latencyMs) ? Math.max(0, Math.round(latencyMs)) : 0;

  const batch = db.batch();
  batch.set(
    requestRef,
    {
      status,
      ackAt: nowTs,
      latencyMs: safeLatency,
      workerId,
      errorMessage: errorMessage || null,
      actualState: safeState,
      online: safeOnline,
      updatedAt: nowTs,
      expireAt,
    },
    { merge: true }
  );

  batch.set(
    queueRef,
    {
      status: status === "acknowledged" ? "processed" : status,
      processedAt: nowTs,
      updatedAt: nowTs,
      expireAt,
    },
    { merge: true }
  );

  batch.set(responseRef, {
    responseId: responseRef.id,
    requestId,
    plugId,
    status,
    responseTopic: responseTopic || null,
    responsePayloadRaw: responsePayloadRaw || null,
    errorMessage: errorMessage || null,
    actualState: safeState,
    online: safeOnline,
    latencyMs: safeLatency,
    workerId,
    createdAt: nowTs,
    updatedAt: nowTs,
    expireAt,
  });

  if (plugId) {
    batch.set(
      db.collection("plugs").doc(plugId),
      {
        plugId,
        actualState: safeState,
        online: safeOnline,
        lastAckRequestId: requestId,
        lastSeen: nowTs,
        updatedAt: nowTs,
      },
      { merge: true }
    );
  }

  await batch.commit();
}

async function markFailedBeforeDispatch(requestId, plugId, message) {
  try {
    await finalizeRequest({
      requestId,
      plugId,
      status: "failed",
      responseTopic: null,
      responsePayloadRaw: null,
      errorMessage: message,
      actualState: "UNKNOWN",
      online: null,
      latencyMs: 0,
    });
  } catch (error) {
    console.error(`[${nowIso()}] failed to mark request as failed`, requestId, error);
  }
}

async function dispatchCommand(requestId, data) {
  const queueRef = db.collection("plug_command_queue").doc(requestId);
  const queueSnap = await queueRef.get();
  if (!queueSnap.exists) {
    return;
  }

  const latestQueue = queueSnap.data() || {};
  if (latestQueue.status !== "pending") {
    return;
  }

  const plugId = String(latestQueue.plugId || data.plugId || "").trim();
  let tasmotaTopic = String(latestQueue.tasmotaTopic || "").trim();
  let plugData = {};
  if (plugId) {
    const plugSnap = await db.collection("plugs").doc(plugId).get();
    if (plugSnap.exists) {
      plugData = plugSnap.data() || {};
      if (!tasmotaTopic) {
        tasmotaTopic = String(plugData.tasmotaTopic || "").trim();
      }
    }
  }

  const queueMode = String(latestQueue.mode || "").trim().toLowerCase();
  const plugMode = String(plugData.mode || "").trim().toLowerCase();
  const mode = queueMode || plugMode;
  const online = toBooleanOrNull(plugData.online);
  const actualState = normalizePowerState(plugData.actualState);

  if (plugData.controlEnabled === false) {
    await finalizeRequest({
      requestId,
      plugId,
      status: "blocked_control_disabled",
      responseTopic: null,
      responsePayloadRaw: null,
      errorMessage: "plug_control_disabled",
      actualState,
      online,
      latencyMs: 0,
    });
    return;
  }

  const manualOverrideUntilMs = toTimestampMs(plugData.manualOverrideUntil);
  const manualOverrideActive = Number.isFinite(manualOverrideUntilMs)
    && manualOverrideUntilMs > Date.now();

  if (mode === "auto" && manualOverrideActive) {
    await finalizeRequest({
      requestId,
      plugId,
      status: "suppressed_manual_override",
      responseTopic: null,
      responsePayloadRaw: null,
      errorMessage: "manual_override_active",
      actualState,
      online,
      latencyMs: 0,
    });
    return;
  }

  if (!plugId || !tasmotaTopic) {
    await markFailedBeforeDispatch(requestId, plugId, "missing_plug_or_tasmota_topic");
    return;
  }

  const command = String(latestQueue.command || data.command || "").trim().toUpperCase();
  if (!["ON", "OFF", "TOGGLE"].includes(command)) {
    await markFailedBeforeDispatch(requestId, plugId, "invalid_command");
    return;
  }

  const nowTs = admin.firestore.FieldValue.serverTimestamp();
  await queueRef.set(
    {
      status: "dispatched",
      dispatchedAt: nowTs,
      tasmotaTopic,
      updatedAt: nowTs,
    },
    { merge: true }
  );

  const requestRef = db.collection("plug_command_requests").doc(requestId);
  await requestRef.set(
    {
      status: "sent",
      sentAt: nowTs,
      updatedAt: nowTs,
    },
    { merge: true }
  );

  const mqttTopic = `cmnd/${tasmotaTopic}/Power`;
  await publishAsync(mqttTopic, command);

  const sentAt = Date.now();
  pendingByRequest.set(requestId, {
    requestId,
    plugId,
    tasmotaTopic,
    command,
    sentAt,
  });
  enqueuePendingByTopic(tasmotaTopic, requestId);

  console.log(
    `[${nowIso()}] dispatched request=${requestId} plug=${plugId} topic=${tasmotaTopic} command=${command}`
  );
}

async function pollPendingQueue() {
  if (pollInFlight || !client.connected) return;
  pollInFlight = true;

  try {
    const snap = await db
      .collection("plug_command_queue")
      .where("status", "==", "pending")
      .limit(20)
      .get();

    if (snap.empty) return;

    for (const doc of snap.docs) {
      try {
        await dispatchCommand(doc.id, doc.data() || {});
      } catch (error) {
        const data = doc.data() || {};
        const plugId = String(data.plugId || "").trim();
        console.error(`[${nowIso()}] dispatch failed request=${doc.id}`, error);
        await markFailedBeforeDispatch(doc.id, plugId, error?.message || "dispatch_failed");
      }
    }
  } catch (error) {
    console.error(`[${nowIso()}] queue poll failed`, error);
  } finally {
    pollInFlight = false;
  }
}

async function handleResponseTopic(topic, payloadBuffer) {
  const tasmotaTopic = extractTopicName(topic);
  if (!tasmotaTopic) return;

  const requestId = dequeuePendingByTopic(tasmotaTopic);
  if (!requestId) return;

  const pending = pendingByRequest.get(requestId);
  if (!pending) return;

  pendingByRequest.delete(requestId);

  const payloadText = payloadBuffer ? payloadBuffer.toString("utf8") : "";
  const state = parseStateFromPayload(payloadText);
  const latencyMs = Date.now() - pending.sentAt;

  try {
    await finalizeRequest({
      requestId,
      plugId: pending.plugId,
      status: "acknowledged",
      responseTopic: topic,
      responsePayloadRaw: payloadText,
      errorMessage: null,
      actualState: state,
      online: true,
      latencyMs,
    });

    console.log(
      `[${nowIso()}] acknowledged request=${requestId} plug=${pending.plugId} state=${state} latencyMs=${latencyMs}`
    );
  } catch (error) {
    console.error(`[${nowIso()}] failed to finalize acknowledged request=${requestId}`, error);
  }
}

async function flushTimeouts() {
  const now = Date.now();
  const timeoutIds = [];

  for (const [requestId, pending] of pendingByRequest.entries()) {
    if (now - pending.sentAt >= commandTimeoutMs) {
      timeoutIds.push(requestId);
    }
  }

  for (const requestId of timeoutIds) {
    const pending = pendingByRequest.get(requestId);
    if (!pending) continue;

    pendingByRequest.delete(requestId);
    removePendingByTopic(pending.tasmotaTopic, requestId);

    try {
      await finalizeRequest({
        requestId,
        plugId: pending.plugId,
        status: "timeout",
        responseTopic: null,
        responsePayloadRaw: null,
        errorMessage: "command_response_timeout",
        actualState: "UNKNOWN",
        online: null,
        latencyMs: commandTimeoutMs,
      });

      console.warn(
        `[${nowIso()}] timeout request=${requestId} plug=${pending.plugId} topic=${pending.tasmotaTopic}`
      );
    } catch (error) {
      console.error(`[${nowIso()}] failed to finalize timeout request=${requestId}`, error);
    }
  }
}

client.on("connect", () => {
  console.log(`[${nowIso()}] MQTT connected as ${workerId}`);

  client.subscribe("stat/+/RESULT", { qos: subscribeQos }, (error) => {
    if (error) {
      console.error(`[${nowIso()}] subscribe failed for stat/+/RESULT`, error);
    }
  });

  client.subscribe("stat/+/POWER", { qos: subscribeQos }, (error) => {
    if (error) {
      console.error(`[${nowIso()}] subscribe failed for stat/+/POWER`, error);
    }
  });

  client.subscribe("tele/+/LWT", { qos: subscribeQos }, (error) => {
    if (error) {
      console.error(`[${nowIso()}] subscribe failed for tele/+/LWT`, error);
    }
  });
});

client.on("reconnect", () => {
  console.log(`[${nowIso()}] MQTT reconnecting...`);
});

client.on("error", (error) => {
  console.error(`[${nowIso()}] MQTT error`, error);
});

client.on("message", async (topic, payload) => {
  try {
    if (topic.startsWith("stat/")) {
      await handleResponseTopic(topic, payload);
      return;
    }

    if (topic.startsWith("tele/") && topic.endsWith("/LWT")) {
      const tasmotaTopic = extractTopicName(topic);
      if (!tasmotaTopic) return;
      const isOnline = payload.toString("utf8").trim().toLowerCase() === "online";

      await db
        .collection("plugs")
        .where("tasmotaTopic", "==", tasmotaTopic)
        .limit(20)
        .get()
        .then(async (snap) => {
          const nowTs = admin.firestore.FieldValue.serverTimestamp();
          const batch = db.batch();
          snap.docs.forEach((doc) => {
            batch.set(
              doc.ref,
              {
                online: isOnline,
                lastSeen: nowTs,
                updatedAt: nowTs,
              },
              { merge: true }
            );
          });
          if (!snap.empty) {
            await batch.commit();
          }
        });
    }
  } catch (error) {
    console.error(`[${nowIso()}] message handling failed topic=${topic}`, error);
  }
});

setInterval(() => {
  pollPendingQueue().catch((error) => {
    console.error(`[${nowIso()}] polling loop failure`, error);
  });
}, pollIntervalMs);

setInterval(() => {
  flushTimeouts().catch((error) => {
    console.error(`[${nowIso()}] timeout loop failure`, error);
  });
}, 1000);

console.log(`[${nowIso()}] ${workerId} started`);
