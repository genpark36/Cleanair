const mqtt = require("mqtt");

const mqttUrl = process.env.MQTT_URL || "mqtt://broker.hivemq.com:1883";
const topic = process.env.PROBE_TOPIC || "tasmota_604954";
const timeoutMs = Number(process.env.PROBE_TIMEOUT_MS || 20000);

const topics = [`tele/${topic}/LWT`, `stat/${topic}/#`];
const client = mqtt.connect(mqttUrl, {
  username: process.env.MQTT_USERNAME || undefined,
  password: process.env.MQTT_PASSWORD || undefined,
  reconnectPeriod: 0,
});

let gotMessage = false;

client.on("connect", () => {
  console.log(`connected mqttUrl=${mqttUrl}`);
  client.subscribe(topics, { qos: 1 }, (err) => {
    if (err) {
      console.error(`subscribe error: ${err.message}`);
      client.end(true);
      process.exit(2);
      return;
    }
    console.log(`subscribed topics=${topics.join(",")}`);
  });

  setTimeout(() => {
    if (!gotMessage) {
      console.log("no_messages_observed");
    }
    client.end(true, () => process.exit(0));
  }, timeoutMs);
});

client.on("message", (receivedTopic, payload) => {
  gotMessage = true;
  console.log(`${receivedTopic} => ${payload.toString("utf8")}`);
});

client.on("error", (err) => {
  console.error(`mqtt error: ${err.message}`);
  process.exit(2);
});
