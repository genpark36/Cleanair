const admin = require("firebase-admin");
const mqtt = require("mqtt");
const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions");
const { generateAlertsFromSnapshot, DEFAULT_QUIET_HOURS } = require("./alertEngine");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

function toMinutes(hhmm) {
  if (!hhmm) return null;
  const [h, m] = String(hhmm).split(":").map((part) => parseInt(part, 10));
  return h * 60 + (m || 0);
}

function isWithinQuietHours(window, timezone) {
  const startMinutes = toMinutes(window?.start);
  const endMinutes = toMinutes(window?.end);
  if (startMinutes == null || endMinutes == null) return false;
  const now = timezone
    ? new Date(new Date().toLocaleString("en-US", { timeZone: timezone }))
    : new Date();
  const minutes = now.getHours() * 60 + now.getMinutes();
  if (startMinutes === endMinutes) return false;
  if (startMinutes < endMinutes) {
    return minutes >= startMinutes && minutes < endMinutes;
  }
  return minutes >= startMinutes || minutes < endMinutes;
}

function normalizeNotificationIntervalMinutes(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 15;
  return Math.max(1, Math.min(24 * 60, Math.round(parsed)));
}

function normalizeMinimumSeverityPriority(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 2;
  return Math.max(1, Math.min(3, Math.round(parsed)));
}

function eventSeverityPriority(severity) {
  const ranks = { notice: 1, warning: 2, critical: 3 };
  return ranks[String(severity || "").toLowerCase()] || 1;
}

function minimumSeverityForEvent(device, event) {
  const byType = device?.minimumSeverityByType;
  const typeValue = byType && typeof byType === "object"
    ? byType[event.type]
    : undefined;
  return normalizeMinimumSeverityPriority(
    typeValue ?? device?.minimumSeverityPriority ?? device?.minimumAlertSeverityPriority
  );
}

function normalizeFireRiskMinimumLevel(value) {
  const level = String(value || "").toLowerCase();
  if (level === "warning" || level === "strong_warning" || level === "fire_suspected") {
    return level;
  }
  return "strong_warning";
}

function fireRiskLevelPriority(level) {
  const ranks = {
    warning: 1,
    strong_warning: 2,
    fire_suspected: 3,
    co_only: 3,
  };
  return ranks[String(level || "").toLowerCase()] || 1;
}

function dateFromMaybeTimestamp(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function shouldDeliver(event, device) {
  if (device?.alertsEnabled === false) return false;
  if (device?.mutedTypes && device.mutedTypes[event.type]) return false;
  const isFireRisk = event.type === "fire_risk";
  if (isFireRisk && event.severity === "notice") return false;
  if (isFireRisk) {
    const minimumLevel = normalizeFireRiskMinimumLevel(device?.fireRiskMinimumLevel);
    const eventLevel = event?.trendMeta?.code || event?.level || event?.fireRiskLevel;
    if (fireRiskLevelPriority(eventLevel) < fireRiskLevelPriority(minimumLevel)) {
      return false;
    }
  }

  const snoozedUntil = device?.snoozedUntil
    ? new Date(device.snoozedUntil)
    : null;
  if (snoozedUntil && Date.now() < snoozedUntil.getTime()) {
    return event.severity === "critical";
  }

  if (event.severity === "critical") return true;

  if (!isFireRisk) {
    const minimumSeverityPriority = minimumSeverityForEvent(device, event);
    if (eventSeverityPriority(event.severity) < minimumSeverityPriority) {
      return false;
    }
  }

  const intervalMinutes = normalizeNotificationIntervalMinutes(
    device?.notificationIntervalMinutes ?? device?.cooldownMinutes
  );
  const lastDeliveredAt = dateFromMaybeTimestamp(
    device?.lastDeliveredByType?.[event.type]
  );
  if (
    lastDeliveredAt &&
    Date.now() - lastDeliveredAt.getTime() < intervalMinutes * 60 * 1000
  ) {
    return false;
  }

  const quietEnabled = device?.quietHoursEnabled ?? Boolean(device?.quietHours);
  if (!quietEnabled) return true;
  if (!device?.quietHours) return true;

  const inQuiet = isWithinQuietHours(device.quietHours, device?.timezone);
  if (!inQuiet) return true;

  return Boolean(event.quietHours === false);
}

function compactSensorId(sensorId) {
  return String(sensorId || "")
    .trim()
    .replace(/^airgradient:/i, "")
    .replace(/[^a-fA-F0-9]/g, "")
    .toLowerCase();
}

function toColonMac(compact, upperCase = false) {
  if (compact.length !== 12) return null;
  const parts = compact.match(/.{1,2}/g);
  if (!parts) return null;
  const joined = parts.join(":");
  return upperCase ? joined.toUpperCase() : joined.toLowerCase();
}

function buildSensorIdCandidates(sensorId) {
  const raw = String(sensorId || "").trim();
  const noPrefix = raw.replace(/^airgradient:/i, "");
  const compact = compactSensorId(raw);
  const lowerColon = toColonMac(compact, false);
  const upperColon = toColonMac(compact, true);

  return [...new Set([
    raw,
    noPrefix,
    compact,
    lowerColon,
    upperColon,
    compact ? `airgradient:${compact}` : null,
    lowerColon ? `airgradient:${lowerColon}` : null,
    upperColon ? `airgradient:${upperColon}` : null,
  ].filter((value) => typeof value === "string" && value.length > 0))];
}

async function listDevicesForSensor(sensorId) {
  const candidates = buildSensorIdCandidates(sensorId);
  if (!candidates.length) return [];

  const snapshot = candidates.length === 1
    ? await db.collection("devices").where("sensorId", "==", candidates[0]).get()
    : await db.collection("devices").where("sensorId", "in", candidates).get();

  return snapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));
}

function resolvePushToken(device) {
  if (!device || device.pushDisabled === true) {
    return null;
  }

  if (typeof device.fcmToken === "string" && device.fcmToken.trim()) {
    return device.fcmToken.trim();
  }

  if (typeof device.token === "string" && device.token.trim()) {
    const legacyToken = device.token.trim();
    if (legacyToken.startsWith("local-client-")) {
      return null;
    }
    return legacyToken;
  }

  return null;
}

