const mqtt = require("mqtt");

const mqttUrl = String(process.env.MQTT_URL || "mqtt://broker.hivemq.com:1883").trim();
const mqttUsername = process.env.MQTT_USERNAME || undefined;
const mqttPassword = process.env.MQTT_PASSWORD || undefined;
const tasmotaTopic = String(process.env.TASMOTA_TOPIC || "smoke_tasmota").trim();
const initialState = String(process.env.INITIAL_POWER || "OFF").trim().toUpperCase();
const clientId = String(
  process.env.SIM_CLIENT_ID || `tasmota-sim-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`
).trim();
const qos = [0, 1, 2].includes(Number(process.env.SIM_QOS)) ? Number(process.env.SIM_QOS) : 1;

if (!mqttUrl) {
  throw new Error("MQTT_URL is required");
}
if (!tasmotaTopic) {
  throw new Error("TASMOTA_TOPIC is required");
}

let powerState = initialState === "ON" ? "ON" : "OFF";

const cmndTopic = `cmnd/${tasmotaTopic}/Power`;
const statPowerTopic = `stat/${tasmotaTopic}/POWER`;
const statResultTopic = `stat/${tasmotaTopic}/RESULT`;
const lwtTopic = `tele/${tasmotaTopic}/LWT`;

function nowIso() {
  return new Date().toISOString();
}

function publishState(reason) {
  const resultPayload = JSON.stringify({
    POWER: powerState,
    source: "tasmota-simulator",
    reason,
    timestamp: Date.now(),
  });

  client.publish(statPowerTopic, powerState, { qos, retain: false });
  client.publish(statResultTopic, resultPayload, { qos, retain: false });

  console.log(
    `[${nowIso()}] state published topic=${tasmotaTopic} power=${powerState} reason=${reason}`
  );
}

function applyPowerCommand(rawCommand) {
  const command = String(rawCommand || "").trim().toUpperCase();
  if (command === "ON") {
    powerState = "ON";
    return true;
  }
  if (command === "OFF") {
    powerState = "OFF";
    return true;
  }
  if (command === "TOGGLE") {
    powerState = powerState === "ON" ? "OFF" : "ON";
    return true;
  }
  return false;
}

const client = mqtt.connect(mqttUrl, {
  username: mqttUsername,
  password: mqttPassword,
  clientId,
  clean: true,
  reconnectPeriod: 1500,
  keepalive: 30,
  will: {
    topic: lwtTopic,
    payload: "Offline",
    qos,
    retain: true,
  },
});

client.on("connect", () => {
  console.log(`[${nowIso()}] simulator connected clientId=${clientId} topic=${tasmotaTopic}`);

  client.subscribe(cmndTopic, { qos }, (error) => {
    if (error) {
      console.error(`[${nowIso()}] subscribe failed for ${cmndTopic}`, error);
      return;
    }

    client.publish(lwtTopic, "Online", { qos, retain: true });
    publishState("boot");
  });
});

client.on("message", (topic, payloadBuffer) => {
  if (topic !== cmndTopic) {
    return;
  }

  const payloadText = payloadBuffer.toString("utf8").trim();
  const applied = applyPowerCommand(payloadText);

  if (!applied) {
    console.warn(`[${nowIso()}] unsupported command payload=${payloadText}`);
    publishState("unsupported_command");
    return;
  }

  console.log(`[${nowIso()}] command received topic=${topic} payload=${payloadText}`);
  publishState(payloadText);
});

client.on("reconnect", () => {
  console.log(`[${nowIso()}] simulator reconnecting...`);
});

client.on("error", (error) => {
  console.error(`[${nowIso()}] simulator MQTT error`, error);
});

function shutdown(signal) {
  console.log(`[${nowIso()}] simulator shutdown signal=${signal}`);
  try {
    client.publish(lwtTopic, "Offline", { qos, retain: true });
  } catch (_) {
    // ignore publish failure during shutdown
  }
  client.end(true, () => {
    process.exit(0);
  });
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

console.log(`[${nowIso()}] tasmota simulator started mqttUrl=${mqttUrl} topic=${tasmotaTopic}`);