async function sendPushToDevice(event, device) {
  const token = resolvePushToken(device);
  if (!token) return;

  try {
    await admin.messaging().send({
      token,
      notification: {
        title: event.title,
        body: event.message,
      },
      android: {
        priority: event.type === "fire_risk" && event.severity === "critical" ? "high" : "normal",
        notification: {
          channelId:
            event.type === "fire_risk" && event.severity === "critical"
              ? "iaq_emergency_alerts"
              : "iaq_alerts",
          sound: "default",
        },
      },
      data: {
        type: String(event.type || ""),
        severity: String(event.severity || ""),
        sensorId: String(event.sensorId || ""),
        eventId: String(event.eventId || ""),
      },
    });
    try {
      await db.collection("devices").doc(device.id).set(
        {
          lastDeliveredAt: admin.firestore.FieldValue.serverTimestamp(),
          lastDeliveredByType: {
            [String(event.type || "unknown")]: new Date().toISOString(),
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } catch (writeError) {
      logger.warn("push_delivery_state_update_failed", {
        deviceId: device.id,
        eventId: event.eventId,
        error: writeError?.message || writeError,
      });
    }
  } catch (error) {
    const code = error?.errorInfo?.code || error?.code;
    if (code === "messaging/registration-token-not-registered") {
      logger.warn("remove_invalid_fcm_token", { tokenPrefix: token.slice(0, 12) });
      await db.collection("devices").doc(device.id).set(
        {
          fcmToken: null,
          pushDisabled: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return;
    }
    throw error;
  }
}

async function dispatchAlertsForSnapshot(snapshotPayload) {
  const events = await generateAlertsFromSnapshot(snapshotPayload, {
    quietHoursWindow: DEFAULT_QUIET_HOURS,
    firestore: db,
  });

  if (!events.length) return;

  const sensorId = snapshotPayload.serial;
  const devices = await listDevicesForSensor(sensorId);

  for (const event of events) {
    if (event.suppressed) {
      logger.info("alert_suppressed", { sensorId, eventId: event.eventId, type: event.type });
      continue;
    }

    const alertDoc = {
      ...event,
      sensorId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("alerts").add(alertDoc);

    for (const device of devices) {
      if (!shouldDeliver(event, device)) {
        continue;
      }

      try {
        await sendPushToDevice({ ...event, sensorId }, device);
      } catch (error) {
        logger.error("push_send_failed", {
          sensorId,
          eventId: event.eventId,
          deviceId: device.id,
          error: error?.message || error,
        });
      }
    }
  }
}

function badRequest(res, message) {
  return res.status(400).json({ ok: false, error: message });
}

function unauthorized(res) {
  return res.status(401).json({ ok: false, error: "invalid_api_key" });
}

function toDateOrNow(value) {
  if (!value) {
    return new Date();
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return new Date();
  }
  return parsed;
}

function toFiniteNumber(value, fallback = 0) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return fallback;
}

function normalizeLegacyScaledIaqi(value) {
  if (!Number.isFinite(value)) return value;
  // Legacy IAQI thresholds used a 0~500-like scale via m_score * 100.
  // If we see a large threshold, normalize it back to raw m_score scale.
  return Math.abs(value) > 10 ? value / 100 : value;
}

function normalizeQuietHours(value) {
  if (!value) return null;
  const start = typeof value.start === "string" ? value.start : null;
  const end = typeof value.end === "string" ? value.end : null;
  if (!start || !end) return null;
  return { start, end };
}

function parseSnoozedUntil(value) {
  if (!value) return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return null;
  return admin.firestore.Timestamp.fromDate(parsed);
}

function ensurePost(req, res) {
  if (req.method !== "POST") {
    res.status(405).json({ ok: false, error: "method_not_allowed" });
    return false;
  }
  return true;
}

function validateOptionalApiKey(req, res) {
  const requiredApiKey = process.env.DEVICE_API_KEY || process.env.INGEST_API_KEY || null;
  if (!requiredApiKey) return true;
  const incomingApiKey = req.get("X-API-Key");
  if (incomingApiKey !== requiredApiKey) {
    unauthorized(res);
    return false;
  }
  return true;
}

const DEVICE_CODE_TTL_MINUTES = Number(process.env.DEVICE_CODE_TTL_MINUTES || 10);
const MANUAL_OVERRIDE_DEFAULT_SECONDS = Number(
  process.env.MANUAL_OVERRIDE_DEFAULT_SECONDS || 15 * 60
);
const DEFAULT_AUTO_AQI_ON = normalizeLegacyScaledIaqi(
  toFiniteNumber(process.env.AUTO_AQI_ON, 1.2)
);
const DEFAULT_AUTO_AQI_HYSTERESIS = normalizeLegacyScaledIaqi(
  toFiniteNumber(process.env.AUTO_AQI_HYSTERESIS, 0.3)
);
const DEFAULT_AUTO_AQI_OFF = normalizeLegacyScaledIaqi(
  toFiniteNumber(
    process.env.AUTO_AQI_OFF,
    DEFAULT_AUTO_AQI_ON - Math.abs(DEFAULT_AUTO_AQI_HYSTERESIS)
  )
);
const DEFAULT_AUTO_COMMAND_INTERVAL_SECONDS = toPositiveInt(
  process.env.AUTO_COMMAND_INTERVAL_SECONDS,
  120
);
const DISABLE_SENSOR_HISTORY_WRITES = isEnvTrue(process.env.DISABLE_SENSOR_HISTORY_WRITES);
const DISABLE_RELAY_SERIES_WRITES = isEnvTrue(process.env.DISABLE_RELAY_SERIES_WRITES);
const DISABLE_RELAY_HISTORY_WRITES = isEnvTrue(process.env.DISABLE_RELAY_HISTORY_WRITES);
const DISABLE_PLUG_DECISION_LOG = isEnvTrue(process.env.DISABLE_PLUG_DECISION_LOG);
const DISABLE_PLUG_STATE_HISTORY_WRITES = isEnvTrue(process.env.DISABLE_PLUG_STATE_HISTORY_WRITES);
const INGEST_MIN_INTERVAL_SECONDS = toPositiveInt(process.env.INGEST_MIN_INTERVAL_SECONDS, 0);
const SENSOR_HISTORY_RETENTION_DAYS = toPositiveInt(process.env.SENSOR_HISTORY_RETENTION_DAYS, 30);
const PLUG_LOG_RETENTION_DAYS = toPositiveInt(process.env.PLUG_LOG_RETENTION_DAYS, 90);
const IAQI_K_REGRESSION_WINDOW_MS =
  toPositiveInt(process.env.IAQI_K_REGRESSION_WINDOW_SECONDS, 300) * 1000;
const IAQI_K_REGRESSION_HISTORY_LIMIT = toPositiveInt(
  process.env.IAQI_K_REGRESSION_HISTORY_LIMIT,
  400
);
const IAQI_K_REGRESSION_MIN_SAMPLES = toPositiveInt(
  process.env.IAQI_K_REGRESSION_MIN_SAMPLES,
  15
);
const IAQI_K_PM_NOISE_THRESHOLD = toFiniteNumber(
  process.env.IAQI_K_PM_NOISE_THRESHOLD,
  0.99
);
const IAQI_K_CO2_BASELINE = toFiniteNumber(process.env.IAQI_K_CO2_BASELINE, 420);
const CLEANUP_MAX_DELETES_PER_RUN = toPositiveInt(process.env.CLEANUP_MAX_DELETES_PER_RUN, 200000);
const ENABLE_EXPIREAT_TTL_WRITES = process.env.ENABLE_EXPIREAT_TTL_WRITES === undefined
  ? true
  : isEnvTrue(process.env.ENABLE_EXPIREAT_TTL_WRITES);
const TTL_SENSOR_COLLECTIONS_ENABLED = isEnvTrue(process.env.TTL_SENSOR_COLLECTIONS_ENABLED);
const TTL_PLUG_LOG_COLLECTIONS_ENABLED = isEnvTrue(process.env.TTL_PLUG_LOG_COLLECTIONS_ENABLED);
const MQTT_URL = String(process.env.MQTT_URL || "").trim();
const MQTT_USERNAME = process.env.MQTT_USERNAME || undefined;
const MQTT_PASSWORD = process.env.MQTT_PASSWORD || undefined;
const ENABLE_FUNCTION_MQTT_COMMANDS = process.env.ENABLE_FUNCTION_MQTT_COMMANDS === undefined
  ? Boolean(MQTT_URL)
  : isEnvTrue(process.env.ENABLE_FUNCTION_MQTT_COMMANDS);
const FUNCTION_MQTT_ACK_TIMEOUT_MS = toPositiveInt(
  process.env.FUNCTION_MQTT_ACK_TIMEOUT_MS,
  8000
);

const ingestCommitCache = new Map();
const INGEST_COMMIT_CACHE_LIMIT = 5000;

function generateDeviceCode() {
  const code = Math.floor(100000 + Math.random() * 900000);
  return String(code);
}

function normalizePlugId(rawValue) {
  if (!rawValue) return "";
  return String(rawValue).trim();
}

function normalizePowerCommand(rawValue) {
  const command = String(rawValue || "").trim().toUpperCase();
  if (["ON", "OFF", "TOGGLE"].includes(command)) {
    return command;
  }
  return "";
}

function normalizePowerState(rawValue) {
  const value = String(rawValue || "").trim().toUpperCase();
  if (value === "ON" || value === "OFF") {
    return value;
  }
  return "UNKNOWN";
}

function parsePowerStateFromPayload(payloadText) {
  const text = String(payloadText || "").trim();
  const direct = normalizePowerState(text);
  if (direct !== "UNKNOWN") return direct;

  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== "object") return "UNKNOWN";
    if (parsed.POWER !== undefined) return normalizePowerState(parsed.POWER);
    if (parsed.Power !== undefined) return normalizePowerState(parsed.Power);
  } catch (_) {
    // MQTT payloads can be plain ON/OFF strings.
  }

  return "UNKNOWN";
}

function normalizeTasmotaTelemetry(payloadText) {
  let parsed = null;
  try {
    parsed = typeof payloadText === "string" ? JSON.parse(payloadText) : payloadText;
  } catch (_) {
    return null;
  }

  if (!parsed || typeof parsed !== "object") return null;
  const energy = parsed?.StatusSNS?.ENERGY
    || parsed?.ENERGY
    || parsed?.Energy
    || parsed?.energy
    || null;
  if (!energy || typeof energy !== "object") return null;

  const telemetry = {
    voltage: toFiniteNumberOrNull(energy.Voltage ?? energy.voltage),
    current: toFiniteNumberOrNull(energy.Current ?? energy.current),
    power: toFiniteNumberOrNull(energy.Power ?? energy.power ?? energy.ActivePower),
    apparentPower: toFiniteNumberOrNull(energy.ApparentPower ?? energy.apparentPower),
    reactivePower: toFiniteNumberOrNull(energy.ReactivePower ?? energy.reactivePower),
    factor: toFiniteNumberOrNull(energy.Factor ?? energy.PowerFactor ?? energy.factor),
    today: toFiniteNumberOrNull(energy.Today ?? energy.today),
    yesterday: toFiniteNumberOrNull(energy.Yesterday ?? energy.yesterday),
    total: toFiniteNumberOrNull(energy.Total ?? energy.total),
  };
  const cleaned = Object.fromEntries(
    Object.entries(telemetry).filter(([, value]) => Number.isFinite(value))
  );
  return Object.keys(cleaned).length ? cleaned : null;
}

function plugTelemetryUpdateFields(telemetry) {
  if (!telemetry || typeof telemetry !== "object") return {};
  const update = { telemetry };
  if (Number.isFinite(telemetry.voltage)) update.voltage = telemetry.voltage;
  if (Number.isFinite(telemetry.current)) update.current = telemetry.current;
  if (Number.isFinite(telemetry.power)) {
    update.power = telemetry.power;
    update.powerWatts = telemetry.power;
  }
  if (Number.isFinite(telemetry.apparentPower)) update.apparentPower = telemetry.apparentPower;
  if (Number.isFinite(telemetry.reactivePower)) update.reactivePower = telemetry.reactivePower;
  if (Number.isFinite(telemetry.factor)) update.powerFactor = telemetry.factor;
  if (Number.isFinite(telemetry.today)) update.energyToday = telemetry.today;
  if (Number.isFinite(telemetry.yesterday)) update.energyYesterday = telemetry.yesterday;
  if (Number.isFinite(telemetry.total)) update.energyTotal = telemetry.total;
  return update;
}

function shouldUseFunctionMqttDispatch(transportHint, tasmotaTopic) {
  if (!ENABLE_FUNCTION_MQTT_COMMANDS || !MQTT_URL) return false;
  if (!String(tasmotaTopic || "").trim()) return false;
  const hint = String(transportHint || "").trim().toUpperCase();
  return !hint || hint === "MQTT" || hint === "CLOUD";
}

function normalizeAutoMetric(rawValue) {
  const value = String(rawValue || "").trim().toLowerCase();
  if (["iaqi", "co2", "pm25", "tvoc", "nox"].includes(value)) {
    return value;
  }
  return "iaqi";
}

function autoMetricLabel(metric) {
  switch (normalizeAutoMetric(metric)) {
    case "co2":
      return "CO2";
    case "pm25":
      return "PM2.5";
    case "tvoc":
      return "TVOC";
    case "nox":
      return "NOx";
    case "iaqi":
    default:
      return "IAQI";
  }
}

function toBooleanOrNull(value) {
  if (typeof value === "boolean") return value;
  if (value === "true" || value === "1" || value === 1) return true;
  if (value === "false" || value === "0" || value === 0) return false;
  return null;
}

function toPositiveInt(value, fallback) {
  const parsed = Number(value);
  if (Number.isFinite(parsed) && parsed > 0) {
    return Math.floor(parsed);
  }
  return fallback;
}

function isEnvTrue(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return ["1", "true", "yes", "y", "on"].includes(normalized);
}

function shouldThrottleIngest(sensorId, measuredAt) {
  if (!INGEST_MIN_INTERVAL_SECONDS) {
    return false;
  }

  const nowMs = measuredAt instanceof Date ? measuredAt.getTime() : Date.now();
  const previousMs = ingestCommitCache.get(sensorId);
  if (Number.isFinite(previousMs) && nowMs - previousMs < INGEST_MIN_INTERVAL_SECONDS * 1000) {
    return true;
  }

  ingestCommitCache.set(sensorId, nowMs);
  if (ingestCommitCache.size > INGEST_COMMIT_CACHE_LIMIT) {
    const oldestKey = ingestCommitCache.keys().next().value;
    if (oldestKey) {
      ingestCommitCache.delete(oldestKey);
    }
  }

  return false;
}

function plusDays(baseDate, days) {
  const safeBaseDate = baseDate instanceof Date ? baseDate : new Date(baseDate || Date.now());
  return new Date(safeBaseDate.getTime() + days * 24 * 60 * 60 * 1000);
}

function computeExpireAtTimestamp(retentionDays, baseDate = new Date()) {
  if (!ENABLE_EXPIREAT_TTL_WRITES) {
    return null;
  }

  const safeRetentionDays = toPositiveInt(retentionDays, 0);
  if (!safeRetentionDays) {
    return null;
  }

  return admin.firestore.Timestamp.fromDate(plusDays(baseDate, safeRetentionDays));
}

function withExpireAt(payload, retentionDays, baseDate = new Date()) {
  const expireAt = computeExpireAtTimestamp(retentionDays, baseDate);
  if (!expireAt) {
    return payload;
  }

  return {
    ...payload,
    expireAt,
  };
}

function publishMqttCommandAndWait({
  requestId,
  tasmotaTopic,
  command,
  desiredState,
}) {
  return new Promise((resolve) => {
    const startedAt = Date.now();
    const safeTopic = String(tasmotaTopic || "").trim();
    const mqttCommand = normalizePowerCommand(command);
    const expectedState = normalizePowerState(desiredState);
    const clientId = `cleanair-fn-${requestId.slice(0, 12)}-${Date.now()}`;
    const commandTopic = `cmnd/${safeTopic}/POWER`;
    const statusTopic = `cmnd/${safeTopic}/STATUS`;
    const resultPrefix = `stat/${safeTopic}/`;
    const telemetryTopics = [
      `tele/${safeTopic}/SENSOR`,
      `stat/${safeTopic}/STATUS8`,
    ];
    const subscriptions = [
      `stat/${safeTopic}/POWER`,
      `stat/${safeTopic}/RESULT`,
      ...telemetryTopics,
    ];

    if (!MQTT_URL || !safeTopic || !mqttCommand) {
      resolve({
        ok: false,
        status: "failed",
        errorMessage: "mqtt_not_configured",
        actualState: "UNKNOWN",
        latencyMs: 0,
      });
      return;
    }

    let done = false;
    let publishIssued = false;
    let latestTelemetry = null;
    let pendingAck = null;
    let ackDelayTimer = null;
    const client = mqtt.connect(MQTT_URL, {
      username: MQTT_USERNAME,
      password: MQTT_PASSWORD,
      clientId,
      clean: true,
      keepalive: 30,
      connectTimeout: 5000,
      reconnectPeriod: 0,
    });

    function finish(result) {
      if (done) return;
      done = true;
      clearTimeout(timer);
      clearTimeout(ackDelayTimer);
      try {
        client.end(true);
      } catch (_) {
        // Ignore MQTT socket cleanup errors after the command result is known.
      }
      resolve(result);
    }

    function finishWithTelemetryDelay(result) {
      if (done) return;
      pendingAck = result;
      ackDelayTimer = setTimeout(() => {
        finish({
          ...pendingAck,
          telemetry: latestTelemetry,
        });
      }, 550);
    }

    const timer = setTimeout(() => {
      finish({
        ok: false,
        status: "timeout",
        errorMessage: "mqtt_ack_timeout",
        responseTopic: null,
        responsePayloadRaw: null,
        actualState: "UNKNOWN",
        latencyMs: Date.now() - startedAt,
      });
    }, FUNCTION_MQTT_ACK_TIMEOUT_MS);

    client.on("connect", () => {
      client.subscribe(subscriptions, { qos: 1 }, (subscribeError) => {
        if (subscribeError) {
          finish({
            ok: false,
            status: "failed",
            errorMessage: subscribeError.message || "mqtt_subscribe_failed",
            actualState: "UNKNOWN",
            latencyMs: Date.now() - startedAt,
          });
          return;
        }

        publishIssued = true;
        client.publish(statusTopic, "8", { qos: 1 }, () => {});
        client.publish(commandTopic, mqttCommand, { qos: 1 }, (publishError) => {
          if (publishError) {
            finish({
              ok: false,
              status: "failed",
              errorMessage: publishError.message || "mqtt_publish_failed",
              actualState: "UNKNOWN",
              latencyMs: Date.now() - startedAt,
            });
          }
        });
      });
    });

    client.on("message", (topic, payload) => {
      if (!publishIssued) return;
      const safeMessageTopic = String(topic || "");
      const payloadText = payload ? payload.toString("utf8") : "";
      if (telemetryTopics.includes(safeMessageTopic)) {
        latestTelemetry = normalizeTasmotaTelemetry(payloadText) || latestTelemetry;
        return;
      }
      if (!safeMessageTopic.startsWith(resultPrefix)) return;
      const actualState = parsePowerStateFromPayload(payloadText);
      if (actualState === "UNKNOWN") return;
      if (expectedState !== "UNKNOWN" && actualState !== expectedState) return;

      client.publish(statusTopic, "8", { qos: 1 }, () => {});
      finishWithTelemetryDelay({
        ok: true,
        status: "acknowledged",
        responseTopic: topic,
        responsePayloadRaw: payloadText,
        actualState,
        latencyMs: Date.now() - startedAt,
      });
    });

    client.on("error", (error) => {
      finish({
        ok: false,
        status: "failed",
        errorMessage: error?.message || "mqtt_error",
        actualState: "UNKNOWN",
        latencyMs: Date.now() - startedAt,
      });
    });
  });
}

async function finalizePlugCommandRequest({
  requestId,
  plugId,
  status,
  responseTopic,
  responsePayloadRaw,
  errorMessage,
  actualState,
  online,
  latencyMs,
  workerId,
  telemetry,
}) {
  const requestRef = db.collection("plug_command_requests").doc(requestId);
  const queueRef = db.collection("plug_command_queue").doc(requestId);
  const responseRef = db.collection("plug_command_responses").doc();
  const nowTs = admin.firestore.FieldValue.serverTimestamp();
  const nowDate = new Date();
  const safeStatus = status || "failed";
  const safeState = normalizePowerState(actualState);
  const safeOnline = typeof online === "boolean" ? online : null;
  const safeLatency = Number.isFinite(latencyMs) ? Math.max(0, Math.round(latencyMs)) : 0;
  const safeTelemetry = telemetry && typeof telemetry === "object" ? telemetry : null;
  const telemetryUpdate = plugTelemetryUpdateFields(safeTelemetry);

  await db.runTransaction(async (tx) => {
    tx.set(requestRef, {
      status: safeStatus,
      ackAt: safeStatus === "acknowledged" ? nowTs : null,
      latencyMs: safeLatency,
      workerId: workerId || "firebase-function-mqtt",
      errorMessage: errorMessage || null,
      actualState: safeState,
      online: safeOnline,
      updatedAt: nowTs,
    }, { merge: true });

    tx.set(queueRef, {
      status: safeStatus === "acknowledged" ? "processed" : safeStatus,
      processedAt: nowTs,
      updatedAt: nowTs,
    }, { merge: true });

    tx.set(
      responseRef,
      withExpireAt(
        {
          responseId: responseRef.id,
          requestId,
          plugId,
          status: safeStatus,
          responseTopic: responseTopic || null,
          responsePayloadRaw: responsePayloadRaw || null,
          errorMessage: errorMessage || null,
          actualState: safeState,
          online: safeOnline,
          latencyMs: safeLatency,
          telemetry: safeTelemetry,
          workerId: workerId || "firebase-function-mqtt",
          createdAt: nowTs,
          updatedAt: nowTs,
        },
        PLUG_LOG_RETENTION_DAYS,
        nowDate
      )
    );

    if (plugId) {
      tx.set(db.collection("plugs").doc(plugId), {
        plugId,
        actualState: safeState,
        online: safeOnline,
        ...telemetryUpdate,
        lastAckRequestId: requestId,
        lastSeen: safeOnline === false ? null : nowTs,
        updatedAt: nowTs,
        createdAt: nowTs,
      }, { merge: true });
    }
  });

  if (plugId && !DISABLE_PLUG_STATE_HISTORY_WRITES) {
    await db.collection("plug_state_history").add(
      withExpireAt(
        {
          plugId,
          actualState: safeState,
          online: safeOnline,
          telemetry: safeTelemetry,
          source: workerId || "firebase-function-mqtt",
          requestId,
          createdAt: nowTs,
        },
        PLUG_LOG_RETENTION_DAYS,
        nowDate
      )
    );
  }
}

async function dispatchQueuedCommandWithFunctionMqtt({
  requestId,
  plugId,
  tasmotaTopic,
  command,
  desiredState,
}) {
  const queueRef = db.collection("plug_command_queue").doc(requestId);
  const requestRef = db.collection("plug_command_requests").doc(requestId);
  const nowTs = admin.firestore.FieldValue.serverTimestamp();

  await queueRef.set({
    status: "function_dispatching",
    dispatchedAt: nowTs,
    dispatcher: "firebase-function-mqtt",
    updatedAt: nowTs,
  }, { merge: true });
  await requestRef.set({
    status: "sent",
    sentAt: nowTs,
    dispatcher: "firebase-function-mqtt",
    updatedAt: nowTs,
  }, { merge: true });

  const result = await publishMqttCommandAndWait({
    requestId,
    tasmotaTopic,
    command,
    desiredState,
  });

  await finalizePlugCommandRequest({
    requestId,
    plugId,
    status: result.status,
    responseTopic: result.responseTopic || null,
    responsePayloadRaw: result.responsePayloadRaw || null,
    errorMessage: result.errorMessage || null,
    actualState: result.actualState || "UNKNOWN",
    online: result.ok ? true : null,
    latencyMs: result.latencyMs,
    workerId: "firebase-function-mqtt",
    telemetry: result.telemetry || null,
  });

  return result;
}

function roundTo(value, digits = 3) {
  const factor = Math.pow(10, digits);
  return Math.round(value * factor) / factor;
}

function runLogLinearRegression(samples, valueSelector, options = {}) {
  const minSamples = toPositiveInt(options.minSamples, IAQI_K_REGRESSION_MIN_SAMPLES);
  const checkNoise = options.checkNoise === true;
  const noiseThreshold = toFiniteNumber(options.noiseThreshold, IAQI_K_PM_NOISE_THRESHOLD);

  const normalized = samples
    .filter((sample) => Number.isFinite(sample?.t) && Number.isFinite(sample?.v))
    .sort((a, b) => a.t - b.t);

  if (normalized.length < minSamples) {
    return {
      valid: false,
      k: null,
      r2: null,
      sampleCount: normalized.length,
    };
  }

  if (checkNoise) {
    const maxVal = normalized.reduce((maxValue, sample) => Math.max(maxValue, sample.v), -Infinity);
    if (!Number.isFinite(maxVal) || maxVal < noiseThreshold) {
      return {
        valid: false,
        k: null,
        r2: null,
        sampleCount: normalized.length,
      };
    }
  }

  const firstTs = normalized[0].t;
  const points = [];

  for (const sample of normalized) {
    const x = (sample.t - firstTs) / 3600000;
    const y = Number(valueSelector(sample));
    if (!Number.isFinite(x) || !Number.isFinite(y)) {
      continue;
    }
    points.push({ x, y });
  }

  const n = points.length;
  if (n < minSamples) {
    return {
      valid: false,
      k: null,
      r2: null,
      sampleCount: n,
    };
  }

  let sumX = 0;
  let sumY = 0;
  let sumXY = 0;
  let sumXX = 0;
  let sumYY = 0;

  for (const point of points) {
    sumX += point.x;
    sumY += point.y;
    sumXY += point.x * point.y;
    sumXX += point.x * point.x;
    sumYY += point.y * point.y;
  }

  const denom = (n * sumXX) - (sumX * sumX);
  if (!Number.isFinite(denom) || denom === 0) {
    return {
      valid: false,
      k: null,
      r2: null,
      sampleCount: n,
    };
  }

  const slope = ((n * sumXY) - (sumX * sumY)) / denom;
  const intercept = (sumY - slope * sumX) / n;
  const ssTot = sumYY - ((sumY * sumY) / n);
  let ssRes = 0;

  for (const point of points) {
    const fitted = (slope * point.x) + intercept;
    ssRes += (point.y - fitted) * (point.y - fitted);
  }

  const r2 = ssTot === 0 ? 1 : Math.max(0, 1 - (ssRes / ssTot));
  const k = roundTo(-slope, 3);

  return {
    valid: Number.isFinite(k),
    k: Number.isFinite(k) ? k : null,
    r2: Number.isFinite(r2) ? roundTo(r2, 4) : null,
    sampleCount: n,
  };
}

async function resolveIaqiKValue({
  sensorRef,
  measuredAt,
  pm25,
  co2,
}) {
  const measuredAtMs = toMillisOrNull(measuredAt) || Date.now();
  const windowStartMs = measuredAtMs - IAQI_K_REGRESSION_WINDOW_MS;

  const pmSamples = [];
  const co2Samples = [];

  try {
    const historySnap = await sensorRef
      .collection("history")
      .orderBy("createdAt", "desc")
      .limit(IAQI_K_REGRESSION_HISTORY_LIMIT)
      .get();

    for (const doc of historySnap.docs) {
      const data = doc.data() || {};
      const tsMs = toMillisOrNull(data.createdAt ?? data.timestamp);
      if (!Number.isFinite(tsMs) || tsMs < windowStartMs || tsMs > measuredAtMs + 1000) {
        continue;
      }

      const pmValue = toFiniteNumberOrNull(data.pm25);
      if (Number.isFinite(pmValue) && pmValue >= 0) {
        pmSamples.push({ t: tsMs, v: pmValue });
      }

      const co2Value = toFiniteNumberOrNull(data.co2);
      if (Number.isFinite(co2Value) && co2Value >= 0) {
        const co2Excess = Math.max(co2Value - IAQI_K_CO2_BASELINE, 10);
        co2Samples.push({ t: tsMs, v: co2Excess });
      }
    }
  } catch (error) {
    logger.warn("iaqi_k_history_lookup_failed", {
      sensorId: sensorRef?.id || null,
      error: error?.message || error,
    });
  }

  const pmNow = toFiniteNumberOrNull(pm25);
  if (Number.isFinite(pmNow) && pmNow >= 0) {
    pmSamples.push({ t: measuredAtMs, v: pmNow });
  }

  const co2Now = toFiniteNumberOrNull(co2);
  if (Number.isFinite(co2Now) && co2Now >= 0) {
    co2Samples.push({ t: measuredAtMs, v: Math.max(co2Now - IAQI_K_CO2_BASELINE, 10) });
  }

  const pmRegression = runLogLinearRegression(
    pmSamples,
    (sample) => Math.log(Math.max(sample.v, 1e-6)),
    {
      minSamples: IAQI_K_REGRESSION_MIN_SAMPLES,
      checkNoise: true,
      noiseThreshold: IAQI_K_PM_NOISE_THRESHOLD,
    }
  );

  const co2Regression = runLogLinearRegression(
    co2Samples,
    (sample) => Math.log(Math.max(sample.v, 1e-6)),
    {
      minSamples: IAQI_K_REGRESSION_MIN_SAMPLES,
      checkNoise: false,
    }
  );

  let resolvedK = 0;
  let source = "computed_co2_insufficient_samples";

  // IAQI ventilation term uses CO2-based k by policy.
  if (co2Regression.valid && Number.isFinite(co2Regression.k)) {
    resolvedK = Math.max(co2Regression.k, 0);
    source = "computed_co2_regression";
  }

  return {
    k: roundTo(resolvedK, 3),
    source,
    kPm25:
      pmRegression.valid && Number.isFinite(pmRegression.k)
        ? roundTo(Math.max(pmRegression.k, 0), 3)
        : null,
    kCo2:
      co2Regression.valid && Number.isFinite(co2Regression.k)
        ? roundTo(Math.max(co2Regression.k, 0), 3)
        : null,
    r2Pm25: pmRegression.r2,
    r2Co2: co2Regression.r2,
    pmSampleCount: pmRegression.sampleCount,
    co2SampleCount: co2Regression.sampleCount,
  };
}

function calculateIaqi({
  co2,
  pm25,
  k,
  voc,
  temp,
  humi,
}) {
  const safeCo2 = Number.isFinite(Number(co2)) ? Number(co2) : 600;
  const safePm25 = Number.isFinite(Number(pm25)) ? Number(pm25) : 15;
  const safeVoc = Number.isFinite(Number(voc)) ? Number(voc) : 100;

  const rCo2 = Math.max(0, (safeCo2 - 600) / 400);
  const rPm25 = Math.max(0, (safePm25 - 15) / 35);
  const rVoc = Math.max(0, (safeVoc - 100) / 100);

  const mScoreRaw = Math.max(rCo2, Math.max(rPm25, rVoc));

  let primaryGrade = "좋음";
  let subLevel = null;
  let eScoreRaw = null;
  let iScoreRaw = null;

  if (mScoreRaw > 0 && mScoreRaw < 1) {
    primaryGrade = "보통";
    iScoreRaw = mScoreRaw;
  } else if (mScoreRaw >= 1) {
    primaryGrade = "나쁨";
    eScoreRaw =
      Math.max(0, rCo2 - 1) +
      Math.max(0, rPm25 - 1) +
      Math.max(0, rVoc - 1);

    if (eScoreRaw < 1) {
      subLevel = "조금 나쁨";
    } else if (eScoreRaw < 2) {
      subLevel = "나쁨";
    } else if (eScoreRaw < 3) {
      subLevel = "상당히 나쁨";
    } else {
      subLevel = "매우 나쁨";
    }
  }

  let baseDisplayIaqiRaw = 0;
  if (mScoreRaw > 0 && mScoreRaw < 1) {
    baseDisplayIaqiRaw = mScoreRaw;
  } else if (mScoreRaw >= 1) {
    baseDisplayIaqiRaw = 1 + (eScoreRaw ?? Math.max(0, mScoreRaw - 1));
  }

  const thermal = calculateThermalComfortPenalty(temp, humi);
  const displayIaqiRaw = Math.min(6, baseDisplayIaqiRaw + thermal.penalty);
  const displayExcess = Math.max(0, displayIaqiRaw - 1);
  if (displayIaqiRaw >= 1 && primaryGrade !== "나쁨") {
    primaryGrade = "나쁨";
    if (displayExcess < 1) {
      subLevel = "조금 나쁨";
    } else if (displayExcess < 2) {
      subLevel = "나쁨";
    } else if (displayExcess < 3) {
      subLevel = "상당히 나쁨";
    } else {
      subLevel = "매우 나쁨";
    }
  }

  return {
    primary_grade: primaryGrade,
    sub_level: subLevel,
    display_iaqi: roundTo(displayIaqiRaw, 3),
    base_display_iaqi: roundTo(baseDisplayIaqiRaw, 3),
    thermal_penalty: thermal.penalty,
    thermal_deviation: thermal.deviation,
    thermal_temp_deviation: thermal.tempDeviation,
    thermal_humidity_deviation: thermal.humidityDeviation,
    m_score: roundTo(mScoreRaw, 3),
    e_score: eScoreRaw == null ? null : roundTo(eScoreRaw, 3),
    i_score: iScoreRaw == null ? null : roundTo(iScoreRaw, 3),
  };
}

function calculateThermalComfortPenalty(temp, humi) {
  const safeTemp = Number(temp);
  const safeHumi = Number(humi);
  if (!Number.isFinite(safeTemp) || !Number.isFinite(safeHumi)) {
    return {
      penalty: 0,
      deviation: 0,
      tempDeviation: 0,
      humidityDeviation: 0,
    };
  }

  const tempExcess = Math.max(0, 20 - safeTemp, safeTemp - 26);
  const tempDeviation = Math.min(1, Math.pow(tempExcess / 4, 2));
  const dryDeviation = Math.pow(Math.max(0, 30 - safeHumi) / 10, 2);
  const humidDeviation = Math.pow(Math.max(0, safeHumi - 60) / 20, 2);
  const humidityDeviation = Math.min(1, Math.max(dryDeviation, humidDeviation));
  const deviation = Math.min(1, Math.max(0, 0.7 * tempDeviation + 0.3 * humidityDeviation));

  return {
    penalty: roundTo(0.5 * deviation, 3),
    deviation: roundTo(deviation, 3),
    tempDeviation: roundTo(tempDeviation, 3),
    humidityDeviation: roundTo(humidityDeviation, 3),
  };
}

function buildIaqiBundle({
  co2,
  pm25,
  k,
  voc,
  temp,
  humi,
}) {
  const pm25Number = Number(pm25);
  if (!Number.isFinite(pm25Number) || pm25Number < 0) {
    return null;
  }
  const co2Number = Number(co2);
  if (!Number.isFinite(co2Number) || co2Number < 0) {
    return null;
  }

  const iaqi = calculateIaqi({
    co2: co2Number,
    pm25: pm25Number,
    k,
    voc,
    temp,
    humi,
  });

  const displayIaqi = Number(iaqi.display_iaqi);
  const iaqiScore = Number.isFinite(displayIaqi) ? roundTo(displayIaqi, 3) : null;

  return {
    iaqi,
    iaqiScore,
    pm25: pm25Number,
  };
}

function buildIaqiBundleFromSnapshot(snapshotPayload) {
  if (!snapshotPayload || typeof snapshotPayload !== "object") {
    return null;
  }

  const raw = snapshotPayload.raw && typeof snapshotPayload.raw === "object"
    ? snapshotPayload.raw
    : {};

  const pm25 = toFiniteNumberOrNull(raw.pm25 ?? snapshotPayload.pm25);
  const co2 = toFiniteNumberOrNull(raw.co2 ?? snapshotPayload.co2);
  const voc = toFiniteNumberOrNull(raw.tvoc ?? raw.voc ?? snapshotPayload.tvoc ?? snapshotPayload.voc);
  const temp = toFiniteNumberOrNull(
    raw.temp ?? raw.temperature ?? snapshotPayload.temp ?? snapshotPayload.temperature
  );
  const humi = toFiniteNumberOrNull(raw.humidity ?? snapshotPayload.humidity);
  const k = toFiniteNumberOrNull(
    raw.k
      ?? raw.kEffective
      ?? snapshotPayload.k
      ?? snapshotPayload.kEffective
      ?? snapshotPayload?.purification?.cadr?.kEffective
      ?? snapshotPayload?.purification?.cadr?.k
  );

  return buildIaqiBundle({
    co2,
    pm25,
    k,
    voc,
    temp,
    humi,
  });
}

function toMillisOrNull(value) {
  if (!value) return null;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value?.toDate === "function") {
    const dateValue = value.toDate();
    return dateValue instanceof Date ? dateValue.getTime() : null;
  }

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.getTime();
}

function toIsoStringOrNull(value) {
  const millis = toMillisOrNull(value);
  if (!Number.isFinite(millis)) return null;
  return new Date(millis).toISOString();
}

function toFiniteNumberOrNull(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === "string" && value.trim() === "") return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return null;
  return parsed;
}

function resolveAutoProfile(profileData) {
  const thresholds = profileData?.thresholds && typeof profileData.thresholds === "object"
    ? profileData.thresholds
    : {};
  const hysteresis = profileData?.hysteresis && typeof profileData.hysteresis === "object"
    ? profileData.hysteresis
    : {};
  const constraints = profileData?.constraints && typeof profileData.constraints === "object"
    ? profileData.constraints
    : {};
  const metric = normalizeAutoMetric(profileData?.metric || thresholds.metric);

  const iaqiOnRaw = normalizeLegacyScaledIaqi(toFiniteNumber(thresholds.iaqiOn, NaN));
  const aqiOn = Number.isFinite(iaqiOnRaw)
    ? iaqiOnRaw
    : normalizeLegacyScaledIaqi(toFiniteNumber(thresholds.aqiOn, DEFAULT_AUTO_AQI_ON));

  const iaqiOffRaw = normalizeLegacyScaledIaqi(toFiniteNumber(thresholds.iaqiOff, NaN));
  const explicitAqiOff = Number.isFinite(iaqiOffRaw)
    ? iaqiOffRaw
    : normalizeLegacyScaledIaqi(toFiniteNumber(thresholds.aqiOff, NaN));

  const iaqiHysteresisRaw = normalizeLegacyScaledIaqi(toFiniteNumber(hysteresis.iaqi, NaN));
  const aqiHysteresis = Number.isFinite(iaqiHysteresisRaw)
    ? iaqiHysteresisRaw
    : normalizeLegacyScaledIaqi(toFiniteNumber(hysteresis.aqi, DEFAULT_AUTO_AQI_HYSTERESIS));

  let aqiOff = Number.isFinite(explicitAqiOff)
    ? explicitAqiOff
    : aqiOn - Math.abs(aqiHysteresis);

  if (!Number.isFinite(aqiOff)) {
    aqiOff = DEFAULT_AUTO_AQI_OFF;
  }
  if (aqiOff >= aqiOn) {
    aqiOff = aqiOn - 0.01;
  }

  const minCommandIntervalSeconds = toPositiveInt(
    constraints.minCommandIntervalSeconds ?? constraints.minIntervalSeconds,
    DEFAULT_AUTO_COMMAND_INTERVAL_SECONDS
  );

  if (metric !== "iaqi") {
    const metricOn = toFiniteNumber(
      thresholds.onThreshold ?? thresholds[`${metric}On`],
      NaN
    );
    const metricOffExplicit = toFiniteNumber(
      thresholds.offThreshold ?? thresholds[`${metric}Off`],
      NaN
    );
    const metricHysteresis = toFiniteNumber(
      hysteresis.value ?? hysteresis[metric],
      NaN
    );
    const onThreshold = Number.isFinite(metricOn) ? metricOn : aqiOn;
    let offThreshold = Number.isFinite(metricOffExplicit)
      ? metricOffExplicit
      : onThreshold - Math.abs(Number.isFinite(metricHysteresis)
        ? metricHysteresis
        : onThreshold * 0.2);

    if (!Number.isFinite(offThreshold)) {
      offThreshold = onThreshold;
    }
    if (offThreshold >= onThreshold) {
      offThreshold = onThreshold - Math.max(Math.abs(onThreshold) * 0.01, 0.01);
    }

    return {
      metric,
      controlBasis: autoMetricLabel(metric),
      onThreshold,
      offThreshold,
      minCommandIntervalSeconds,
    };
  }

  return {
    metric: "iaqi",
    controlBasis: "IAQI",
    onThreshold: aqiOn,
    offThreshold: aqiOff,
    aqiOn,
    aqiOff,
    minCommandIntervalSeconds,
  };
}

function resolveAutoProfiles(profileData) {
  const rawRules = Array.isArray(profileData?.rules) ? profileData.rules : [];
  const rules = rawRules
    .filter((rule) => rule && typeof rule === "object")
    .map((rule) => resolveAutoProfile({
      metric: rule.metric || rule.thresholds?.metric,
      thresholds: rule.thresholds || {},
      hysteresis: rule.hysteresis || {},
      constraints: profileData?.constraints || {},
    }))
    .filter((rule) => rule && Number.isFinite(rule.onThreshold) && Number.isFinite(rule.offThreshold));

  if (rules.length) return rules;
  return [resolveAutoProfile(profileData)];
}

function resolveAutoMetricValue(snapshotPayload, iaqiBundle, metric) {
  const raw = snapshotPayload?.raw && typeof snapshotPayload.raw === "object"
    ? snapshotPayload.raw
    : {};
  switch (normalizeAutoMetric(metric)) {
    case "co2":
      return toFiniteNumberOrNull(raw.co2 ?? snapshotPayload?.co2);
    case "pm25":
      return toFiniteNumberOrNull(
        raw.pm25
          ?? raw.pm2_5
          ?? raw.pm02
          ?? snapshotPayload?.pm25
          ?? snapshotPayload?.pm2_5
          ?? snapshotPayload?.pm02
      );
    case "tvoc":
      return toFiniteNumberOrNull(raw.tvoc ?? raw.voc ?? snapshotPayload?.tvoc ?? snapshotPayload?.voc);
    case "nox":
      return toFiniteNumberOrNull(raw.nox ?? snapshotPayload?.nox);
    case "iaqi":
    default:
      return toFiniteNumberOrNull(snapshotPayload?.iaqiScore ?? raw.iaqiScore ?? iaqiBundle?.iaqiScore);
  }
}

function isWithinAutoCommandInterval(plugData, minCommandIntervalSeconds) {
  const minInterval = toPositiveInt(minCommandIntervalSeconds, DEFAULT_AUTO_COMMAND_INTERVAL_SECONDS);
  if (!minInterval) return false;

  const lastAutoCommandAtMs = toMillisOrNull(plugData?.lastAutoCommandAt);
  if (!Number.isFinite(lastAutoCommandAtMs)) return false;

  return Date.now() - lastAutoCommandAtMs < minInterval * 1000;
}

async function listPlugsForSensor(sensorId) {
  const candidates = buildSensorIdCandidates(sensorId).slice(0, 30);
  if (!candidates.length) return [];

  const snapshot = candidates.length === 1
    ? await db.collection("plugs").where("sensorId", "==", candidates[0]).get()
    : await db.collection("plugs").where("sensorId", "in", candidates).get();

  return snapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));
}

async function loadPlugProfile(profileId) {
  const normalized = typeof profileId === "string" ? profileId.trim() : "";
  if (!normalized) return null;

  const snap = await db.collection("plug_profiles").doc(normalized).get();
  if (!snap.exists) return null;
  return snap.data() || null;
}

async function logPlugControlDecision(entry) {
  if (DISABLE_PLUG_DECISION_LOG) {
    return;
  }

  const nowTs = admin.firestore.FieldValue.serverTimestamp();
  const nowDate = new Date();
  try {
    await db.collection("plug_control_decisions").add(
      withExpireAt(
        {
          ...entry,
          createdAt: nowTs,
          updatedAt: nowTs,
        },
        PLUG_LOG_RETENTION_DAYS,
        nowDate
      )
    );
  } catch (error) {
    logger.warn("plug_control_decision_log_failed", {
      plugId: entry?.plugId || null,
      error: error?.message || error,
    });
  }
}

async function enqueueAutoAqiCommand({
  plug,
  command,
  metric,
  metricValue,
  iaqi,
  iaqiScore,
  pm25,
  profile,
  snapshotPayload,
}) {
  const plugId = normalizePlugId(plug?.plugId || plug?.id);
  if (!plugId) {
    return {
      queued: false,
      status: "invalid_plug_id",
    };
  }

  const requestRef = db.collection("plug_command_requests").doc();
  const requestId = requestRef.id;
  const queueRef = db.collection("plug_command_queue").doc(requestId);
  const plugRef = db.collection("plugs").doc(plugId);
  const sensorSnapshot = {
    serial: snapshotPayload?.serial || null,
    timestamp: snapshotPayload?.timestamp || new Date().toISOString(),
    pm25,
    metric: profile.metric,
    metricValue,
    iaqiScore,
    iaqi,
    controlBasis: profile.controlBasis,
    thresholds: {
      metric: profile.metric,
      onThreshold: profile.onThreshold,
      offThreshold: profile.offThreshold,
      aqiOn: profile.aqiOn ?? null,
      aqiOff: profile.aqiOff ?? null,
    },
  };

  const result = await db.runTransaction(async (tx) => {
    const plugSnap = await tx.get(plugRef);
    const plugData = plugSnap.exists ? (plugSnap.data() || {}) : {};
    const currentActualState = normalizePowerState(plugData.actualState);
    const desiredState = normalizePowerState(command);
    const nowMs = Date.now();
    const existingManualOverrideMs = plugData.manualOverrideUntil?.toDate
      ? plugData.manualOverrideUntil.toDate().getTime()
      : null;
    const manualOverrideActive = Number.isFinite(existingManualOverrideMs)
      && existingManualOverrideMs > nowMs;
    const nowTs = admin.firestore.FieldValue.serverTimestamp();
    const nowDate = new Date();

    if (currentActualState === desiredState) {
      return {
        queued: false,
        status: "no_state_change_needed",
      };
    }

    if (manualOverrideActive) {
      tx.set(
        requestRef,
        withExpireAt(
          {
            requestId,
            plugId,
            command,
            desiredState,
            mode: "auto",
            actor: "auto_control_engine",
            reason: `auto_${normalizeAutoMetric(metric)}_threshold`,
            sensorSnapshot,
            status: "suppressed_manual_override",
            errorMessage: "manual_override_active",
            manualOverrideUntil: plugData.manualOverrideUntil || null,
            queuedAt: nowTs,
            createdAt: nowTs,
            updatedAt: nowTs,
          },
          PLUG_LOG_RETENTION_DAYS,
          nowDate
        )
      );

      tx.set(
        queueRef,
        withExpireAt(
          {
            requestId,
            plugId,
            command,
            desiredState,
            mode: "auto",
            status: "suppressed_manual_override",
            errorMessage: "manual_override_active",
            tasmotaTopic: plugData.tasmotaTopic || null,
            queuedAt: nowTs,
            processedAt: nowTs,
            createdAt: nowTs,
            updatedAt: nowTs,
          },
          PLUG_LOG_RETENTION_DAYS,
          nowDate
        )
      );

      tx.set(plugRef, {
        plugId,
        desiredState,
        lastCommandRequestId: requestId,
        updatedAt: nowTs,
        createdAt: nowTs,
      }, { merge: true });

      return {
        queued: false,
        status: "suppressed_manual_override",
        requestId,
      };
    }

    tx.set(
      requestRef,
      withExpireAt(
        {
          requestId,
          plugId,
          command,
          desiredState,
          mode: "auto",
          actor: "auto_control_engine",
          reason: `auto_${normalizeAutoMetric(metric)}_threshold`,
          sensorSnapshot,
          status: "queued",
          queuedAt: nowTs,
          createdAt: nowTs,
          updatedAt: nowTs,
        },
        PLUG_LOG_RETENTION_DAYS,
        nowDate
      )
    );

    tx.set(
      queueRef,
      withExpireAt(
        {
          requestId,
          plugId,
          command,
          desiredState,
          mode: "auto",
          status: shouldUseFunctionMqttDispatch(null, plugData.tasmotaTopic)
            ? "function_dispatching"
            : "pending",
          dispatcher: shouldUseFunctionMqttDispatch(null, plugData.tasmotaTopic)
            ? "firebase-function-mqtt"
            : "worker",
          tasmotaTopic: plugData.tasmotaTopic || null,
          queuedAt: nowTs,
          createdAt: nowTs,
          updatedAt: nowTs,
        },
        PLUG_LOG_RETENTION_DAYS,
        nowDate
      )
    );

    tx.set(plugRef, {
      plugId,
      mode: "auto",
      desiredState,
      lastCommandRequestId: requestId,
      lastAutoCommandAt: nowTs,
      lastAutoMetric: profile.metric,
      lastAutoMetricValue: metricValue,
      lastAutoIAQI: iaqiScore,
      lastAutoIAQIPrimary: iaqi?.primary_grade || null,
      lastAutoPM25: pm25,
      updatedAt: nowTs,
      createdAt: nowTs,
    }, { merge: true });

    return {
      queued: true,
      status: "queued",
      requestId,
      plugId,
      command,
      desiredState,
      tasmotaTopic: plugData.tasmotaTopic || null,
      functionMqttDispatch: shouldUseFunctionMqttDispatch(null, plugData.tasmotaTopic),
    };
  });

  if (result.queued && result.functionMqttDispatch) {
    const dispatchResult = await dispatchQueuedCommandWithFunctionMqtt({
      requestId: result.requestId,
      plugId: result.plugId,
      tasmotaTopic: result.tasmotaTopic,
      command: result.command,
      desiredState: result.desiredState,
    });
    return {
      ...result,
      status: dispatchResult.status,
      dispatched: true,
      acknowledged: dispatchResult.ok === true,
    };
  }

  return result;
}

async function dispatchAutoControlForSnapshot(snapshotPayload) {
  const sensorId = typeof snapshotPayload?.serial === "string"
    ? snapshotPayload.serial.trim()
    : "";
  if (!sensorId) return;

  const iaqiBundle = buildIaqiBundleFromSnapshot(snapshotPayload);
  const pm25 = toFiniteNumberOrNull(snapshotPayload?.pm25 ?? snapshotPayload?.raw?.pm25 ?? iaqiBundle?.pm25);
  const iaqi = iaqiBundle?.iaqi || snapshotPayload?.iaqi || snapshotPayload?.raw?.iaqi || null;
  const iaqiScore = toFiniteNumberOrNull(snapshotPayload?.iaqiScore ?? snapshotPayload?.raw?.iaqiScore ?? iaqiBundle?.iaqiScore);

  const plugs = await listPlugsForSensor(sensorId);
  if (!plugs.length) return;

  const profileCache = new Map();
  for (const plug of plugs) {
    const plugId = normalizePlugId(plug?.plugId || plug?.id);
    if (!plugId) continue;
    if (plug.controlEnabled === false) continue;

    const mode = String(plug.mode || "auto").trim().toLowerCase();
    if (mode !== "auto") continue;

    const profileId = typeof plug.profileId === "string" ? plug.profileId.trim() : "";
    let profileData = null;
    if (profileId) {
      if (profileCache.has(profileId)) {
        profileData = profileCache.get(profileId);
      } else {
        profileData = await loadPlugProfile(profileId);
        profileCache.set(profileId, profileData);
      }
    }

    const profiles = resolveAutoProfiles(profileData);
    const evaluatedProfiles = [];
    for (const profile of profiles) {
      const metricValue = resolveAutoMetricValue(snapshotPayload, iaqiBundle, profile.metric);
      if (Number.isFinite(metricValue)) {
        evaluatedProfiles.push({ profile, metricValue });
      }
    }

    const firstProfile = profiles[0] || resolveAutoProfile(profileData);
    if (!evaluatedProfiles.length) {
      await logPlugControlDecision({
        plugId,
        sensorId,
        profileId: profileId || null,
        controlBasis: firstProfile.controlBasis,
        metric: firstProfile.metric,
        metricValue: null,
        iaqiScore,
        iaqi,
        pm25,
        command: null,
        status: "skipped_missing_metric",
        thresholds: {
          metric: firstProfile.metric,
          onThreshold: firstProfile.onThreshold,
          offThreshold: firstProfile.offThreshold,
          minCommandIntervalSeconds: firstProfile.minCommandIntervalSeconds,
        },
      });
      continue;
    }

    let command = null;
    let selected = evaluatedProfiles
      .filter((item) => item.metricValue >= item.profile.onThreshold)
      .sort((a, b) =>
        (b.metricValue / b.profile.onThreshold) -
        (a.metricValue / a.profile.onThreshold)
      )[0];
    if (selected) {
      command = "ON";
    } else if (
      evaluatedProfiles.length === profiles.length &&
      evaluatedProfiles.every((item) => item.metricValue <= item.profile.offThreshold)
    ) {
      command = "OFF";
      selected = evaluatedProfiles[0];
    }

    if (!command) {
      continue;
    }
    const profile = selected.profile;
    const metricValue = selected.metricValue;

    if (isWithinAutoCommandInterval(plug, profile.minCommandIntervalSeconds)) {
      await logPlugControlDecision({
        plugId,
        sensorId,
        profileId: profileId || null,
        controlBasis: profile.controlBasis,
        metric: profile.metric,
        metricValue,
        iaqiScore,
        iaqi,
        pm25,
        command,
        status: "skipped_min_interval",
        thresholds: {
          metric: profile.metric,
          onThreshold: profile.onThreshold,
          offThreshold: profile.offThreshold,
          aqiOn: profile.aqiOn ?? null,
          aqiOff: profile.aqiOff ?? null,
          minCommandIntervalSeconds: profile.minCommandIntervalSeconds,
        },
      });
      continue;
    }

    const enqueueResult = await enqueueAutoAqiCommand({
      plug,
      command,
      metric: profile.metric,
      metricValue,
      iaqi,
      iaqiScore,
      pm25,
      profile,
      snapshotPayload,
    });

    await logPlugControlDecision({
      plugId,
      sensorId,
      profileId: profileId || null,
      controlBasis: profile.controlBasis,
      metric: profile.metric,
      metricValue,
      iaqiScore,
      iaqi,
      pm25,
      command,
      requestId: enqueueResult.requestId || null,
      status: enqueueResult.status,
      queued: Boolean(enqueueResult.queued),
      thresholds: {
        metric: profile.metric,
        onThreshold: profile.onThreshold,
        offThreshold: profile.offThreshold,
        aqiOn: profile.aqiOn ?? null,
        aqiOff: profile.aqiOff ?? null,
        minCommandIntervalSeconds: profile.minCommandIntervalSeconds,
      },
    });
  }
}

function buildSnapshotPayloadFromSensorDoc(sensorId, sensorData) {
  const latest = sensorData?.latest && typeof sensorData.latest === "object"
    ? sensorData.latest
    : sensorData || {};
  return {
    serial: sensorId,
    raw: latest,
    pm25: latest.pm25 ?? latest.pm02 ?? sensorData?.pm25 ?? sensorData?.pm02,
    iaqi: latest.iaqi ?? sensorData?.iaqi,
    iaqiScore: latest.iaqiScore ?? sensorData?.iaqiScore,
    co2: latest.co2 ?? latest.rco2 ?? sensorData?.co2 ?? sensorData?.rco2,
    tvoc: latest.tvoc ?? latest.voc ?? sensorData?.tvoc ?? sensorData?.voc,
    nox: latest.nox ?? sensorData?.nox,
    temp: latest.temp ?? latest.temperature ?? sensorData?.temp ?? sensorData?.temperature,
    humidity: latest.humidity ?? latest.rhum ?? sensorData?.humidity ?? sensorData?.rhum,
    k: latest.k ?? sensorData?.k,
    kEffective: latest.kEffective ?? sensorData?.kEffective,
    timestamp: toIsoStringOrNull(
      latest.timestamp
        || latest.createdAt
        || sensorData?.lastSeen
        || sensorData?.timestamp
        || sensorData?.updatedAt
    ) || new Date().toISOString(),
  };
}

async function loadLatestSensorSnapshotPayload(sensorId) {
  const candidates = buildSensorIdCandidates(sensorId).slice(0, 12);
  for (const candidate of candidates) {
    const snap = await db.collection("sensors").doc(candidate).get();
    if (!snap.exists) continue;
    return buildSnapshotPayloadFromSensorDoc(candidate, snap.data() || {});
  }
  return null;
}

async function dispatchAutoControlForRegisteredPlugs() {
  const snap = await db.collection("plugs")
    .where("mode", "==", "auto")
    .limit(100)
    .get();
  if (snap.empty) return { scanned: 0, sensors: 0 };

  const sensorIds = [...new Set(snap.docs
    .map((doc) => {
      const data = doc.data() || {};
      if (data.controlEnabled === false) return "";
      return typeof data.sensorId === "string" ? data.sensorId.trim() : "";
    })
    .filter((value) => value.length > 0))];

  let dispatched = 0;
  for (const sensorId of sensorIds) {
    const payload = await loadLatestSensorSnapshotPayload(sensorId);
    if (!payload) continue;
    await dispatchAutoControlForSnapshot(payload);
    dispatched += 1;
  }

  return { scanned: snap.size, sensors: dispatched };
}

exports.registerPlug = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (!ensurePost(req, res)) return;
    if (!validateOptionalApiKey(req, res)) return;

    const body = req.body || {};
    const plugId = normalizePlugId(body.plugId);
    if (!plugId) {
      return badRequest(res, "plugId_is_required");
    }

    const mode = String(body.mode || "auto").trim().toLowerCase() === "manual"
      ? "manual"
      : "auto";

    const payload = {
      plugId,
      displayName: typeof body.displayName === "string" ? body.displayName.trim() : null,
      stationId: typeof body.stationId === "string" ? body.stationId.trim() : null,
      sensorId: typeof body.sensorId === "string" ? body.sensorId.trim() : null,
      tasmotaTopic: typeof body.tasmotaTopic === "string" ? body.tasmotaTopic.trim() : null,
      profileId: typeof body.profileId === "string" ? body.profileId.trim() : null,
      mode,
      transportPrimary: typeof body.transportPrimary === "string"
        ? body.transportPrimary.trim().toUpperCase()
        : "MQTT",
      transportFallback: typeof body.transportFallback === "string"
        ? body.transportFallback.trim().toUpperCase()
        : "HTTP",
      desiredState: normalizePowerState(body.desiredState),
      actualState: normalizePowerState(body.actualState),
      online: toBooleanOrNull(body.online),
      metadata: body.metadata && typeof body.metadata === "object" ? body.metadata : {},
      controlEnabled: body.controlEnabled === false ? false : true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (mode === "auto") {
      payload.manualOverrideUntil = null;
    }

    try {
      await db.collection("plugs").doc(plugId).set(payload, { merge: true });
      return res.status(200).json({ ok: true, plugId });
    } catch (error) {
      logger.error("register_plug_failed", { plugId, error: error?.message || error });
      return res.status(500).json({ ok: false, error: "internal_error" });
    }
  }
);

exports.upsertPlugProfile = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (!ensurePost(req, res)) return;
    if (!validateOptionalApiKey(req, res)) return;

    const body = req.body || {};
    const providedId = typeof body.profileId === "string" ? body.profileId.trim() : "";
    const profileId = providedId || db.collection("plug_profiles").doc().id;

    const payload = {
      profileId,
      name: typeof body.name === "string" ? body.name.trim() : "default",
      metric: normalizeAutoMetric(body.metric || body.thresholds?.metric),
      weights: body.weights && typeof body.weights === "object" ? body.weights : {},
      thresholds: body.thresholds && typeof body.thresholds === "object" ? body.thresholds : {},
      hysteresis: body.hysteresis && typeof body.hysteresis === "object" ? body.hysteresis : {},
      rules: Array.isArray(body.rules) ? body.rules : [],
      constraints: body.constraints && typeof body.constraints === "object" ? body.constraints : {},
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    try {
      await db.collection("plug_profiles").doc(profileId).set(payload, { merge: true });
      return res.status(200).json({ ok: true, profileId });
    } catch (error) {
      logger.error("upsert_plug_profile_failed", { profileId, error: error?.message || error });
      return res.status(500).json({ ok: false, error: "internal_error" });
    }
  }
);

exports.commandPlug = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (!ensurePost(req, res)) return;
    if (!validateOptionalApiKey(req, res)) return;

    const body = req.body || {};
    const plugId = normalizePlugId(body.plugId);
    const command = normalizePowerCommand(body.command);
    if (!plugId) {
      return badRequest(res, "plugId_is_required");
    }
    if (!command) {
      return badRequest(res, "command_must_be_on_off_toggle");
    }

    const requestedByToken = typeof body.requestedByToken === "string"
      ? body.requestedByToken.trim()
      : null;
    const actor = typeof body.actor === "string" ? body.actor.trim() : "system";
    const requestedMode = String(body.mode || "manual").trim().toLowerCase();
    const mode = requestedMode === "auto" ? "auto" : "manual";
    const reason = typeof body.reason === "string" ? body.reason.trim() : null;
    const transportHint = typeof body.transportHint === "string"
      ? body.transportHint.trim().toUpperCase()
      : null;
    const sensorSnapshot = body.sensorSnapshot && typeof body.sensorSnapshot === "object"
      ? body.sensorSnapshot
      : null;
    const manualOverrideSeconds = toPositiveInt(
      body.manualOverrideSeconds,
      MANUAL_OVERRIDE_DEFAULT_SECONDS
    );

    const requestRef = db.collection("plug_command_requests").doc();
    const requestId = requestRef.id;
    const queueRef = db.collection("plug_command_queue").doc(requestId);
    const plugRef = db.collection("plugs").doc(plugId);
    const manualOverrideUntil = mode === "manual"
      ? admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + manualOverrideSeconds * 1000)
      )
      : null;

    try {
      const commandResult = await db.runTransaction(async (tx) => {
        const plugSnap = await tx.get(plugRef);
        const plugData = plugSnap.exists ? (plugSnap.data() || {}) : {};
        const currentActualState = normalizePowerState(plugData.actualState);
        const nowMs = Date.now();
        const existingManualOverrideMs = plugData.manualOverrideUntil?.toDate
          ? plugData.manualOverrideUntil.toDate().getTime()
          : null;
        const manualOverrideActive = Number.isFinite(existingManualOverrideMs)
          && existingManualOverrideMs > nowMs;
        const existingManualOverrideIso = manualOverrideActive
          ? new Date(existingManualOverrideMs).toISOString()
          : null;
        const desiredState = command === "TOGGLE"
          ? (currentActualState === "ON"
            ? "OFF"
            : currentActualState === "OFF"
              ? "ON"
              : "UNKNOWN")
          : command;

        const nowTs = admin.firestore.FieldValue.serverTimestamp();
        const nowDate = new Date();

        if (mode === "auto" && manualOverrideActive) {
          tx.set(
            requestRef,
            withExpireAt(
              {
                requestId,
                plugId,
                command,
                desiredState,
                mode,
                actor,
                requestedByToken,
                reason,
                transportHint,
                sensorSnapshot,
                status: "suppressed_manual_override",
                errorMessage: "manual_override_active",
                manualOverrideUntil: plugData.manualOverrideUntil || null,
                queuedAt: nowTs,
                createdAt: nowTs,
                updatedAt: nowTs,
              },
              PLUG_LOG_RETENTION_DAYS,
              nowDate
            )
          );

          tx.set(
            queueRef,
            withExpireAt(
              {
                requestId,
                plugId,
                command,
                desiredState,
                mode,
                status: "suppressed_manual_override",
                errorMessage: "manual_override_active",
                transportHint,
                tasmotaTopic: plugData.tasmotaTopic || null,
                queuedAt: nowTs,
                processedAt: nowTs,
                createdAt: nowTs,
                updatedAt: nowTs,
              },
              PLUG_LOG_RETENTION_DAYS,
              nowDate
            )
          );

          tx.set(plugRef, {
            plugId,
            desiredState,
            lastCommandRequestId: requestId,
            updatedAt: nowTs,
            createdAt: nowTs,
          }, { merge: true });

          return {
            queued: false,
            status: "suppressed_manual_override",
            manualOverrideUntil: existingManualOverrideIso,
          };
        }

        tx.set(
          requestRef,
          withExpireAt(
            {
              requestId,
              plugId,
              command,
              desiredState,
              mode,
              actor,
              requestedByToken,
              reason,
              transportHint,
              sensorSnapshot,
              status: "queued",
              queuedAt: nowTs,
              createdAt: nowTs,
              updatedAt: nowTs,
            },
            PLUG_LOG_RETENTION_DAYS,
            nowDate
          )
        );

        tx.set(
          queueRef,
          withExpireAt(
            {
              requestId,
              plugId,
              command,
              desiredState,
              mode,
              status: shouldUseFunctionMqttDispatch(transportHint, plugData.tasmotaTopic)
                ? "function_dispatching"
                : "pending",
              dispatcher: shouldUseFunctionMqttDispatch(transportHint, plugData.tasmotaTopic)
                ? "firebase-function-mqtt"
                : "worker",
              transportHint,
              tasmotaTopic: plugData.tasmotaTopic || null,
              queuedAt: nowTs,
              createdAt: nowTs,
              updatedAt: nowTs,
            },
            PLUG_LOG_RETENTION_DAYS,
            nowDate
          )
        );

        const currentMode = String(plugData.mode || "manual").trim().toLowerCase() === "auto"
          ? "auto"
          : "manual";

        const plugUpdate = {
          plugId,
          mode: mode === "auto" ? "auto" : currentMode,
          desiredState,
          lastCommandRequestId: requestId,
          updatedAt: nowTs,
          createdAt: nowTs,
        };

        if (mode === "manual") {
          plugUpdate.manualOverrideUntil = manualOverrideUntil;
        } else if (Number.isFinite(existingManualOverrideMs) && existingManualOverrideMs <= nowMs) {
          plugUpdate.manualOverrideUntil = null;
        }

        tx.set(plugRef, plugUpdate, { merge: true });

        return {
          queued: true,
          status: "queued",
          command,
          desiredState,
          tasmotaTopic: plugData.tasmotaTopic || null,
          functionMqttDispatch: shouldUseFunctionMqttDispatch(
            transportHint,
            plugData.tasmotaTopic
          ),
          manualOverrideUntil: manualOverrideUntil
            ? manualOverrideUntil.toDate().toISOString()
            : null,
        };
      });

      if (!commandResult.queued) {
        return res.status(200).json({
          ok: true,
          requestId,
          plugId,
          queued: false,
          status: commandResult.status,
          reason: "manual_override_active",
          manualOverrideUntil: commandResult.manualOverrideUntil,
        });
      }

      let dispatchResult = null;
      if (commandResult.functionMqttDispatch) {
        dispatchResult = await dispatchQueuedCommandWithFunctionMqtt({
          requestId,
          plugId,
          tasmotaTopic: commandResult.tasmotaTopic,
          command: commandResult.command,
          desiredState: commandResult.desiredState,
        });
      }

      return res.status(200).json({
        ok: true,
        requestId,
        plugId,
        queued: true,
        status: dispatchResult?.status || commandResult.status,
        dispatched: Boolean(dispatchResult),
        acknowledged: dispatchResult?.ok === true,
        mqtt: dispatchResult
          ? {
            status: dispatchResult.status,
            actualState: dispatchResult.actualState || "UNKNOWN",
            responseTopic: dispatchResult.responseTopic || null,
            errorMessage: dispatchResult.errorMessage || null,
            latencyMs: dispatchResult.latencyMs || null,
            telemetry: dispatchResult.telemetry || null,
          }
          : null,
        manualOverrideUntil: commandResult.manualOverrideUntil,
      });
    } catch (error) {
      logger.error("command_plug_failed", { plugId, command, error: error?.message || error });
      return res.status(500).json({ ok: false, error: "internal_error" });
    }
  }
);

exports.ackPlugCommand = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (!ensurePost(req, res)) return;
    if (!validateOptionalApiKey(req, res)) return;

    const body = req.body || {};
    const requestId = typeof body.requestId === "string" ? body.requestId.trim() : "";
    if (!requestId) {
      return badRequest(res, "requestId_is_required");
    }

    const requestRef = db.collection("plug_command_requests").doc(requestId);
    const queueRef = db.collection("plug_command_queue").doc(requestId);
    const responseRef = db.collection("plug_command_responses").doc();

    const requestedStatus = String(body.status || "").trim().toLowerCase();
    const status = ["acknowledged", "failed", "timeout"].includes(requestedStatus)
      ? requestedStatus
      : "acknowledged";
    const responseTopic = typeof body.responseTopic === "string" ? body.responseTopic.trim() : null;
    const responsePayloadRaw = body.responsePayloadRaw !== undefined
      ? JSON.stringify(body.responsePayloadRaw)
      : null;
    const errorMessage = typeof body.errorMessage === "string" ? body.errorMessage.trim() : null;
    const actualState = normalizePowerState(body.actualState);
    const online = toBooleanOrNull(body.online);
    const latencyMs = toFiniteNumber(body.latencyMs, 0);
    const workerId = typeof body.workerId === "string" ? body.workerId.trim() : null;
    const telemetry = body.telemetry && typeof body.telemetry === "object" ? body.telemetry : null;
    const telemetryUpdate = plugTelemetryUpdateFields(telemetry);

    try {
      await db.runTransaction(async (tx) => {
        const requestSnap = await tx.get(requestRef);
        if (!requestSnap.exists) {
          throw new Error("request_not_found");
        }

        const requestData = requestSnap.data() || {};
        const plugId = normalizePlugId(body.plugId || requestData.plugId);
        const nowTs = admin.firestore.FieldValue.serverTimestamp();
        const nowDate = new Date();

        tx.set(requestRef, {
          status,
          ackAt: nowTs,
          latencyMs,
          workerId,
          errorMessage,
          actualState,
          online,
          updatedAt: nowTs,
        }, { merge: true });

        tx.set(queueRef, {
          status: status === "acknowledged" ? "processed" : status,
          processedAt: nowTs,
          updatedAt: nowTs,
        }, { merge: true });

        tx.set(
          responseRef,
          withExpireAt(
            {
              responseId: responseRef.id,
              requestId,
              plugId,
              status,
              responseTopic,
              responsePayloadRaw,
              errorMessage,
              actualState,
              online,
              latencyMs,
              telemetry,
              workerId,
              createdAt: nowTs,
              updatedAt: nowTs,
            },
            PLUG_LOG_RETENTION_DAYS,
            nowDate
          )
        );

        if (plugId) {
          tx.set(db.collection("plugs").doc(plugId), {
            plugId,
            actualState,
            online,
            ...telemetryUpdate,
            lastAckRequestId: requestId,
            lastSeen: nowTs,
            updatedAt: nowTs,
            createdAt: nowTs,
          }, { merge: true });
        }
      });

      return res.status(200).json({ ok: true, requestId, status });
    } catch (error) {
      const message = error?.message || "internal_error";
      if (message === "request_not_found") {
        return res.status(404).json({ ok: false, error: "request_not_found" });
      }
      logger.error("ack_plug_command_failed", { requestId, error: message });
      return res.status(500).json({ ok: false, error: "internal_error" });
    }
  }
);

exports.updatePlugState = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (!ensurePost(req, res)) return;
    if (!validateOptionalApiKey(req, res)) return;

    const body = req.body || {};
    const plugId = normalizePlugId(body.plugId);
    if (!plugId) {
      return badRequest(res, "plugId_is_required");
    }

    const actualState = normalizePowerState(body.actualState);
    const online = toBooleanOrNull(body.online);
    const source = typeof body.source === "string" ? body.source.trim() : "worker";
    const telemetry = body.telemetry && typeof body.telemetry === "object" ? body.telemetry : null;
    const telemetryUpdate = plugTelemetryUpdateFields(telemetry);

    try {
      const nowTs = admin.firestore.FieldValue.serverTimestamp();
      await db.collection("plugs").doc(plugId).set(
        {
          plugId,
          actualState,
          online,
          telemetry,
          ...telemetryUpdate,
          stateSource: source,
          lastSeen: nowTs,
          updatedAt: nowTs,
          createdAt: nowTs,
        },
        { merge: true }
      );

      if (!DISABLE_PLUG_STATE_HISTORY_WRITES) {
        await db.collection("plug_state_history").add(
          withExpireAt(
            {
              plugId,
              actualState,
              online,
              telemetry,
              source,
              createdAt: nowTs,
            },
            PLUG_LOG_RETENTION_DAYS
          )
        );
      }

      return res.status(200).json({ ok: true, plugId, actualState, online });
    } catch (error) {
      logger.error("update_plug_state_failed", { plugId, error: error?.message || error });
      return res.status(500).json({ ok: false, error: "internal_error" });
    }
  }
);

exports.getPlug = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (!ensurePost(req, res)) return;
    if (!validateOptionalApiKey(req, res)) return;

    const plugId = normalizePlugId(req.body?.plugId);
    if (!plugId) {
      return badRequest(res, "plugId_is_required");
    }

    try {
      const snap = await db.collection("plugs").doc(plugId).get();
      if (!snap.exists) {
        return res.status(404).json({ ok: false, error: "plug_not_found" });
      }

      const data = snap.data() || {};
      const manualOverrideUntil = data.manualOverrideUntil?.toDate
        ? data.manualOverrideUntil.toDate().toISOString()
        : null;
      const nowMs = Date.now();
      const autoPaused = manualOverrideUntil
        ? new Date(manualOverrideUntil).getTime() > nowMs
        : false;

      return res.status(200).json({
        ok: true,
        plug: {
          ...data,
          plugId: snap.id,
          manualOverrideUntil,
          autoPaused,
        },
      });
    } catch (error) {
      logger.error("get_plug_failed", { plugId, error: error?.message || error });
      return res.status(500).json({ ok: false, error: "internal_error" });
    }
  }
);

exports.listPlugs = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (!ensurePost(req, res)) return;
    if (!validateOptionalApiKey(req, res)) return;

    const body = req.body || {};
    const stationId = typeof body.stationId === "string" ? body.stationId.trim() : "";
    const sensorId = typeof body.sensorId === "string" ? body.sensorId.trim() : "";
    const limit = Math.min(100, Math.max(1, toPositiveInt(body.limit, 20)));

    try {
      let query = db.collection("plugs").limit(limit);
      if (stationId) {
        query = db.collection("plugs").where("stationId", "==", stationId).limit(limit);
      } else if (sensorId) {
        query = db.collection("plugs").where("sensorId", "==", sensorId).limit(limit);
      }

      const snap = await query.get();
      const plugs = snap.docs.map((doc) => {
        const data = doc.data() || {};
        const manualOverrideUntil = data.manualOverrideUntil?.toDate
          ? data.manualOverrideUntil.toDate().toISOString()
          : null;
        return {
          ...data,
          plugId: doc.id,
          manualOverrideUntil,
        };
      });

      return res.status(200).json({ ok: true, count: plugs.length, plugs });
    } catch (error) {
      logger.error("list_plugs_failed", { error: error?.message || error });
      return res.status(500).json({ ok: false, error: "internal_error" });
    }
  }
);

exports.getPlugControlTrace = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (!ensurePost(req, res)) return;
    if (!validateOptionalApiKey(req, res)) return;

    const body = req.body || {};
    const plugId = normalizePlugId(body.plugId);
    if (!plugId) {
      return badRequest(res, "plugId_is_required");
    }

    const limit = Math.min(50, Math.max(1, toPositiveInt(body.limit, 12)));
    const decisionFetchLimit = Math.min(300, Math.max(limit * 10, limit));
    const requestFetchLimit = Math.min(300, Math.max(limit * 6, limit));

    try {
      const formatRequest = (requestData) => requestData ? {
        status: typeof requestData.status === "string" ? requestData.status : null,
        mode: typeof requestData.mode === "string" ? requestData.mode : null,
        actor: typeof requestData.actor === "string" ? requestData.actor : null,
        reason: typeof requestData.reason === "string" ? requestData.reason : null,
        desiredState: typeof requestData.desiredState === "string"
          ? requestData.desiredState
          : null,
        actualState: typeof requestData.actualState === "string"
          ? requestData.actualState
          : null,
        errorMessage: typeof requestData.errorMessage === "string"
          ? requestData.errorMessage
          : null,
        manualOverrideUntil: toIsoStringOrNull(requestData.manualOverrideUntil),
        queuedAt: toIsoStringOrNull(requestData.queuedAt),
        ackAt: toIsoStringOrNull(requestData.ackAt),
        updatedAt: toIsoStringOrNull(requestData.updatedAt),
      } : null;

      const formatResponse = (responseData) => responseData ? {
        status: typeof responseData.status === "string" ? responseData.status : null,
        actualState: typeof responseData.actualState === "string"
          ? responseData.actualState
          : null,
        online: toBooleanOrNull(responseData.online),
        latencyMs: toFiniteNumberOrNull(responseData.latencyMs),
        errorMessage: typeof responseData.errorMessage === "string"
          ? responseData.errorMessage
          : null,
        responseTopic: typeof responseData.responseTopic === "string"
          ? responseData.responseTopic
          : null,
        workerId: typeof responseData.workerId === "string" ? responseData.workerId : null,
        createdAt: toIsoStringOrNull(responseData.createdAt),
      } : null;

      const buildTraceEntry = ({
        decisionId = null,
        decisionData = null,
        requestId,
        requestData = null,
        responseData = null,
      }) => {
        const sensorSnapshot = requestData?.sensorSnapshot && typeof requestData.sensorSnapshot === "object"
          ? requestData.sensorSnapshot
          : null;

        const fallbackStatus = typeof requestData?.status === "string"
          ? requestData.status
          : null;
        const fallbackMode = String(requestData?.mode || "manual").trim().toLowerCase();

        return {
          decisionId,
          plugId: normalizePlugId(decisionData?.plugId || requestData?.plugId) || plugId,
          sensorId: typeof decisionData?.sensorId === "string"
            ? decisionData.sensorId
            : (typeof sensorSnapshot?.serial === "string" ? sensorSnapshot.serial : null),
          profileId: typeof decisionData?.profileId === "string" ? decisionData.profileId : null,
          controlBasis: typeof decisionData?.controlBasis === "string"
            ? decisionData.controlBasis
            : (fallbackMode === "auto" ? "auto_request" : "manual_request"),
          command: typeof decisionData?.command === "string"
            ? decisionData.command
            : (typeof requestData?.command === "string" ? requestData.command : null),
          status: typeof decisionData?.status === "string" ? decisionData.status : fallbackStatus,
          queued: decisionData?.queued === true
            || fallbackStatus === "queued"
            || fallbackStatus === "pending",
          iaqiScore: toFiniteNumberOrNull(
            decisionData?.iaqiScore
              ?? sensorSnapshot?.iaqiScore
          ),
          pm25: toFiniteNumberOrNull(decisionData?.pm25 ?? sensorSnapshot?.pm25),
          thresholds: decisionData?.thresholds && typeof decisionData.thresholds === "object"
            ? decisionData.thresholds
            : (sensorSnapshot?.thresholds && typeof sensorSnapshot.thresholds === "object"
              ? sensorSnapshot.thresholds
              : null),
          requestId: requestId || null,
          decisionAt: toIsoStringOrNull(
            decisionData?.createdAt
              || decisionData?.updatedAt
              || requestData?.createdAt
              || requestData?.queuedAt
              || requestData?.updatedAt
          ),
          request: formatRequest(requestData),
          response: formatResponse(responseData),
        };
      };

      const decisionSnap = await db.collection("plug_control_decisions")
        .where("plugId", "==", plugId)
        .limit(decisionFetchLimit)
        .get();

      const decisionDocs = decisionSnap.docs
        .sort((left, right) => {
          const leftMs = toMillisOrNull((left.data() || {}).createdAt) || 0;
          const rightMs = toMillisOrNull((right.data() || {}).createdAt) || 0;
          return rightMs - leftMs;
        })
        .slice(0, limit);

      const requestSnapByPlug = await db.collection("plug_command_requests")
        .where("plugId", "==", plugId)
        .limit(requestFetchLimit)
        .get();

      const requestDocs = requestSnapByPlug.docs
        .sort((left, right) => {
          const leftData = left.data() || {};
          const rightData = right.data() || {};
          const leftMs = toMillisOrNull(leftData.createdAt || leftData.queuedAt || leftData.updatedAt) || 0;
          const rightMs = toMillisOrNull(rightData.createdAt || rightData.queuedAt || rightData.updatedAt) || 0;
          return rightMs - leftMs;
        })
        .slice(0, limit);

      const requestIds = [...new Set(decisionDocs
        .map((doc) => {
          const data = doc.data() || {};
          return typeof data.requestId === "string" ? data.requestId.trim() : "";
        })
        .filter((value) => Boolean(value)))];

      const requestIdsFromDocs = requestDocs
        .map((doc) => doc.id)
        .filter((value) => typeof value === "string" && value.length > 0);
      const allRequestIds = [...new Set([...requestIds, ...requestIdsFromDocs])];

      const requestMap = new Map();
      const responseMap = new Map();
      const decisionByRequestId = new Map();

      for (const requestDoc of requestDocs) {
        requestMap.set(requestDoc.id, requestDoc.data() || {});
      }

      for (const decisionDoc of decisionDocs) {
        const data = decisionDoc.data() || {};
        const requestId = typeof data.requestId === "string" ? data.requestId.trim() : "";
        if (!requestId || decisionByRequestId.has(requestId)) continue;
        decisionByRequestId.set(requestId, {
          decisionId: decisionDoc.id,
          decisionData: data,
        });
      }

      const unresolvedDecisionRequestIds = requestIds.filter((requestId) => !requestMap.has(requestId));

      if (unresolvedDecisionRequestIds.length) {
        const requestSnaps = await Promise.all(
          unresolvedDecisionRequestIds.map((requestId) => db.collection("plug_command_requests").doc(requestId).get())
        );

        for (const requestSnap of requestSnaps) {
          if (!requestSnap.exists) continue;
          requestMap.set(requestSnap.id, requestSnap.data() || {});
        }
      }

      if (allRequestIds.length) {
        const responseSnaps = await Promise.all(
          allRequestIds.map((requestId) => db.collection("plug_command_responses")
            .where("requestId", "==", requestId)
            .limit(20)
            .get())
        );

        for (const snap of responseSnaps) {
          if (snap.empty) continue;

          const sorted = snap.docs.sort((left, right) => {
            const leftMs = toMillisOrNull((left.data() || {}).createdAt) || 0;
            const rightMs = toMillisOrNull((right.data() || {}).createdAt) || 0;
            return rightMs - leftMs;
          });

          const latest = sorted[0];
          const latestData = latest.data() || {};
          const requestId = typeof latestData.requestId === "string"
            ? latestData.requestId.trim()
            : "";
          if (!requestId || responseMap.has(requestId)) continue;
          responseMap.set(requestId, latestData);
        }
      }

      const traces = [];

      for (const decisionDoc of decisionDocs) {
        const decisionData = decisionDoc.data() || {};
        const requestId = typeof decisionData.requestId === "string"
          ? decisionData.requestId.trim()
          : "";
        const requestData = requestId ? (requestMap.get(requestId) || null) : null;
        const responseData = requestId ? (responseMap.get(requestId) || null) : null;

        traces.push(buildTraceEntry({
          decisionId: decisionDoc.id,
          decisionData,
          requestId,
          requestData,
          responseData,
        }));
      }

      for (const requestDoc of requestDocs) {
        const requestId = requestDoc.id;
        if (decisionByRequestId.has(requestId)) {
          continue;
        }

        const requestData = requestMap.get(requestId) || requestDoc.data() || null;
        const responseData = responseMap.get(requestId) || null;

        traces.push(buildTraceEntry({
          decisionId: null,
          decisionData: null,
          requestId,
          requestData,
          responseData,
        }));
      }

      traces.sort((left, right) => {
        const leftMs = toMillisOrNull(left.decisionAt) || 0;
        const rightMs = toMillisOrNull(right.decisionAt) || 0;
        return rightMs - leftMs;
      });

      const limitedTraces = traces.slice(0, limit);

      return res.status(200).json({
        ok: true,
        plugId,
        count: limitedTraces.length,
        traces: limitedTraces,
      });
    } catch (error) {
      logger.error("get_plug_control_trace_failed", { plugId, error: error?.message || error });
      return res.status(500).json({ ok: false, error: "internal_error" });
    }
  }
);

exports.ingest = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({ ok: false, error: "method_not_allowed" });
    }

    const requiredApiKey = process.env.INGEST_API_KEY;
    const incomingApiKey = req.get("X-API-Key");

    if (!requiredApiKey || incomingApiKey !== requiredApiKey) {
      return unauthorized(res);
    }

    const {
      serial,
      pm25,
      co2,
      tvoc,
      nox,
      temp,
      humidity,
      firmware,
      timestamp,
      ip,
    } = req.body || {};

    if (!serial || typeof serial !== "string") {
      return badRequest(res, "serial_is_required");
    }

    const parsedPm25 = toFiniteNumber(pm25);
    const parsedCo2 = toFiniteNumber(co2);
    const parsedTvoc = toFiniteNumber(tvoc);
    const parsedNox = toFiniteNumber(nox);
    const parsedTemp = toFiniteNumber(temp);
    const parsedHumidity = toFiniteNumber(humidity);
    const parsedK = toFiniteNumberOrNull((req.body || {}).k);

    const sensorId = serial.trim();
    const measuredAt = toDateOrNow(timestamp);
    const measuredAtTs = admin.firestore.Timestamp.fromDate(measuredAt);
    const sensorRef = db.collection("sensors").doc(sensorId);

    if (shouldThrottleIngest(sensorId, measuredAt)) {
      return res.status(200).json({
        ok: true,
        sensorId,
        timestamp: measuredAt.toISOString(),
        throttled: true,
        minIntervalSeconds: INGEST_MIN_INTERVAL_SECONDS,
      });
    }

    const resolvedK = await resolveIaqiKValue({
      sensorRef,
      measuredAt,
      pm25: parsedPm25,
      co2: parsedCo2,
    });
    const parsedKEffective = resolvedK.k;

    const parsedIaqiBundle = buildIaqiBundle({
      co2: parsedCo2,
      pm25: parsedPm25,
      k: parsedKEffective,
      voc: parsedTvoc,
      temp: parsedTemp,
      humi: parsedHumidity,
    });
    const parsedIaqi = parsedIaqiBundle?.iaqi || null;
    const parsedIaqiScore = Number.isFinite(parsedIaqiBundle?.iaqiScore)
      ? parsedIaqiBundle.iaqiScore
      : null;

    const nowTs = admin.firestore.FieldValue.serverTimestamp();

    const latest = {
      pm25: parsedPm25,
      iaqi: parsedIaqi,
      iaqiScore: parsedIaqiScore,
      co2: parsedCo2,
      tvoc: parsedTvoc,
      nox: parsedNox,
      temp: parsedTemp,
      humidity: parsedHumidity,
      k: Number.isFinite(parsedK) ? parsedK : null,
      kEffective: parsedKEffective,
      kSource: resolvedK.source,
      kPm25: resolvedK.kPm25,
      kCo2: resolvedK.kCo2,
      kR2Pm25: resolvedK.r2Pm25,
      kR2Co2: resolvedK.r2Co2,
      kSampleCountPm25: resolvedK.pmSampleCount,
      kSampleCountCo2: resolvedK.co2SampleCount,
      timestamp: measuredAtTs,
      source: "esphome",
    };

    const historyRef = DISABLE_SENSOR_HISTORY_WRITES
      ? null
      : sensorRef.collection("history").doc();

    try {
      await db.runTransaction(async (tx) => {
        tx.set(
          sensorRef,
          {
            serial: sensorId,
            latest,
            firmware: typeof firmware === "string" ? firmware : null,
            ip: typeof ip === "string" ? ip : null,
            lastSeen: nowTs,
            updatedAt: nowTs,
          },
          { merge: true }
        );

        if (!DISABLE_SENSOR_HISTORY_WRITES && historyRef) {
          tx.set(
            historyRef,
            withExpireAt(
              {
                ...latest,
                serial: sensorId,
                firmware: typeof firmware === "string" ? firmware : null,
                createdAt: nowTs,
              },
              SENSOR_HISTORY_RETENTION_DAYS,
              measuredAt
            )
          );
        }
      });

      const snapshotPayload = {
        serial: sensorId,
        raw: {
          pm25: parsedPm25,
          iaqi: parsedIaqi,
          iaqiScore: parsedIaqiScore,
          co2: parsedCo2,
          tvoc: parsedTvoc,
          nox: parsedNox,
          temp: parsedTemp,
          humidity: parsedHumidity,
          k: Number.isFinite(parsedK) ? parsedK : null,
          kEffective: parsedKEffective,
          kSource: resolvedK.source,
          kPm25: resolvedK.kPm25,
          kCo2: resolvedK.kCo2,
          kR2Pm25: resolvedK.r2Pm25,
          kR2Co2: resolvedK.r2Co2,
          kSampleCountPm25: resolvedK.pmSampleCount,
          kSampleCountCo2: resolvedK.co2SampleCount,
        },
        pm25: parsedPm25,
        iaqi: parsedIaqi,
        iaqiScore: parsedIaqiScore,
        co2: parsedCo2,
        tvoc: parsedTvoc,
        nox: parsedNox,
        temp: parsedTemp,
        humidity: parsedHumidity,
        k: Number.isFinite(parsedK) ? parsedK : null,
        kEffective: parsedKEffective,
        kSource: resolvedK.source,
        kPm25: resolvedK.kPm25,
        kCo2: resolvedK.kCo2,
        kR2Pm25: resolvedK.r2Pm25,
        kR2Co2: resolvedK.r2Co2,
        kSampleCountPm25: resolvedK.pmSampleCount,
        kSampleCountCo2: resolvedK.co2SampleCount,
        firmware: typeof firmware === "string" ? firmware : null,
        timestamp: measuredAt.toISOString(),
      };

      try {
        await dispatchAlertsForSnapshot(snapshotPayload);
      } catch (alertError) {
        logger.error("alert_dispatch_failed", {
          sensorId,
          error: alertError?.message || alertError,
        });
      }

      try {
        await dispatchAutoControlForSnapshot(snapshotPayload);
      } catch (autoControlError) {
        logger.error("auto_control_dispatch_failed", {
          sensorId,
          error: autoControlError?.message || autoControlError,
        });
      }

      return res.status(200).json({
        ok: true,
        sensorId,
        iaqi: parsedIaqi,
        iaqiScore: parsedIaqiScore,
        k: Number.isFinite(parsedK) ? parsedK : null,
        kEffective: parsedKEffective,
        kSource: resolvedK.source,
        timestamp: measuredAt.toISOString(),
      });
    } catch (error) {
      logger.error("ingest_failed", { sensorId, error: error?.message || error });
      return res.status(500).json({ ok: false, error: "internal_error" });
    }
  }
);

exports.registerDevice = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (!ensurePost(req, res)) return;
    if (!validateOptionalApiKey(req, res)) return;

    const {
      token,
      fcmToken,
      sensorId,
      timezone,
      alertsEnabled,
      quietHours,
      quietHoursEnabled,
      snoozedUntil,
      mutedTypes,
      notificationIntervalMinutes,
      minimumSeverityPriority,
      minimumSeverityByType,
      fireRiskMinimumLevel,
    } = req.body || {};

    if (!token || typeof token !== "string") {
      return badRequest(res, "token_is_required");
    }

    const docId = token.trim();
    const resolvedSensorId = typeof sensorId === "string" && sensorId.trim()
      ? sensorId.trim()
      : null;
    const resolvedFcmToken = typeof fcmToken === "string" && fcmToken.trim()
      ? fcmToken.trim()
      : null;

    const payload = {
      token: docId,
      sensorId: resolvedSensorId,
      firestoreDocPath: resolvedSensorId ? `sensors/${resolvedSensorId}` : null,
      timezone: typeof timezone === "string" ? timezone : null,
      alertsEnabled: typeof alertsEnabled === "boolean" ? alertsEnabled : true,
      quietHours: normalizeQuietHours(quietHours),
      quietHoursEnabled: typeof quietHoursEnabled === "boolean"
        ? quietHoursEnabled
        : Boolean(quietHours),
      snoozedUntil: parseSnoozedUntil(snoozedUntil),
      mutedTypes: mutedTypes && typeof mutedTypes === "object" ? mutedTypes : {},
      notificationIntervalMinutes:
        normalizeNotificationIntervalMinutes(notificationIntervalMinutes),
      minimumSeverityPriority:
        normalizeMinimumSeverityPriority(minimumSeverityPriority),
      minimumSeverityByType:
        minimumSeverityByType && typeof minimumSeverityByType === "object"
          ? Object.fromEntries(
            Object.entries(minimumSeverityByType).map(([type, priority]) => [
              type,
              normalizeMinimumSeverityPriority(priority),
            ])
          )
          : {},
      fireRiskMinimumLevel: normalizeFireRiskMinimumLevel(fireRiskMinimumLevel),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (resolvedFcmToken) {
      payload.fcmToken = resolvedFcmToken;
      payload.pushDisabled = false;
    }

    try {
      await db.collection("devices").doc(docId).set(payload, { merge: true });
      return res.status(200).json({
        ok: true,
        token: docId,
        sensorId: resolvedSensorId,
        firestoreDocPath: resolvedSensorId ? `sensors/${resolvedSensorId}` : null,
      });
    } catch (error) {
      logger.error("register_device_failed", { error: error?.message || error });
      return res.status(500).json({ ok: false, error: "internal_error" });
    }
  }
);

exports.claimDevice = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (!ensurePost(req, res)) return;
    if (!validateOptionalApiKey(req, res)) return;

    const { token, code } = req.body || {};
    if (!token || typeof token !== "string") {
      return badRequest(res, "token_is_required");
    }
    if (!code || typeof code !== "string") {
      return badRequest(res, "code_is_required");
    }

    const tokenId = token.trim();
    const codeId = code.trim();
    let claimedSensorId = null;

    try {
      await db.runTransaction(async (tx) => {
        const codeRef = db.collection("device_codes").doc(codeId);
        const deviceRef = db.collection("devices").doc(tokenId);
        const codeDoc = await tx.get(codeRef);

        if (!codeDoc.exists) {
          throw new Error("invalid_code");
        }

        const codeData = codeDoc.data() || {};
        const sensorId = typeof codeData.sensorId === "string" ? codeData.sensorId : null;
        if (!sensorId) {
          throw new Error("code_missing_sensor");
        }

        const claimedBy = codeData.claimedBy || null;
        if (claimedBy && claimedBy !== tokenId) {
          throw new Error("code_already_claimed");
        }

        if (!claimedBy) {
          const expiresAt = codeData.expiresAt?.toDate
            ? codeData.expiresAt.toDate()
            : null;
          if (!expiresAt || expiresAt.getTime() <= Date.now()) {
            throw new Error("code_expired");
          }
        }

        claimedSensorId = sensorId;

        tx.set(deviceRef, {
          token: tokenId,
          sensorId,
          firestoreDocPath: `sensors/${sensorId}`,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        if (!claimedBy) {
          tx.set(codeRef, {
            claimedBy: tokenId,
            claimedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
      });

      return res.status(200).json({
        ok: true,
        token: tokenId,
        sensorId: claimedSensorId,
        firestoreDocPath: claimedSensorId ? `sensors/${claimedSensorId}` : null,
      });
    } catch (error) {
      const message = error?.message || "internal_error";
      if (["invalid_code", "code_missing_sensor", "code_already_claimed", "code_expired"].includes(message)) {
        return res.status(400).json({ ok: false, error: message });
      }
      logger.error("claim_device_failed", { error: message });
      return res.status(500).json({ ok: false, error: "internal_error" });
    }
  }
);

exports.updatePreferences = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (!ensurePost(req, res)) return;
    if (!validateOptionalApiKey(req, res)) return;

    const {
      token,
      alertsEnabled,
      quietHours,
      quietHoursEnabled,
      snoozedUntil,
      mutedTypes,
      notificationIntervalMinutes,
      minimumSeverityPriority,
      minimumSeverityByType,
      fireRiskMinimumLevel,
      timezone,
    } = req.body || {};

    if (!token || typeof token !== "string") {
      return badRequest(res, "token_is_required");
    }

    const updatePayload = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (typeof alertsEnabled === "boolean") {
      updatePayload.alertsEnabled = alertsEnabled;
    }
    if (quietHours !== undefined) {
      updatePayload.quietHours = normalizeQuietHours(quietHours);
    }
    if (typeof quietHoursEnabled === "boolean") {
      updatePayload.quietHoursEnabled = quietHoursEnabled;
    }
    if (snoozedUntil !== undefined) {
      updatePayload.snoozedUntil = parseSnoozedUntil(snoozedUntil);
    }
    if (mutedTypes && typeof mutedTypes === "object") {
      updatePayload.mutedTypes = mutedTypes;
    }
    if (notificationIntervalMinutes !== undefined) {
      updatePayload.notificationIntervalMinutes =
        normalizeNotificationIntervalMinutes(notificationIntervalMinutes);
    }
    if (minimumSeverityPriority !== undefined) {
      updatePayload.minimumSeverityPriority =
        normalizeMinimumSeverityPriority(minimumSeverityPriority);
    }
    if (minimumSeverityByType && typeof minimumSeverityByType === "object") {
      updatePayload.minimumSeverityByType = Object.fromEntries(
        Object.entries(minimumSeverityByType).map(([type, priority]) => [
          type,
          normalizeMinimumSeverityPriority(priority),
        ])
      );
    }
    if (fireRiskMinimumLevel !== undefined) {
      updatePayload.fireRiskMinimumLevel =
        normalizeFireRiskMinimumLevel(fireRiskMinimumLevel);
    }
    if (timezone !== undefined) {
      updatePayload.timezone = typeof timezone === "string" ? timezone : null;
    }

    const tokenId = token.trim();

    try {
      await db.collection("devices").doc(tokenId).set(updatePayload, { merge: true });
      return res.status(200).json({ ok: true, token: tokenId });
    } catch (error) {
      logger.error("update_preferences_failed", { error: error?.message || error });
      return res.status(500).json({ ok: false, error: "internal_error" });
    }
  }
);

exports.getDevicePreferences = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (!ensurePost(req, res)) return;
    if (!validateOptionalApiKey(req, res)) return;

    const { token } = req.body || {};
    if (!token || typeof token !== "string") {
      return badRequest(res, "token_is_required");
    }

    const tokenId = token.trim();

    try {
      const doc = await db.collection("devices").doc(tokenId).get();
      if (!doc.exists) {
        return res.status(200).json({
          ok: true,
          token: tokenId,
          device: null,
        });
      }

      const data = doc.data() || {};
      return res.status(200).json({
        ok: true,
        token: tokenId,
        device: {
          sensorId: data.sensorId || null,
          firestoreDocPath: data.firestoreDocPath || null,
          alertsEnabled: data.alertsEnabled !== false,
          quietHours: data.quietHours || null,
          quietHoursEnabled: Boolean(data.quietHoursEnabled),
          snoozedUntil: toIsoStringOrNull(data.snoozedUntil),
          mutedTypes: data.mutedTypes || {},
          notificationIntervalMinutes:
            normalizeNotificationIntervalMinutes(data.notificationIntervalMinutes),
          minimumSeverityPriority:
            normalizeMinimumSeverityPriority(data.minimumSeverityPriority),
          minimumSeverityByType:
            data.minimumSeverityByType && typeof data.minimumSeverityByType === "object"
              ? data.minimumSeverityByType
              : {},
          lastDeliveredAt: toIsoStringOrNull(data.lastDeliveredAt),
          lastDeliveredByType: data.lastDeliveredByType || {},
          pushDisabled: data.pushDisabled === true,
          updatedAt: toIsoStringOrNull(data.updatedAt),
        },
      });
    } catch (error) {
      logger.error("get_device_preferences_failed", {
        error: error?.message || error,
      });
      return res.status(500).json({ ok: false, error: "internal_error" });
    }
  }
);

exports.generateDeviceCode = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (!ensurePost(req, res)) return;
    if (!validateOptionalApiKey(req, res)) return;

    const { sensorId } = req.body || {};
    if (!sensorId || typeof sensorId !== "string") {
      return badRequest(res, "sensorId_is_required");
    }

    const normalizedSensorId = sensorId.trim();
    const code = generateDeviceCode();
    const expiresAt = new Date(Date.now() + DEVICE_CODE_TTL_MINUTES * 60 * 1000);

    try {
      const existingDevices = await listDevicesForSensor(normalizedSensorId);
      if (existingDevices.length > 0) {
        return res.status(200).json({
          ok: true,
          sensorId: normalizedSensorId,
          alreadyClaimed: true,
          code: null,
        });
      }

      await db.collection("device_codes").doc(code).set({
        sensorId: normalizedSensorId,
        expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
        claimedBy: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return res.status(200).json({
        ok: true,
        code,
        sensorId: normalizedSensorId,
        expiresAt: expiresAt.toISOString(),
      });
    } catch (error) {
      logger.error("generate_device_code_failed", { error: error?.message || error });
      return res.status(500).json({ ok: false, error: "internal_error" });
    }
  }
);

async function registerRelayServer(serverId, serverUrl) {
  await db.collection("relay_servers").doc(serverId).set(
    {
      serverId,
      serverUrl,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

function relayPath(req) {
  const path = typeof req.path === "string" ? req.path : (req.url || "");
  return String(path).split("?")[0];
}

function normalizeRelayMacAddress(rawValue) {
  if (!rawValue) return "";
  return String(rawValue).replace(/:/g, "").trim().toLowerCase();
}

exports.relay = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.set("Allow", "POST");
      return res.status(405).json({ ok: false, error: "method_not_allowed" });
    }

    const path = relayPath(req);
    const body = req.body || {};

    if (path === "/api/relay/register-server") {
      const serverId = String(body.serverId || req.query?.serverId || "").trim();
      const serverUrl = String(body.serverUrl || req.query?.serverUrl || "").trim();
      if (!serverId || !serverUrl) {
        return res.status(400).json({ ok: false, error: "serverId_and_serverUrl_required" });
      }

      try {
        await registerRelayServer(serverId, serverUrl);
        return res.status(200).json({ ok: true });
      } catch (error) {
        logger.error("relay_register_failed", { error: error?.message || error });
        return res.status(500).json({ ok: false, error: "relay_register_failed" });
      }
    }

    const pathRegisterMatch = path.match(/^\/api\/relay\/register-server-path\/([^/]+)\/([^/]+)$/);
    if (pathRegisterMatch) {
      const serverId = String(pathRegisterMatch[1] || "").trim();
      const encoded = String(pathRegisterMatch[2] || "").trim();
      let serverUrl = "";
      try {
        serverUrl = Buffer.from(encoded, "base64url").toString("utf8").trim();
      } catch (_) {
        return res.status(400).json({ ok: false, error: "invalid_serverUrlB64" });
      }

      if (!serverId || !serverUrl) {
        return res.status(400).json({ ok: false, error: "serverId_and_serverUrl_required" });
      }

      try {
        await registerRelayServer(serverId, serverUrl);
        return res.status(200).json({ ok: true });
      } catch (error) {
        logger.error("relay_register_path_failed", { error: error?.message || error });
        return res.status(500).json({ ok: false, error: "relay_register_failed" });
      }
    }

    if (path === "/api/relay/bind-token") {
      const token = String(body.token || "").trim();
      const serverId = String(body.serverId || "").trim();
      if (!token || !serverId) {
        return res.status(400).json({ ok: false, error: "token_and_serverId_required" });
      }

      try {
        const serverRef = db.collection("relay_servers").doc(serverId);
        const serverSnap = await serverRef.get();
        if (!serverSnap.exists) {
          return res.status(404).json({ ok: false, error: "server_not_found" });
        }

        const serverUrl = serverSnap.data()?.serverUrl || null;
        await db.collection("relay_tokens").doc(token).set(
          {
            token,
            serverId,
            serverUrl,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        return res.status(200).json({ ok: true, serverId, serverUrl });
      } catch (error) {
        logger.error("relay_bind_failed", { error: error?.message || error });
        return res.status(500).json({ ok: false, error: "relay_bind_failed" });
      }
    }

    if (path === "/api/relay/resolve-server") {
      const token = String(body.token || "").trim();
      if (!token) {
        return res.status(400).json({ ok: false, error: "token_required" });
      }

      try {
        const tokenRef = db.collection("relay_tokens").doc(token);
        const tokenSnap = await tokenRef.get();
        if (tokenSnap.exists) {
          const data = tokenSnap.data() || {};
          return res.status(200).json({
            ok: true,
            serverId: data.serverId || null,
            serverUrl: data.serverUrl || null,
          });
        }

        const serversSnap = await db
          .collection("relay_servers")
          .orderBy("updatedAt", "desc")
          .limit(1)
          .get();
        if (serversSnap.empty) {
          return res.status(404).json({ ok: false, error: "no_servers_available" });
        }

        const serverDoc = serversSnap.docs[0];
        const serverData = serverDoc.data() || {};
        const serverId = serverData.serverId || serverDoc.id;
        const serverUrl = serverData.serverUrl || null;

        await tokenRef.set(
          {
            token,
            serverId,
            serverUrl,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        return res.status(200).json({ ok: true, serverId, serverUrl });
      } catch (error) {
        logger.error("relay_resolve_failed", { error: error?.message || error });
        return res.status(500).json({ ok: false, error: "relay_resolve_failed" });
      }
    }

    if (path === "/api/relay/sensor") {
      try {
        const normalizedMac = normalizeRelayMacAddress(body.macAddress);
        if (!normalizedMac) {
          return res.status(400).json({ ok: false, error: "macAddress_required" });
        }

        const requestCode = body.requestCode === true ||
          body.requestCode === "true" ||
          body.requestCode === 1 ||
          body.requestCode === "1";
        const nowDate = new Date();
        const relayPm25 = toFiniteNumber(body.pm02);
        const relayCo2 = toFiniteNumber(body.rco2);
        const relayTemp = toFiniteNumber(body.temp);
        const relayHumidity = toFiniteNumber(body.rhum);
        const relayTvoc = toFiniteNumber(body.tvoc);
        const relayK = toFiniteNumberOrNull(body.k);
        const sensorRef = db.collection("sensors").doc(normalizedMac);
        const resolvedRelayK = await resolveIaqiKValue({
          sensorRef,
          measuredAt: nowDate,
          pm25: relayPm25,
          co2: relayCo2,
        });
        const relayKEffective = resolvedRelayK.k;
        const relayIaqiBundle = buildIaqiBundle({
          co2: relayCo2,
          pm25: relayPm25,
          k: relayKEffective,
          voc: relayTvoc,
          temp: relayTemp,
          humi: relayHumidity,
        });
        const relayIaqi = relayIaqiBundle?.iaqi || null;
        const relayIaqiScore = Number.isFinite(relayIaqiBundle?.iaqiScore)
          ? relayIaqiBundle.iaqiScore
          : null;

        const timestamp = admin.firestore.FieldValue.serverTimestamp();
        const sensorData = {
          pm25: relayPm25,
          iaqi: relayIaqi,
          iaqiScore: relayIaqiScore,
          co2: relayCo2,
          tvoc: relayTvoc,
          nox: toFiniteNumber(body.nox),
          temp: relayTemp,
          humidity: relayHumidity,
          k: Number.isFinite(relayK) ? relayK : null,
          kEffective: relayKEffective,
          kSource: resolvedRelayK.source,
          kPm25: resolvedRelayK.kPm25,
          kCo2: resolvedRelayK.kCo2,
          kR2Pm25: resolvedRelayK.r2Pm25,
          kR2Co2: resolvedRelayK.r2Co2,
          kSampleCountPm25: resolvedRelayK.pmSampleCount,
          kSampleCountCo2: resolvedRelayK.co2SampleCount,
          timestamp,
        };

        if (!DISABLE_RELAY_SERIES_WRITES) {
          await sensorRef.collection("series").add(
            withExpireAt(
              {
                macAddress: normalizedMac,
                ...sensorData,
              },
              SENSOR_HISTORY_RETENTION_DAYS,
              nowDate
            )
          );
        }

        await sensorRef.set(
          {
            latest: sensorData,
            lastSeen: timestamp,
          },
          { merge: true }
        );

        if (!DISABLE_RELAY_HISTORY_WRITES) {
          await sensorRef.collection("history").add(
            withExpireAt(
              {
                createdAt: timestamp,
                ...sensorData,
              },
              SENSOR_HISTORY_RETENTION_DAYS,
              nowDate
            )
          );
        }

        if (!requestCode) {
          return res.status(200).json({ ok: true });
        }

        const devicesForSensor = await listDevicesForSensor(normalizedMac);
        const alreadyClaimed = devicesForSensor.length > 0;

        let code = null;
        let expiresAt = null;
        const nowMs = Date.now();

        const activeCodesSnapshot = await db.collection("device_codes")
          .where("sensorId", "==", normalizedMac)
          .where("claimedBy", "==", null)
          .limit(20)
          .get();

        activeCodesSnapshot.forEach((doc) => {
          if (code) {
            return;
          }

          const data = doc.data() || {};
          const docExpiresAt = data.expiresAt?.toDate ? data.expiresAt.toDate() : null;
          if (docExpiresAt && docExpiresAt.getTime() > nowMs) {
            code = doc.id;
            expiresAt = docExpiresAt.toISOString();
          }
        });

        if (!code) {
          code = generateDeviceCode();
          const codeExpiryDate = new Date(nowMs + DEVICE_CODE_TTL_MINUTES * 60 * 1000);
          expiresAt = codeExpiryDate.toISOString();

          await db.collection("device_codes").doc(code).set({
            sensorId: normalizedMac,
            expiresAt: admin.firestore.Timestamp.fromDate(codeExpiryDate),
            claimedBy: null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        return res.status(200).json({
          ok: true,
          code,
          alreadyClaimed,
          expiresAt,
        });
      } catch (error) {
        logger.error("relay_sensor_failed", { error: error?.message || error });
        return res.status(500).json({ ok: false, error: "relay_sensor_failed" });
      }
    }

    return res.status(404).json({ ok: false, error: "not_found" });
  }
);

async function deleteOldDocs(collectionRef, fieldName, cutoffTs, maxDeletes = Number.POSITIVE_INFINITY) {
  let deletedCount = 0;

  while (true) {
    const remaining = maxDeletes - deletedCount;
    if (remaining <= 0) {
      break;
    }

    const queryLimit = Math.max(1, Math.min(500, remaining));
    const snapshot = await collectionRef
      .where(fieldName, "<", cutoffTs)
      .limit(queryLimit)
      .get();

    if (snapshot.empty) {
      break;
    }

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deletedCount += snapshot.size;

    if (snapshot.size < queryLimit) {
      break;
    }
  }

  return deletedCount;
}

exports.scheduledDataCleanup = onSchedule(
  {
    region: "asia-northeast3",
    schedule: "0 0 * * *",
    timeZone: "Asia/Seoul",
  },
  async () => {
    const daysToKeep = SENSOR_HISTORY_RETENTION_DAYS;
    const cutoffDate = new Date(Date.now() - daysToKeep * 24 * 60 * 60 * 1000);
    const cutoffTs = admin.firestore.Timestamp.fromDate(cutoffDate);
    const plugLogDaysToKeep = PLUG_LOG_RETENTION_DAYS;
    const plugCutoffDate = new Date(Date.now() - plugLogDaysToKeep * 24 * 60 * 60 * 1000);
    const plugCutoffTs = admin.firestore.Timestamp.fromDate(plugCutoffDate);
    logger.info("scheduled_cleanup_started", {
      cutoffDate: cutoffDate.toISOString(),
      plugCutoffDate: plugCutoffDate.toISOString(),
      cleanupMaxDeletesPerRun: CLEANUP_MAX_DELETES_PER_RUN,
      ttlSensorCollectionsEnabled: TTL_SENSOR_COLLECTIONS_ENABLED,
      ttlPlugLogCollectionsEnabled: TTL_PLUG_LOG_COLLECTIONS_ENABLED,
    });

    let deletedCount = 0;

    if (!TTL_SENSOR_COLLECTIONS_ENABLED) {
      try {
        deletedCount += await deleteOldDocs(
          db.collectionGroup("history"),
          "createdAt",
          cutoffTs,
          CLEANUP_MAX_DELETES_PER_RUN - deletedCount
        );
        deletedCount += await deleteOldDocs(
          db.collectionGroup("series"),
          "timestamp",
          cutoffTs,
          CLEANUP_MAX_DELETES_PER_RUN - deletedCount
        );
      } catch (error) {
        logger.warn("scheduled_cleanup_collection_group_fallback", {
          error: error?.message || error,
        });

        const sensorsSnap = await db.collection("sensors").get();
        for (const sensorDoc of sensorsSnap.docs) {
          if (deletedCount >= CLEANUP_MAX_DELETES_PER_RUN) {
            break;
          }

          const sensorRef = db.collection("sensors").doc(sensorDoc.id);
          deletedCount += await deleteOldDocs(
            sensorRef.collection("history"),
            "createdAt",
            cutoffTs,
            CLEANUP_MAX_DELETES_PER_RUN - deletedCount
          );

          if (deletedCount >= CLEANUP_MAX_DELETES_PER_RUN) {
            break;
          }

          deletedCount += await deleteOldDocs(
            sensorRef.collection("series"),
            "timestamp",
            cutoffTs,
            CLEANUP_MAX_DELETES_PER_RUN - deletedCount
          );
        }
      }
    } else {
      logger.info("scheduled_cleanup_sensor_skip_ttl", {
        reason: "ttl_sensor_collections_enabled",
      });
    }

    if (!TTL_PLUG_LOG_COLLECTIONS_ENABLED) {
      if (deletedCount < CLEANUP_MAX_DELETES_PER_RUN) {
        deletedCount += await deleteOldDocs(
          db.collection("plug_command_requests"),
          "createdAt",
          plugCutoffTs,
          CLEANUP_MAX_DELETES_PER_RUN - deletedCount
        );
      }
      if (deletedCount < CLEANUP_MAX_DELETES_PER_RUN) {
        deletedCount += await deleteOldDocs(
          db.collection("plug_command_responses"),
          "createdAt",
          plugCutoffTs,
          CLEANUP_MAX_DELETES_PER_RUN - deletedCount
        );
      }
      if (deletedCount < CLEANUP_MAX_DELETES_PER_RUN) {
        deletedCount += await deleteOldDocs(
          db.collection("plug_command_queue"),
          "createdAt",
          plugCutoffTs,
          CLEANUP_MAX_DELETES_PER_RUN - deletedCount
        );
      }
      if (deletedCount < CLEANUP_MAX_DELETES_PER_RUN) {
        deletedCount += await deleteOldDocs(
          db.collection("plug_state_history"),
          "createdAt",
          plugCutoffTs,
          CLEANUP_MAX_DELETES_PER_RUN - deletedCount
        );
      }
    } else {
      logger.info("scheduled_cleanup_plug_skip_ttl", {
        reason: "ttl_plug_log_collections_enabled",
      });
    }

    logger.info("scheduled_cleanup_finished", { deletedCount });
  }
);

exports.scheduledPlugAutoControl = onSchedule(
  {
    region: "asia-northeast3",
    schedule: "* * * * *",
    timeZone: "Asia/Seoul",
  },
  async () => {
    if (isEnvTrue(process.env.DISABLE_PLUG_AUTO_CONTROL_SWEEP)) {
      logger.info("scheduled_plug_auto_control_skipped", {
        reason: "disabled_by_env",
      });
      return;
    }

    try {
      const result = await dispatchAutoControlForRegisteredPlugs();
      logger.info("scheduled_plug_auto_control_finished", result);
    } catch (error) {
      logger.error("scheduled_plug_auto_control_failed", {
        error: error?.message || error,
      });
    }
  }
);
