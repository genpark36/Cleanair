import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.5/firebase-app.js";
import {
  collection,
  doc,
  getDoc,
  getFirestore,
  limit,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
} from "https://www.gstatic.com/firebasejs/10.12.5/firebase-firestore.js";
import {
  getAuth,
  GoogleAuthProvider,
  onAuthStateChanged,
  signInWithPopup,
  signOut,
} from "https://www.gstatic.com/firebasejs/10.12.5/firebase-auth.js";

const config = window.CLEANAIR_FIREBASE_CONFIG;
const options = window.CLEANAIR_DASHBOARD_OPTIONS || {};

const state = {
  firebaseReady: false,
  db: null,
  auth: null,
  user: null,
  profile: null,
  authorized: false,
  subscribed: false,
  sensorLinks: [],
  plugLinks: [],
  sensors: [],
  alerts: [],
  dismissedAlertIds: new Set(),
  incidents: [],
  plugs: [],
  plugTraces: {},
  plugTraceFetchedAt: {},
  plugTraceLoading: {},
  kakaoMap: null,
  kakaoOverlays: [],
  kakaoInfoOverlay: null,
  kakaoSdkLoading: null,
  browserPosition: null,
  browserPositionPromise: null,
  mapPopupSensorId: null,
  mapPopupPlugId: null,
  selectedSensorId: null,
  view: "overview",
  lastError: "",
  sensorLinksUnsubscribe: null,
  plugLinksUnsubscribe: null,
  sensorsUnsubscribe: null,
  alertsUnsubscribe: null,
  incidentsUnsubscribe: null,
};

const els = {
  app: document.querySelector("#app"),
  authGate: document.querySelector("#authGate"),
  authMessage: document.querySelector("#authMessage"),
  setupWarning: document.querySelector("#setupWarning"),
  statusStrip: document.querySelector("#statusStrip"),
  criticalBanner: document.querySelector("#criticalBanner"),
  summaryGrid: document.querySelector("#summaryGrid"),
  alertSummary: document.querySelector("#alertSummary"),
  facilityCards: document.querySelector("#facilityCards"),
  mapBoard: document.querySelector("#mapBoard"),
  facilityList: document.querySelector("#facilityList"),
  facilityDetail: document.querySelector("#facilityDetail"),
  eventTimeline: document.querySelector("#eventTimeline"),
  deviceGrid: document.querySelector("#deviceGrid"),
  settingsPanel: document.querySelector("#settingsPanel"),
  modal: document.querySelector("#alertModal"),
  search: document.querySelector("#facilitySearch"),
  sidebarFoot: document.querySelector(".sidebar-foot"),
};

window.CLEANAIR_DASHBOARD_BOOTED = true;
if (els.authMessage) {
  els.authMessage.textContent = "Firebase Auth 상태를 확인하는 중입니다.";
}

document.addEventListener("click", (event) => {
  const viewTarget = event.target.closest("[data-view]");
  if (viewTarget) {
    setView(viewTarget.dataset.view);
    return;
  }

  const action = event.target.closest("[data-action]");
  if (!action) return;

  const { action: actionName, plugId, command, sensorId } = action.dataset;
  if (actionName === "sign-in-google") signInGoogle();
  if (actionName === "sign-out") signOutUser();
  if (actionName === "open-profile") openProfileModal();
  if (actionName === "save-profile") saveProfile();
  if (actionName === "refresh") refreshPlugs();
  if (actionName === "open-emergency") openEmergencyModal();
  if (actionName === "end-incident") endIncident(action.dataset.incidentId);
  if (actionName === "close-modal") closeModal();
  if (actionName === "close-map-popup") closeMapPopup();
  if (actionName === "copy-situation") copySituationSummary();
  if (actionName === "select-sensor") selectSensor(sensorId);
  if (actionName === "select-map-sensor") selectMapSensor(sensorId);
  if (actionName === "select-map-plug") selectMapPlug(plugId);
  if (actionName === "command-plug") commandPlug(plugId, command);
  if (actionName === "refresh-plug-trace") refreshPlugTrace(plugId, { force: true });
  if (actionName === "export-plug-csv") exportPlugTraceCsv(plugId);
});

els.modal?.addEventListener("click", (event) => {
  if (event.target === els.modal) {
    closeModal();
  }
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !els.modal?.classList.contains("hidden")) {
    closeModal();
  }
});

els.search?.addEventListener("input", renderFacilities);

if (config?.projectId && config?.apiKey) {
  bootFirebase();
} else {
  els.authMessage.textContent = "firebase-config.js 설정이 필요합니다.";
  els.setupWarning.classList.remove("hidden");
  unlockDashboardForSetup();
  render();
}

function bootFirebase() {
  try {
    const app = initializeApp(config);
    state.db = getFirestore(app);
    state.auth = getAuth(app);
    state.firebaseReady = true;
    els.setupWarning.classList.add("hidden");
    let authResolved = false;
    const authTimer = window.setTimeout(() => {
      if (authResolved || state.authorized) return;
      els.authMessage.textContent =
        "Firebase Auth 응답이 지연되고 있습니다. 승인 도메인, Google 로그인 제공업체, 네트워크 차단 여부를 확인해 주세요.";
    }, 6000);
    onAuthStateChanged(state.auth, async (user) => {
      try {
        authResolved = true;
        window.clearTimeout(authTimer);
        state.user = user;
        if (user) {
          loadDismissedAlerts();
        } else {
          state.dismissedAlertIds = new Set();
        }
        state.authorized = isAuthorized(user);
        renderAuthGate();
        if (state.authorized && !state.subscribed) {
          await loadUserProfile();
          startLiveData();
        } else if (state.authorized) {
          await loadUserProfile();
        } else {
          state.profile = null;
        }
        render();
      } catch (error) {
        showAuthError("로그인 후 대시보드 준비 실패", error);
      }
    });
  } catch (error) {
    state.lastError = formatError(error);
    els.setupWarning.classList.remove("hidden");
    els.authMessage.textContent = state.lastError;
    setSyncText("Firebase 연결 실패");
    render();
  }
}

function startLiveData() {
  state.subscribed = true;
  subscribeAssetLinks();
  subscribeIncidents();
  refreshPlugs();
  setInterval(refreshPlugs, 15000);
  setSyncText("실시간 동기화 중");
}

async function signInGoogle() {
  if (!state.auth) {
    els.authMessage.textContent = "Firebase Auth 설정을 먼저 확인해 주세요.";
    return;
  }
  try {
    els.authMessage.textContent = "로그인 창을 여는 중입니다.";
    state.lastError = "";
    await signInWithPopup(state.auth, new GoogleAuthProvider());
  } catch (error) {
    showAuthError("Google 로그인 실패", error);
  }
}

async function signOutUser() {
  if (!state.auth) return;
  await signOut(state.auth);
}

function isAuthorized(user) {
  if (options.requireAuth === false) return true;
  if (!user) return false;
  if (options.restrictToAdminEmails !== true) return true;
  const admins = Array.isArray(options.adminEmails)
    ? options.adminEmails.map((email) => String(email).trim().toLowerCase()).filter(Boolean)
    : [];
  if (!admins.length) return true;
  return admins.includes(String(user.email || "").toLowerCase());
}

function renderAuthGate() {
  if (state.authorized) {
    els.authGate.classList.add("hidden");
    els.app.classList.remove("locked");
    const label = initials(state.profile?.displayName || state.user?.email || "CA");
    document.querySelector(".profile-button").textContent = label;
    return;
  }

  els.authGate.classList.remove("hidden");
  els.app.classList.add("locked");
  els.authMessage.textContent = state.user
    ? `로그인은 되었지만 대시보드 접근이 차단되었습니다. email=${state.user.email || "unknown"}, restrictToAdminEmails=${options.restrictToAdminEmails === true}`
    : "Google 계정으로 로그인해 주세요.";
}

async function loadUserProfile() {
  if (!state.db || !state.user) return;
  const ref = doc(state.db, "user_profiles", state.user.uid);
  const baseProfile = {
    uid: state.user.uid,
    email: state.user.email || "",
    displayName: state.user.displayName || "",
    photoURL: state.user.photoURL || "",
    role: "",
    organizationName: "",
    phone: "",
    defaultFacilityId: "",
    notifyCritical: true,
  };
  try {
    const snapshot = await getDoc(ref);
    if (snapshot.exists()) {
      state.profile = { ...baseProfile, ...snapshot.data() };
      await setDoc(ref, {
        email: baseProfile.email,
        photoURL: baseProfile.photoURL,
        lastLoginAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }, { merge: true });
    } else {
      state.profile = baseProfile;
      await setDoc(ref, {
        ...baseProfile,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
        lastLoginAt: serverTimestamp(),
      }, { merge: true });
    }
  } catch (error) {
    state.lastError = `프로필 동기화 실패: ${formatError(error)}`;
    if (els.authMessage && !els.authGate.classList.contains("hidden")) {
      els.authMessage.textContent = state.lastError;
    }
  }
}

function unlockDashboardForSetup() {
  els.authGate.classList.add("hidden");
  els.app.classList.remove("locked");
}

function subscribeAssetLinks() {
  if (!state.db || !state.user) return;

  state.sensorLinksUnsubscribe?.();
  state.sensorLinksUnsubscribe = onSnapshot(
    collection(state.db, "user_profiles", state.user.uid, "sensor_links"),
    (snapshot) => {
      state.sensorLinks = snapshot.docs.map((item) => normalizeSensorLink(item.id, item.data()));
      subscribeSensors();
      subscribeAlerts();
      render();
    },
    setError
  );

  state.plugLinksUnsubscribe?.();
  state.plugLinksUnsubscribe = onSnapshot(
    collection(state.db, "user_profiles", state.user.uid, "plug_links"),
    (snapshot) => {
      state.plugLinks = snapshot.docs.map((item) => normalizePlugLink(item.id, item.data()));
      refreshPlugs();
      render();
    },
    setError
  );
}

function subscribeSensors() {
  const allowedSensorIds = linkedSensorIds();
  if (!allowedSensorIds.size) {
    state.sensors = [];
    state.selectedSensorId = null;
    state.sensorsUnsubscribe?.();
    state.sensorsUnsubscribe = null;
    render();
    return;
  }

  state.sensorsUnsubscribe?.();
  state.sensorsUnsubscribe = onSnapshot(collection(state.db, "sensors"), (snapshot) => {
    const links = sensorLinkMap();
    state.sensors = snapshot.docs
      .map((doc) => mergeSensorLink(normalizeSensor(doc.id, doc.data()), links.get(doc.id)))
      .filter((sensor) => allowedSensorIds.has(sensor.id))
      .filter(isVisibleSensor)
      .sort((a, b) => toMillis(b.updatedAt) - toMillis(a.updatedAt));
    if (!state.sensors.some((sensor) => sensor.id === state.selectedSensorId)) {
      state.selectedSensorId = null;
    }
    if (!state.selectedSensorId && state.sensors.length) {
      state.selectedSensorId = state.sensors[0].id;
    }
    render();
  }, setError);
}

function subscribeAlerts() {
  const alertsQuery = query(collection(state.db, "alerts"), orderBy("createdAt", "desc"), limit(40));
  state.alertsUnsubscribe?.();
  state.alertsUnsubscribe = onSnapshot(alertsQuery, (snapshot) => {
    state.alerts = snapshot.docs
      .map((doc) => normalizeAlert(doc.id, doc.data()))
      .filter((alert) => isVisibleAlert(alert) && alertBelongsToUser(alert) && !isDismissedAlert(alert));
    render();
  }, setError);
}

function subscribeIncidents() {
  if (!state.db || !state.user) return;
  state.incidentsUnsubscribe?.();
  state.incidentsUnsubscribe = onSnapshot(
    collection(state.db, "user_profiles", state.user.uid, "incidents"),
    (snapshot) => {
      state.incidents = snapshot.docs
        .map((item) => normalizeIncident(item.id, item.data()))
        .filter((incident) => !incident.archived)
        .sort((a, b) => toMillis(b.createdAt || b.updatedAt) - toMillis(a.createdAt || a.updatedAt))
        .slice(0, 50);
      setSyncText(activeIncidents().length ? "상황 수신됨" : "실시간 동기화 중");
      render();
    },
    setError
  );
}

async function refreshPlugs() {
  if (!config?.projectId || !state.authorized) return;
  const linked = state.plugLinks.map(normalizePlug).filter(isVisiblePlug);
  const allowedPlugIds = linkedPlugIds();
  if (!allowedPlugIds.size) {
    state.plugs = [];
    render();
    return;
  }
  try {
    const response = await callFunction("listPlugs", { limit: 100 });
    const remote = (response.plugs || [])
      .map(normalizePlug)
      .filter((plug) => allowedPlugIds.has(plug.plugId))
      .filter(isVisiblePlug)
    const byId = new Map();
    for (const plug of linked) byId.set(plug.plugId, plug);
    for (const plug of remote) byId.set(plug.plugId, { ...(byId.get(plug.plugId) || {}), ...plug });
    state.plugs = [...byId.values()]
      .sort((a, b) => toMillis(b.lastSeen || b.updatedAt) - toMillis(a.lastSeen || a.updatedAt));
    setSyncText("실시간 동기화 중");
    render();
    refreshPlugTracesFor(state.plugs.slice(0, 8));
  } catch (error) {
    state.lastError = error?.message || String(error);
    state.plugs = linked;
    setSyncText("플러그 동기화 실패");
    render();
  }
}

async function commandPlug(plugId, command) {
  if (!plugId || !command) return;
  const card = document.querySelector(`[data-plug-card="${cssEscape(plugId)}"]`);
  card?.classList.add("pending");
  try {
    await callFunction("commandPlug", {
      plugId,
      command,
      mode: "manual",
      actor: "web-dashboard",
      reason: "dashboard_manual_control",
      transportHint: "MQTT",
      manualOverrideSeconds: 300,
    });
    await refreshPlugs();
    await refreshPlugTrace(plugId, { force: true });
  } catch (error) {
    state.lastError = `플러그 제어 실패: ${error?.message || error}`;
    renderSettings();
  } finally {
    card?.classList.remove("pending");
  }
}

async function refreshPlugTracesFor(plugs, { force = false } = {}) {
  if (!state.authorized) return;
  const plugIds = [...new Set(plugs
    .map((plug) => typeof plug === "string" ? plug : plug?.plugId)
    .filter(Boolean))];
  const stalePlugIds = plugIds.filter((plugId) => {
    if (force) return true;
    const fetchedAt = state.plugTraceFetchedAt[plugId] || 0;
    return Date.now() - fetchedAt > 30000;
  });
  if (!stalePlugIds.length) return;

  const results = await Promise.all(stalePlugIds.map(async (plugId) => {
    try {
      const response = await callFunction("getPlugControlTrace", { plugId, limit: 6 });
      return { plugId, traces: response.traces || [] };
    } catch (error) {
      return { plugId, error };
    }
  }));

  let changed = false;
  for (const result of results) {
    if (result.error) {
      state.lastError = `플러그 이력 조회 실패: ${result.error?.message || result.error}`;
      continue;
    }
    state.plugTraces[result.plugId] = result.traces.map(normalizePlugTrace);
    state.plugTraceFetchedAt[result.plugId] = Date.now();
    changed = true;
  }
  if (changed) render();
}

async function refreshPlugTrace(plugId, { force = false } = {}) {
  if (!plugId) return;
  state.plugTraceLoading[plugId] = true;
  renderDevices();
  try {
    await refreshPlugTracesFor([plugId], { force });
  } finally {
    delete state.plugTraceLoading[plugId];
    render();
  }
}

async function callFunction(endpoint, body) {
  const base = options.functionsBaseUrl?.trim()
    || `https://${options.defaultRegion || "us-central1"}-${config.projectId}.cloudfunctions.net`;
  const headers = { "Content-Type": "application/json" };
  if (options.deviceApiKey?.trim()) {
    headers["X-API-Key"] = options.deviceApiKey.trim();
  }
  const response = await fetch(`${base}/${endpoint}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body || {}),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.ok === false) {
    throw new Error(payload.error || `${endpoint} failed`);
  }
  return payload;
}

function render() {
  renderStatus();
  renderCriticalBanner();
  renderSummary();
  renderAlerts();
  renderFacilities();
  renderMap();
  renderEvents();
  renderDevices();
  renderSettings();
}

function setView(view) {
  state.view = view;
  document.querySelectorAll("[data-view]").forEach((button) => {
    button.classList.toggle("active", button.dataset.view === view);
  });
  document.querySelectorAll("[data-view-panel]").forEach((panel) => {
    panel.classList.toggle("active", panel.dataset.viewPanel === view);
  });
  if (view === "map") {
    window.setTimeout(() => state.kakaoMap?.relayout?.(), 0);
  }
}

function renderStatus() {
  const counts = getStatusCounts();
  const activeCount = activeIncidents().length;
  els.statusStrip.innerHTML = `
    <span class="status-dot">정상 ${counts.normal}</span>
    <span class="status-dot warn">주의 ${counts.warning}</span>
    <span class="status-dot danger">화재 의심 ${counts.danger}</span>
    ${activeCount ? `<span class="status-dot danger">상황 ${activeCount}</span>` : ""}
    <span class="status-dot offline">오프라인 ${counts.offline}</span>
  `;
}

function renderCriticalBanner() {
  const critical = getActiveIncident() || getCriticalAlert();
  if (!critical) {
    els.criticalBanner.classList.add("hidden");
    els.criticalBanner.innerHTML = "";
    return;
  }

  els.criticalBanner.classList.remove("hidden");
  els.criticalBanner.innerHTML = `
    <div>
      <div class="card-sub">CRITICAL ALERT</div>
      <strong>${escapeHtml(critical.title)}</strong>
      <div>${escapeHtml(critical.location || "위치 확인 필요")} · ${formatTime(critical.createdAt)}</div>
    </div>
    <div class="critical-actions">
      <button class="soft-button" data-action="open-emergency">상세 확인</button>
      ${critical.id ? `<button class="white-button" data-action="end-incident" data-incident-id="${escapeAttr(critical.id)}">상황 종료</button>` : ""}
    </div>
  `;
}

function renderSummary() {
  const counts = getStatusCounts();
  const activeCount = activeIncidents().length;
  els.summaryGrid.innerHTML = [
    summaryCard("총 모니터링 시설", state.sensors.length, "등록 센서 기준"),
    summaryCard("정상 가동", counts.normal, "안정적인 공간"),
    summaryCard("주의 필요", counts.warning, "공기질 저하 확인"),
    summaryCard(activeCount ? "상황 확인" : "화재 의심", activeCount || counts.danger, activeCount ? "대시보드 전송됨" : "즉시 확인 필요"),
  ].join("");
}

function summaryCard(label, value, sub) {
  return `
    <article class="summary-card">
      <span class="card-sub">${label}</span>
      <strong>${value}</strong>
      <div class="trend">${sub}</div>
    </article>
  `;
}

function renderAlerts() {
  const items = [
    ...activeIncidents().slice(0, 3).map((incident) => ({
      ...incident,
      isIncident: true,
      isCritical: incident.isCritical,
    })),
    ...state.alerts,
  ].slice(0, 4);
  if (!items.length) {
    els.alertSummary.innerHTML = emptyBlock("최근 경고 기록이 없습니다.");
    return;
  }

  els.alertSummary.innerHTML = items.map((alert) => `
    <article class="alert-item ${alert.isCritical ? "critical" : "warning"}">
      <strong>${escapeHtml(alert.title)}</strong>
      <div>${escapeHtml(alert.message || alert.location || "")}</div>
      ${alert.isIncident ? `<button class="link-button" data-action="open-emergency">상황 확인</button>` : ""}
      <small>${formatTime(alert.createdAt)}</small>
    </article>
  `).join("");
}

function renderFacilities() {
  const search = (els.search?.value || "").trim().toLowerCase();
  const sensors = state.sensors.filter((sensor) => {
    if (!search) return true;
    return `${sensor.name} ${sensor.location} ${sensor.id}`.toLowerCase().includes(search);
  });

  els.facilityCards.innerHTML = sensors.slice(0, 4).map(facilityCard).join("")
    || emptyBlock("등록된 센서가 없습니다.");

  els.facilityList.innerHTML = sensors.map((sensor) => `
    <button class="facility-row ${sensor.id === state.selectedSensorId ? "active" : ""}"
      data-action="select-sensor" data-sensor-id="${escapeAttr(sensor.id)}">
      <strong>${escapeHtml(sensor.name)}</strong>
      <div class="card-sub">${escapeHtml(sensor.location || sensor.id)}</div>
      <span class="pill ${statusPillClass(sensor.status)}">${statusLabel(sensor.status)}</span>
    </button>
  `).join("") || emptyBlock("검색 결과가 없습니다.");

  const selected = state.sensors.find((sensor) => sensor.id === state.selectedSensorId) || sensors[0] || state.sensors[0];
  els.facilityDetail.innerHTML = selected ? facilityDetail(selected) : emptyBlock("시설을 선택하세요.");
}

function facilityCard(sensor) {
  return `
    <button class="facility-card ${sensor.status}" data-action="select-sensor" data-sensor-id="${escapeAttr(sensor.id)}">
      <div class="section-title-row">
        <div>
          <h3>${escapeHtml(sensor.name)}</h3>
          <div class="card-sub">${escapeHtml(sensor.location || "위치 미등록")}</div>
        </div>
        <span class="pill ${statusPillClass(sensor.status)}">${statusLabel(sensor.status)}</span>
      </div>
      ${metricGrid(sensor)}
      <div class="card-foot">
        <div class="trend">${formatTime(sensor.updatedAt)} 업데이트</div>
        <span>상세 보기 →</span>
      </div>
    </button>
  `;
}

function facilityDetail(sensor) {
  const linkedPlugs = linkedPlugsForSensor(sensor);
  const recentAlerts = alertsForSensor(sensor).slice(0, 4);
  return `
    <div class="section-title-row">
      <div>
        <h2>${escapeHtml(sensor.name)} 제어 패널</h2>
        <div class="card-sub">마지막 업데이트: ${formatTime(sensor.updatedAt)}</div>
      </div>
      <span class="pill ${statusPillClass(sensor.status)}">${statusLabel(sensor.status)}</span>
    </div>
    <div class="facility-context">
      <strong>${escapeHtml(sensorStatusSentence(sensor))}</strong>
      <span>${escapeHtml(sensor.location || sensor.id)}</span>
    </div>
    ${metricGrid(sensor)}
    <h2 style="margin-top: 30px">최근 알림</h2>
    <div class="stack">
      ${recentAlerts.map((alert) => `
        <article class="alert-item ${alert.isCritical ? "critical" : "warning"}">
          <strong>${escapeHtml(alert.title)}</strong>
          <div>${escapeHtml(alert.message || alert.location || "상세 내용 없음")}</div>
          <small>${formatTime(alert.createdAt)}</small>
        </article>
      `).join("") || emptyBlock("이 센서와 연결된 최근 알림이 없습니다.")}
    </div>
    <h2 style="margin-top: 30px">연결 장비</h2>
    <div class="device-grid">
      ${linkedPlugs.map(deviceCard).join("") || emptyBlock("연결된 플러그가 없습니다.")}
    </div>
  `;
}

function metricGrid(sensor) {
  const metrics = [
    ["PM2.5", value(sensor.pm25, "ug/m3")],
    ["CO2", value(sensor.co2, "ppm")],
    ["CO", value(sensor.co, "ppm")],
    ["TVOC", value(sensor.tvoc, "index")],
    ["NOx", value(sensor.nox, "index")],
    ["온도/습도", `${value(sensor.temperature, "°C")} / ${value(sensor.humidity, "%")}`],
  ];

  return `
    <div class="metric-grid">
      ${metrics.map(([label, metricValue]) => `
        <div class="metric">
          <span>${label}</span>
          <strong>${metricValue}</strong>
        </div>
      `).join("")}
    </div>
  `;
}

function linkedPlugsForSensor(sensor) {
  const strict = state.plugs.filter((plug) =>
    sameId(plug.sensorId, sensor.id)
    || sameId(plug.stationId, sensor.id)
    || sameText(plug.location, sensor.name)
    || sameText(plug.location, sensor.location)
  );
  if (strict.length || state.sensors.length !== 1) return strict;
  return state.plugs.filter((plug) => !plug.sensorId && !plug.stationId).slice(0, 4);
}

function alertsForSensor(sensor) {
  return state.alerts.filter((alert) =>
    sameId(alert.sensorId, sensor.id)
    || sameText(alert.location, sensor.name)
    || sameText(alert.location, sensor.location)
  );
}

function sensorStatusSentence(sensor) {
  if (sensor.status === "danger") return "화재 의심 또는 위급 알림을 확인해야 합니다.";
  if (sensor.status === "warning") return "공기질이 평소보다 나빠졌습니다.";
  if (sensor.status === "offline") return "센서 연결 상태를 확인해야 합니다.";
  return "현재 공기질과 방재 상태가 안정적입니다.";
}

function selectedSensor() {
  return state.sensors.find((sensor) => sensor.id === state.selectedSensorId)
    || state.sensors.find((sensor) => sensor.status === "danger")
    || state.sensors[0]
    || null;
}

function renderMap() {
  const points = state.sensors.length ? state.sensors : [];
  const selected = selectedSensor();
  const activeIncident = getActiveIncident();
  const sensorLayer = points.map((sensor, index) => {
    const x = sensor.lng ? clamp(((sensor.lng - 124) / 8) * 100, 8, 92) : 22 + (index * 17) % 64;
    const y = sensor.lat ? clamp((1 - ((sensor.lat - 33) / 6)) * 100, 10, 88) : 22 + (index * 23) % 64;
    return `
      <span class="map-label" style="left:${x}%;top:${y}%">${escapeHtml(sensor.name)}</span>
      <button class="map-point ${sensor.status}" style="left:${x}%;top:${y}%"
        data-action="select-map-sensor" data-sensor-id="${escapeAttr(sensor.id)}">${index + 1}</button>
    `;
  }).join("");
  const plugLayer = state.plugs.map((plug, index) => {
    const sensor = state.sensors.find((item) => sameId(item.id, plug.sensorId) || sameId(item.id, plug.stationId));
    const x = sensor?.lng ? clamp(((sensor.lng - 124) / 8) * 100 + 2, 10, 94) : 72 + (index * 7) % 16;
    const y = sensor?.lat ? clamp((1 - ((sensor.lat - 33) / 6)) * 100 + 4, 12, 90) : 58 + (index * 11) % 22;
    return `
      <button class="map-plug ${plug.actualState === "ON" ? "on" : ""}" style="left:${x}%;top:${y}%"
        data-action="select-map-plug" data-plug-id="${escapeAttr(plug.plugId)}"
        title="${escapeAttr(plug.displayName)}">${plug.actualState === "ON" ? "ON" : "OFF"}</button>
    `;
  }).join("");
  ensureMapBoardShell();
  const fallback = els.mapBoard.querySelector(".map-fallback-layer");
  if (fallback) {
    fallback.innerHTML = `
      ${sensorLayer || `<div class="muted" style="padding:32px">지도에 표시할 센서 위치가 없습니다.</div>`}
      ${plugLayer}
    `;
  }
  renderKakaoSituationMap(selected);
}

function ensureMapBoardShell() {
  if (els.mapBoard.querySelector("#kakaoSituationMap")) return;
  els.mapBoard.innerHTML = `
    <div id="kakaoSituationMap" class="kakao-situation-map">
      <div class="map-fallback-layer"></div>
    </div>
    <div class="map-popup-layer"></div>
  `;
}

function mapSensorPopupHtml(selected, activeIncident) {
  const linkedPlugCount = selected ? linkedPlugsForSensor(selected).length : 0;
  return `
    <div class="kakao-popup-head">
      <span class="pill ${statusPillClass(selected?.status || "normal")}">${statusLabel(selected?.status || "normal")}</span>
      <button class="kakao-popup-close" type="button" data-action="close-map-popup" aria-label="팝업 닫기">×</button>
    </div>
    <h2>${escapeHtml(activeIncident?.title || selected?.name || "등록된 장소 없음")}</h2>
    <p>${escapeHtml(activeIncident?.message || selected?.location || "위치 정보 없음")}</p>
    ${selected ? metricGrid(selected) : ""}
    <div class="map-sensor-note">연결 장비 ${linkedPlugCount}개</div>
    <div class="map-card-actions">
      ${activeIncident ? `<button class="danger-button" data-action="open-emergency">상황 확인</button>` : ""}
      ${activeIncident ? `<button class="soft-button" data-action="end-incident" data-incident-id="${escapeAttr(activeIncident.id)}">상황 종료</button>` : ""}
      ${selected ? `<button class="soft-button" data-action="select-sensor" data-sensor-id="${escapeAttr(selected.id)}">시설 보기</button>` : ""}
    </div>
  `;
}

function mapPlugPopupHtml(plug) {
  const isOn = plug?.actualState === "ON";
  return `
    <div class="kakao-popup-head">
      <span class="pill ${isOn ? "blue" : ""}">${isOn ? "ON" : "OFF"}</span>
      <button class="kakao-popup-close" type="button" data-action="close-map-popup" aria-label="팝업 닫기">×</button>
    </div>
    <h2>${escapeHtml(plug?.displayName || plug?.plugId || "등록된 플러그")}</h2>
    <p>${escapeHtml(plug?.location || plug?.sensorId || "연결 위치 미등록")}</p>
    ${mapPlugControl(plug)}
  `;
}

function mapPlugControl(plug) {
  const isOn = plug.actualState === "ON";
  return `
    <article class="map-plug-control" data-plug-card="${escapeAttr(plug.plugId)}">
      <div>
        <strong>${escapeHtml(plug.displayName || plug.plugId)}</strong>
        <span>${escapeHtml(plug.location || plug.sensorId || "연결 위치 미등록")}</span>
        <small>전압 ${value(plug.voltage, "V")} · 전류 ${value(plug.current, "A")} · 전력 ${value(plug.power, "W")}</small>
      </div>
      <div class="map-plug-buttons">
        <button class="device-action ${isOn ? "" : "primary"}" data-action="command-plug" data-plug-id="${escapeAttr(plug.plugId)}" data-command="ON">ON</button>
        <button class="device-action ${isOn ? "primary" : ""}" data-action="command-plug" data-plug-id="${escapeAttr(plug.plugId)}" data-command="OFF">OFF</button>
        <button class="device-action ghost" data-action="export-plug-csv" data-plug-id="${escapeAttr(plug.plugId)}">CSV</button>
      </div>
    </article>
  `;
}

async function mapInitialCenterSource(selected) {
  if (!state.kakaoMap) {
    const browserPosition = await getBrowserPosition();
    if (browserPosition) {
      return { ...browserPosition, kind: "browser" };
    }
  }
  if (sensorHasPosition(selected)) {
    return { lat: Number(selected.lat), lng: Number(selected.lng), kind: "sensor" };
  }
  const sensor = state.sensors.find(sensorHasPosition);
  if (sensor) {
    return { lat: Number(sensor.lat), lng: Number(sensor.lng), kind: "sensor" };
  }
  return { lat: 37.5665, lng: 126.9780, kind: "default" };
}

function getBrowserPosition() {
  if (state.browserPosition) return Promise.resolve(state.browserPosition);
  if (state.browserPositionPromise) return state.browserPositionPromise;
  if (!navigator.geolocation) return Promise.resolve(null);

  state.browserPositionPromise = new Promise((resolve) => {
    navigator.geolocation.getCurrentPosition(
      (position) => {
        const coords = {
          lat: position.coords.latitude,
          lng: position.coords.longitude,
        };
        state.browserPosition = coords;
        resolve(coords);
      },
      () => resolve(null),
      {
        enableHighAccuracy: false,
        maximumAge: 5 * 60 * 1000,
        timeout: 2500,
      }
    );
  });
  return state.browserPositionPromise;
}

async function renderKakaoSituationMap(selected) {
  const container = document.querySelector("#kakaoSituationMap");
  if (!container) return;
  const key = options.kakaoJsApiKey || "";
  if (!key) {
    container.classList.add("map-fallback");
    return;
  }

  try {
    await loadKakaoMapSdk(key);
    const kakao = window.kakao;
    if (!kakao?.maps) throw new Error("Kakao Maps SDK가 준비되지 않았습니다.");
    const centerSource = await mapInitialCenterSource(selected);
    const center = new kakao.maps.LatLng(Number(centerSource.lat), Number(centerSource.lng));
    const map = state.kakaoMap || new kakao.maps.Map(container, {
      center,
      level: centerSource.kind === "browser" ? 5 : state.sensors.length > 1 ? 7 : 4,
    });
    state.kakaoMap = map;
    map.relayout?.();
    clearKakaoOverlays();

    if (state.browserPosition) {
      const myPosition = new kakao.maps.LatLng(
        Number(state.browserPosition.lat),
        Number(state.browserPosition.lng)
      );
      const myChip = document.createElement("span");
      myChip.className = "kakao-user-position";
      myChip.textContent = "현재 위치";
      state.kakaoOverlays.push(new kakao.maps.CustomOverlay({
        map,
        position: myPosition,
        yAnchor: 1.4,
        zIndex: 45,
        content: myChip,
      }));
    }

    state.sensors.filter(sensorHasPosition).forEach((sensor) => {
      const position = new kakao.maps.LatLng(Number(sensor.lat), Number(sensor.lng));
      const marker = new kakao.maps.Marker({ map, position, title: sensor.name });
      kakao.maps.event.addListener(marker, "click", () => {
        selectMapSensor(sensor.id, { pan: true });
      });
      state.kakaoOverlays.push(marker);
      const chip = document.createElement("button");
      chip.className = `kakao-map-chip ${sensor.status}`;
      chip.textContent = sensor.name;
      chip.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        selectMapSensor(sensor.id, { pan: true });
      });
      const overlay = new kakao.maps.CustomOverlay({
        map,
        position,
        yAnchor: 1.55,
        zIndex: 40,
        content: chip,
      });
      state.kakaoOverlays.push(overlay);
    });

    state.plugs.forEach((plug, index) => {
      const linked = state.sensors.find((sensor) =>
        sensorHasPosition(sensor)
        && (sameId(sensor.id, plug.sensorId) || sameId(sensor.id, plug.stationId))
      );
      if (!linked) return;
      const position = new kakao.maps.LatLng(
        Number(linked.lat) + 0.00035 + index * 0.00008,
        Number(linked.lng) + 0.00035 + index * 0.00008
      );
      const plugChip = document.createElement("button");
      plugChip.className = `kakao-plug-chip ${plug.actualState === "ON" ? "on" : ""}`;
      plugChip.textContent = `${plug.displayName || "플러그"} · ${plug.actualState || "확인"}`;
      plugChip.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        selectMapPlug(plug.plugId, { pan: true });
      });
      const overlay = new kakao.maps.CustomOverlay({
        map,
        position,
        zIndex: 41,
        content: plugChip,
      });
      state.kakaoOverlays.push(overlay);
    });
    const popupSensor = state.mapPopupSensorId
      ? state.sensors.find((sensor) => sameId(sensor.id, state.mapPopupSensorId))
      : null;
    const popupPlug = state.mapPopupPlugId
      ? state.plugs.find((plug) => sameId(plug.plugId, state.mapPopupPlugId))
      : null;
    if (popupSensor && sensorHasPosition(popupSensor)) {
      openKakaoMapPopup(popupSensor, { pan: false });
    } else if (popupPlug) {
      openKakaoPlugPopup(popupPlug, { pan: false });
    }
    container.classList.remove("map-fallback");
  } catch (error) {
    state.lastError = `Kakao 지도 표시 실패: ${error?.message || error}`;
    container.classList.add("map-fallback");
    const fallback = container.querySelector(".map-fallback-layer");
    if (fallback && !fallback.querySelector(".map-error")) {
      fallback.insertAdjacentHTML(
        "afterbegin",
        `<div class="map-error">Kakao 지도 도메인 승인이 필요합니다. 현재는 도식 상황판으로 표시합니다.</div>`
      );
    }
  }
}

function loadKakaoMapSdk(key) {
  if (window.kakao?.maps) {
    return new Promise((resolve) => window.kakao.maps.load(resolve));
  }
  if (state.kakaoSdkLoading) return state.kakaoSdkLoading;
  state.kakaoSdkLoading = new Promise((resolve, reject) => {
    const finish = () => {
      if (!window.kakao?.maps) {
        reject(new Error("Kakao Maps SDK 로드 실패"));
        return;
      }
      window.kakao.maps.load(resolve);
    };
    const script = document.createElement("script");
    script.src = `https://dapi.kakao.com/v2/maps/sdk.js?appkey=${encodeURIComponent(key)}&autoload=false&libraries=services`;
    script.async = true;
    script.onload = finish;
    script.onerror = () => reject(new Error("Kakao Maps SDK 스크립트를 불러오지 못했습니다."));
    document.head.appendChild(script);
  });
  return state.kakaoSdkLoading;
}

function clearKakaoOverlays() {
  for (const overlay of state.kakaoOverlays) {
    overlay.setMap?.(null);
  }
  state.kakaoOverlays = [];
  closeKakaoInfoOverlay();
}

function closeKakaoInfoOverlay() {
  state.kakaoInfoOverlay?.setMap?.(null);
  state.kakaoInfoOverlay = null;
}

function closeMapPopup() {
  state.mapPopupSensorId = null;
  state.mapPopupPlugId = null;
  closeKakaoInfoOverlay();
  const layer = els.mapBoard?.querySelector(".map-popup-layer");
  if (layer) layer.innerHTML = "";
}

function mapPlugPosition(plug) {
  const linked = state.sensors.find((sensor) =>
    sensorHasPosition(sensor)
    && (sameId(sensor.id, plug?.sensorId) || sameId(sensor.id, plug?.stationId))
  );
  if (!linked) return null;
  const index = state.plugs.findIndex((item) => sameId(item.plugId, plug.plugId));
  return {
    lat: Number(linked.lat) + 0.00035 + Math.max(index, 0) * 0.00008,
    lng: Number(linked.lng) + 0.00035 + Math.max(index, 0) * 0.00008,
  };
}

function openKakaoMapPopup(sensor, { pan = false } = {}) {
  if (!state.kakaoMap || !window.kakao?.maps || !sensorHasPosition(sensor)) {
    openFallbackMapPopup(sensor);
    return;
  }
  const kakao = window.kakao;
  const position = new kakao.maps.LatLng(Number(sensor.lat), Number(sensor.lng));
  closeKakaoInfoOverlay();
  const popup = document.createElement("article");
  popup.className = "kakao-info-popup";
  popup.innerHTML = mapSensorPopupHtml(sensor, getActiveIncident());
  popup.querySelector("[data-action='close-map-popup']")?.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();
    closeMapPopup();
  });
  state.kakaoInfoOverlay = new kakao.maps.CustomOverlay({
    map: state.kakaoMap,
    position,
    xAnchor: 0.5,
    yAnchor: 1.12,
    zIndex: 80,
    content: popup,
  });
  if (pan) state.kakaoMap.panTo(position);
}

function openKakaoPlugPopup(plug, { pan = false } = {}) {
  const coords = mapPlugPosition(plug);
  if (!state.kakaoMap || !window.kakao?.maps || !coords) {
    openFallbackPlugPopup(plug);
    return;
  }
  const kakao = window.kakao;
  const position = new kakao.maps.LatLng(Number(coords.lat), Number(coords.lng));
  closeKakaoInfoOverlay();
  const popup = document.createElement("article");
  popup.className = "kakao-info-popup plug-popup";
  popup.innerHTML = mapPlugPopupHtml(plug);
  popup.querySelector("[data-action='close-map-popup']")?.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();
    closeMapPopup();
  });
  state.kakaoInfoOverlay = new kakao.maps.CustomOverlay({
    map: state.kakaoMap,
    position,
    xAnchor: 0.5,
    yAnchor: 1.12,
    zIndex: 82,
    content: popup,
  });
  if (pan) state.kakaoMap.panTo(position);
}

function openFallbackMapPopup(sensor) {
  ensureMapBoardShell();
  const layer = els.mapBoard.querySelector(".map-popup-layer");
  if (!layer) return;
  layer.innerHTML = `
    <article class="kakao-info-popup fallback-popup">
      ${mapSensorPopupHtml(sensor, getActiveIncident())}
    </article>
  `;
}

function openFallbackPlugPopup(plug) {
  ensureMapBoardShell();
  const layer = els.mapBoard.querySelector(".map-popup-layer");
  if (!layer) return;
  layer.innerHTML = `
    <article class="kakao-info-popup plug-popup fallback-popup">
      ${mapPlugPopupHtml(plug)}
    </article>
  `;
}

function sensorHasPosition(sensor) {
  return Number.isFinite(Number(sensor?.lat)) && Number.isFinite(Number(sensor?.lng));
}

function renderEvents() {
  const rows = buildTimeline();
  els.eventTimeline.innerHTML = rows.map((row) => `
    <article class="timeline-item ${row.critical ? "critical" : ""}">
      <strong>${escapeHtml(row.title)}</strong>
      <div>${escapeHtml(row.message)}</div>
      <small>${formatTime(row.time)}</small>
    </article>
  `).join("") || emptyBlock("기록할 만한 이벤트가 없습니다.");
}

function getActiveIncident() {
  return activeIncidents()[0] || null;
}

function activeIncidents() {
  return state.incidents.filter((incident) =>
    incident.status === "active" || incident.status === "open"
  );
}

function renderDevices() {
  els.deviceGrid.innerHTML = state.plugs.map(deviceCard).join("")
    || emptyBlock("등록된 플러그가 없습니다.");
}

function deviceCard(plug) {
  const stateClass = plug.actualState === "ON" ? "on" : "off";
  const traces = state.plugTraces[plug.plugId] || [];
  const traceLoading = Boolean(state.plugTraceLoading[plug.plugId]);
  return `
    <article class="device-card" data-plug-card="${escapeAttr(plug.plugId)}">
      <div class="device-header">
        <div>
          <h3>${escapeHtml(plug.displayName || plug.plugId)}</h3>
          <div class="card-sub">${escapeHtml(plug.location || plug.sensorId || "연결 위치 미등록")}</div>
        </div>
        <span class="device-state ${stateClass}">${plug.actualState || "확인 중"}</span>
      </div>
      <div class="card-sub">모드: ${plug.mode === "auto" ? "자동" : "수동"} · 마지막 응답: ${formatTime(plug.lastSeen)}</div>
      <div class="card-sub">전압 ${value(plug.voltage, "V")} · 전류 ${value(plug.current, "A")} · 전력 ${value(plug.power, "W")}</div>
      <div class="device-actions">
        <button class="device-action primary" data-action="command-plug" data-plug-id="${escapeAttr(plug.plugId)}" data-command="ON">켜기</button>
        <button class="device-action" data-action="command-plug" data-plug-id="${escapeAttr(plug.plugId)}" data-command="OFF">끄기</button>
        <button class="device-action ghost" data-action="refresh-plug-trace" data-plug-id="${escapeAttr(plug.plugId)}">
          ${traceLoading ? "확인 중" : "이력 갱신"}
        </button>
        <button class="device-action ghost" data-action="export-plug-csv" data-plug-id="${escapeAttr(plug.plugId)}">CSV 저장</button>
      </div>
      <div class="plug-trace">
        <div class="trace-head">
          <strong>제어 이력</strong>
          <span>${traces.length ? `${traces.length}건` : "최근 기록 없음"}</span>
        </div>
        ${traces.slice(0, 4).map(traceRow).join("") || `<div class="trace-empty">아직 제어 요청이나 응답 기록이 없습니다.</div>`}
      </div>
    </article>
  `;
}

function renderSettings() {
  const profileName = state.profile?.displayName || state.user?.displayName || "이름 미등록";
  const organization = state.profile?.organizationName || "조직 미등록";
  els.settingsPanel.innerHTML = `
    <div class="settings-row"><strong>프로필</strong><span>${escapeHtml(profileName)}</span></div>
    <div class="settings-row"><strong>소속</strong><span>${escapeHtml(organization)}</span></div>
    <div class="settings-row"><strong>로그인</strong><span>${state.user?.email ? escapeHtml(state.user.email) : "로그인 필요"}</span></div>
    <div class="settings-row"><strong>연결된 센서</strong><span>${state.sensors.length}개</span></div>
    <div class="settings-row"><strong>연결된 플러그</strong><span>${state.plugs.length}개</span></div>
    <div class="settings-row"><strong>최근 오류</strong><span>${escapeHtml(state.lastError || "없음")}</span></div>
  `;
}

function openProfileModal() {
  const profile = state.profile || {};
  els.modal.classList.remove("hidden");
  els.modal.innerHTML = `
    <article class="modal-card profile-modal-card">
      <header class="modal-head profile-head">
        <div>
          <div class="card-sub">ACCOUNT PROFILE</div>
          <h2>사용자 프로필</h2>
        </div>
        <button class="icon-button" data-action="close-modal">×</button>
      </header>
      <div class="modal-body profile-body">
        <form class="profile-form" data-profile-form>
          <label>
            <span>이름</span>
            <input name="displayName" value="${escapeAttr(profile.displayName || state.user?.displayName || "")}" autocomplete="name" />
          </label>
          <label>
            <span>소속</span>
            <input name="organizationName" value="${escapeAttr(profile.organizationName || "")}" autocomplete="organization" />
          </label>
          <label>
            <span>역할</span>
            <input name="role" value="${escapeAttr(profile.role || "")}" />
          </label>
          <label>
            <span>연락처</span>
            <input name="phone" value="${escapeAttr(profile.phone || "")}" autocomplete="tel" />
          </label>
          <label class="profile-check">
            <input name="notifyCritical" type="checkbox" ${profile.notifyCritical === false ? "" : "checked"} />
            <span>위급 알림을 프로필에 연결</span>
          </label>
        </form>
        <aside class="profile-summary">
          <div class="avatar large">${initials(profile.displayName || state.user?.email || "CA")}</div>
          <strong>${escapeHtml(state.user?.email || "로그인 계정 없음")}</strong>
          <span>이 프로필은 앱과 웹에서 같은 센서와 플러그를 불러오는 기준으로 사용됩니다.</span>
        </aside>
      </div>
      <footer class="modal-foot">
        <button class="soft-button" data-action="sign-out">로그아웃</button>
        <button class="soft-button" data-action="close-modal">닫기</button>
        <button class="danger-button" data-action="save-profile">저장</button>
      </footer>
    </article>
  `;
}

async function saveProfile() {
  if (!state.db || !state.user) return;
  const form = els.modal.querySelector("[data-profile-form]");
  if (!form) return;
  const data = new FormData(form);
  const profile = {
    uid: state.user.uid,
    email: state.user.email || "",
    photoURL: state.user.photoURL || "",
    displayName: String(data.get("displayName") || "").trim(),
    organizationName: String(data.get("organizationName") || "").trim(),
    role: String(data.get("role") || "").trim(),
    phone: String(data.get("phone") || "").trim(),
    defaultFacilityId: String(data.get("defaultFacilityId") || "").trim(),
    notifyCritical: data.get("notifyCritical") === "on",
    updatedAt: serverTimestamp(),
  };
  try {
    await setDoc(doc(state.db, "user_profiles", state.user.uid), profile, { merge: true });
    state.profile = { ...(state.profile || {}), ...profile };
    closeModal();
    renderAuthGate();
    renderSettings();
  } catch (error) {
    state.lastError = `프로필 저장 실패: ${error?.message || error}`;
    renderSettings();
  }
}

function openEmergencyModal() {
  const incident = getActiveIncident();
  const alert = getCriticalAlert() || state.alerts[0] || null;
  const sensorId = incident?.sensorId || alert?.sensorId;
  const sensor = sensorId
    ? state.sensors.find((item) => item.id === sensorId)
    : state.sensors.find((item) => item.status === "danger") || state.sensors[0];
  const plugs = sensor
    ? state.plugs.filter((plug) => plug.sensorId === sensor.id || plug.stationId === sensor.id)
    : state.plugs.slice(0, 2);
  const title = incident?.title || alert?.title || "확인할 상황 없음";
  const message = incident?.message || alert?.message || "앱에서 전송된 상황이 없습니다.";
  const location = incident?.location || sensor?.location || alert?.location || "위치 정보 없음";
  const createdAt = incident?.createdAt || alert?.createdAt || Date.now();

  els.modal.classList.remove("hidden");
  els.modal.innerHTML = `
    <article class="modal-card incident-modal-card">
      <header class="modal-head">
        <div>
          <div class="card-sub">LEVEL: ${(incident?.isCritical || alert?.isCritical) ? "EMERGENCY" : "MONITORING"}</div>
          <h2>${escapeHtml(title)}</h2>
        </div>
        <button class="icon-button" data-action="close-modal">×</button>
      </header>
      <div class="modal-body">
        <section>
          <h2>상황 정보</h2>
          <div class="alert-item ${(incident?.isCritical || alert?.isCritical) ? "critical" : ""}">
            <strong>${escapeHtml(sensor?.name || "시설 선택 필요")}</strong>
            <div>${escapeHtml(location)}</div>
            <div>${escapeHtml(message)}</div>
            <small>${formatTime(createdAt)}</small>
          </div>
          <h2 style="margin-top: 28px">판단 근거</h2>
          ${sensor ? metricGrid(sensor) : emptyBlock("센서 데이터가 없습니다.")}
        </section>
        <section class="incident-device-section">
          <h2>연결 장비</h2>
          <div class="stack incident-device-list">
            ${plugs.map(deviceCard).join("") || emptyBlock("연결된 대응 장비가 없습니다.")}
          </div>
        </section>
      </div>
      <footer class="modal-foot">
        <button class="soft-button" data-action="close-modal">대시보드로 돌아가기</button>
        ${incident ? `<button class="soft-button" data-action="end-incident" data-incident-id="${escapeAttr(incident.id)}">상황 종료</button>` : ""}
        <button class="danger-button" data-action="copy-situation">상황 요약 복사</button>
      </footer>
    </article>
  `;
}

async function createIncidentFromCurrent() {
  if (!state.db || !state.user) return;
  const alert = getCriticalAlert() || state.alerts[0] || null;
  const sensor = alert?.sensorId
    ? state.sensors.find((item) => item.id === alert.sensorId)
    : state.sensors.find((item) => item.status === "danger") || state.sensors[0];
  const linkedPlugs = sensor ? linkedPlugsForSensor(sensor) : state.plugs.slice(0, 3);
  const ref = doc(collection(state.db, "user_profiles", state.user.uid, "incidents"));
  const title = alert?.title || (sensor?.status === "danger" ? "화재 의심 상황 확인 필요" : "현장 확인 요청");
  const message = alert?.message || (sensor
    ? `${sensor.name}의 현재 상태를 확인해 주세요.`
    : "센서 위치와 상황을 확인해 주세요.");
  try {
    await setDoc(ref, {
      id: ref.id,
      status: "active",
      severity: alert?.isCritical || sensor?.status === "danger" ? "critical" : "warning",
      type: alert?.type || "manual_report",
      title,
      message,
      sensorId: sensor?.id || "",
      sensorName: sensor?.name || "",
      location: sensor?.location || alert?.location || "",
      metrics: sensor ? {
        pm25: sensor.pm25,
        co2: sensor.co2,
        co: sensor.co,
        tvoc: sensor.tvoc,
        nox: sensor.nox,
        temperature: sensor.temperature,
        humidity: sensor.humidity,
        iaqi: sensor.iaqi,
      } : {},
      plugIds: linkedPlugs.map((plug) => plug.plugId),
      plugSummary: linkedPlugs.map((plug) => ({
        plugId: plug.plugId,
        displayName: plug.displayName,
        state: plug.actualState,
        mode: plug.mode,
      })),
      createdAt: serverTimestamp(),
      createdBy: state.user.email || state.user.uid,
      updatedAt: serverTimestamp(),
    }, { merge: true });
    setSyncText("대시보드 상황이 생성됨");
    closeModal();
  } catch (error) {
    state.lastError = `상황 공유 실패: ${error?.message || error}`;
    renderSettings();
  }
}

async function endIncident(incidentId) {
  if (!state.db || !state.user || !incidentId) return;
  const alert = state.alerts.find((item) => item.id === incidentId);
  const incident = state.incidents.find((item) => item.id === incidentId);

  if (alert && !incident) {
    dismissAlert(incidentId);
    state.alerts = state.alerts.filter((item) => item.id !== incidentId);
    setSyncText("상황 확인 처리됨");
    closeModal();
    render();
    return;
  }

  try {
    const incidentRef = doc(state.db, "user_profiles", state.user.uid, "incidents", incidentId);
    await setDoc(incidentRef, {
      status: "resolved",
      archived: true,
      resolvedAt: serverTimestamp(),
      resolvedBy: state.user.email || state.user.uid,
      updatedAt: serverTimestamp(),
    }, { merge: true });
    state.incidents = state.incidents.filter((item) => item.id !== incidentId);
    if (alert) {
      dismissAlert(incidentId);
      state.alerts = state.alerts.filter((item) => item.id !== incidentId);
    }
    setSyncText("상황 종료 처리됨");
    closeModal();
    render();
  } catch (error) {
    state.lastError = `상황 종료 실패: ${error?.message || error}`;
    renderSettings();
  }
}

async function copySituationSummary() {
  const incident = getActiveIncident();
  const alert = getCriticalAlert() || state.alerts[0] || null;
  const sensorId = incident?.sensorId || alert?.sensorId;
  const sensor = sensorId
    ? state.sensors.find((item) => item.id === sensorId)
    : state.sensors.find((item) => item.status === "danger") || state.sensors[0];
  const text = [
    `[CleanAir] ${incident?.title || alert?.title || "상황 요약"}`,
    `위치: ${sensor?.name || incident?.location || alert?.location || "확인 필요"}`,
    `주소/상세: ${sensor?.location || incident?.location || alert?.location || "정보 없음"}`,
    `시간: ${formatTime(incident?.createdAt || alert?.createdAt || sensor?.updatedAt || Date.now())}`,
    `상태: ${sensor ? sensorStatusSentence(sensor) : "센서 정보 없음"}`,
    `PM2.5 ${value(sensor?.pm25, "ug/m3")} / CO2 ${value(sensor?.co2, "ppm")} / CO ${value(sensor?.co, "ppm")} / TVOC ${value(sensor?.tvoc, "index")} / NOx ${value(sensor?.nox, "index")}`,
  ].join("\n");
  try {
    await navigator.clipboard.writeText(text);
    setSyncText("상황 요약 복사됨");
  } catch (_) {
    setSyncText("브라우저에서 복사를 허용해 주세요");
  }
}

function closeModal() {
  els.modal.classList.add("hidden");
  els.modal.innerHTML = "";
}

function selectSensor(sensorId) {
  state.selectedSensorId = sensorId;
  renderFacilities();
  setView("facilities");
}

function selectMapSensor(sensorId, { pan = false } = {}) {
  if (!sensorId) return;
  state.selectedSensorId = sensorId;
  state.mapPopupSensorId = sensorId;
  state.mapPopupPlugId = null;
  const sensor = state.sensors.find((item) => item.id === sensorId);
  const plugs = sensor ? linkedPlugsForSensor(sensor) : [];
  refreshPlugTracesFor(plugs);
  if (sensor && state.kakaoMap && window.kakao?.maps && sensorHasPosition(sensor)) {
    openKakaoMapPopup(sensor, { pan });
  } else if (sensor) {
    openFallbackMapPopup(sensor);
  } else {
    renderMap();
  }
  renderFacilities();
}

function selectMapPlug(plugId, { pan = false } = {}) {
  if (!plugId) return;
  state.mapPopupSensorId = null;
  state.mapPopupPlugId = plugId;
  const plug = state.plugs.find((item) => sameId(item.plugId, plugId));
  if (!plug) {
    renderMap();
    return;
  }
  refreshPlugTracesFor([plug], { force: true });
  if (state.kakaoMap && window.kakao?.maps && mapPlugPosition(plug)) {
    openKakaoPlugPopup(plug, { pan });
  } else {
    openFallbackPlugPopup(plug);
  }
}

async function exportPlugTraceCsv(plugId) {
  if (!plugId) return;
  await refreshPlugTracesFor([plugId], { force: true });
  const plug = state.plugs.find((item) => item.plugId === plugId);
  const traces = state.plugTraces[plugId] || [];
  if (!traces.length) {
    setSyncText("내보낼 제어 이력이 없습니다");
    return;
  }

  const rows = [
    ["time", "plug_id", "plug_name", "command", "status", "response", "failed"],
    ...traces.map((trace) => [
      formatCsvTime(trace.time),
      plugId,
      plug?.displayName || "",
      trace.commandLabel,
      trace.statusLabel,
      trace.responseLabel,
      trace.failed ? "true" : "false",
    ]),
  ];
  const csv = `\uFEFF${rows.map((row) => row.map(csvCell).join(",")).join("\r\n")}`;
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  const stamp = new Date().toISOString().slice(0, 19).replaceAll(":", "").replace("T", "_");
  link.href = url;
  link.download = `cleanair_plug_${safeFileName(plug?.displayName || plugId)}_${stamp}.csv`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
  setSyncText("플러그 제어 이력 CSV 저장됨");
}

function buildTimeline() {
  const incidentRows = state.incidents.slice(0, 30).map((incident) => ({
    title: incident.status === "active" ? incident.title : `${incident.title} 종료`,
    message: incident.status === "active"
      ? incident.message || incident.location || "상황 확인 필요"
      : `${formatTime(incident.resolvedAt)}에 종료 처리되었습니다.`,
    time: incident.status === "active" ? incident.createdAt : incident.resolvedAt || incident.updatedAt,
    critical: incident.isCritical && incident.status === "active",
  }));

  const alertRows = state.alerts.slice(0, 30).map((alert) => ({
    title: alert.title,
    message: alert.message || alert.location || "상세 내용 없음",
    time: alert.createdAt,
    critical: alert.isCritical,
  }));

  const plugRows = state.plugs
    .filter((plug) => plug.lastSeen || plug.updatedAt)
    .slice(0, 12)
    .map((plug) => ({
      title: `${plug.displayName || plug.plugId} ${plug.actualState || "상태 확인"}`,
      message: plug.mode === "auto" ? "자동 제어 상태가 갱신되었습니다." : "수동 제어 상태가 갱신되었습니다.",
      time: plug.lastSeen || plug.updatedAt,
      critical: false,
    }));

  const traceRows = Object.values(state.plugTraces)
    .flat()
    .slice(0, 20)
    .map((trace) => ({
      title: `${trace.plugLabel || "플러그"} ${trace.commandLabel}`,
      message: trace.responseLabel || trace.statusLabel,
      time: trace.time,
      critical: trace.failed,
    }));

  return [...incidentRows, ...alertRows, ...plugRows, ...traceRows]
    .sort((a, b) => toMillis(b.time) - toMillis(a.time))
    .slice(0, 30);
}

function normalizePlugTrace(trace = {}) {
  const plug = state.plugs.find((item) => item.plugId === trace.plugId);
  const command = firstText(trace.command, trace.request?.desiredState, trace.request?.actualState, "");
  const responseStatus = firstText(trace.response?.status, trace.request?.status, trace.status, "");
  const actualState = firstText(trace.response?.actualState, trace.request?.actualState, "");
  const failed = ["failed", "error", "timeout", "suppressed"].some((word) =>
    responseStatus.toLowerCase().includes(word)
  );
  const metricLabel = trace.metric || trace.thresholds?.metric || trace.controlBasis || "";
  return {
    ...trace,
    plugLabel: plug?.displayName || trace.plugId,
    commandLabel: command === "ON" ? "켜기 요청" : command === "OFF" ? "끄기 요청" : "제어 요청",
    statusLabel: controlStatusLabel(responseStatus),
    responseLabel: actualState
      ? `응답 상태 ${actualState}${metricLabel ? ` · 기준 ${metricLabel}` : ""}`
      : controlStatusLabel(responseStatus),
    time: firstTime(trace.decisionAt, trace.request?.queuedAt, trace.response?.createdAt),
    failed,
  };
}

function traceRow(trace) {
  return `
    <div class="trace-row ${trace.failed ? "failed" : ""}">
      <div>
        <strong>${escapeHtml(trace.commandLabel)}</strong>
        <span>${escapeHtml(trace.responseLabel || trace.statusLabel)}</span>
      </div>
      <time>${formatTime(trace.time)}</time>
    </div>
  `;
}

function controlStatusLabel(status) {
  const normalized = String(status || "").toLowerCase();
  if (!normalized) return "응답 대기";
  if (normalized.includes("ack") || normalized.includes("success") || normalized.includes("completed")) return "응답 확인";
  if (normalized.includes("queued") || normalized.includes("pending") || normalized.includes("dispatching")) return "명령 전송 중";
  if (normalized.includes("suppressed")) return "수동 조작 보호 중";
  if (normalized.includes("failed") || normalized.includes("error") || normalized.includes("timeout")) return "제어 실패";
  return status;
}

function normalizeSensorLink(id, data = {}) {
  return {
    id,
    sensorId: firstText(data.sensorId, id, ""),
    spaceName: firstText(data.spaceName, data.displayName, data.name, ""),
    address: firstText(data.address, data.locationName, ""),
    detailLocation: firstText(data.detailLocation, data.indoorLocation, ""),
    floor: firstText(data.floor, ""),
    lat: firstNumber(data.latitude, data.lat),
    lng: firstNumber(data.longitude, data.lng),
    updatedAt: firstTime(data.updatedAt, data.linkedAt, data.createdAt),
  };
}

function normalizePlugLink(id, data = {}) {
  return normalizePlug({
    ...data,
    plugId: firstText(data.plugId, id, ""),
    sensorId: firstText(data.linkedSensorId, data.sensorId, data.stationId, ""),
    stationId: firstText(data.linkedSensorId, data.stationId, data.sensorId, ""),
    spaceName: firstText(data.linkedSpaceName, data.spaceName, data.locationName, ""),
    locationName: firstText(data.linkedSpaceName, data.locationName, data.spaceName, ""),
    updatedAt: data.updatedAt || data.linkedAt || data.createdAt,
  });
}

function mergeSensorLink(sensor, link) {
  if (!link) return sensor;
  return {
    ...sensor,
    name: firstText(link.spaceName, sensor.name),
    location: firstText(
      [link.address, link.floor, link.detailLocation].filter(Boolean).join(" · "),
      sensor.location
    ),
    lat: link.lat ?? sensor.lat,
    lng: link.lng ?? sensor.lng,
    updatedAt: firstTime(sensor.updatedAt, link.updatedAt),
  };
}

function normalizeSensor(id, data = {}) {
  const latest = data.latest || data.current || data.snapshot || data.measurement || data;
  const location = data.location || data.sensorLocation || {};
  const name = firstText(
    data.spaceName,
    location.spaceName,
    data.displayName,
    data.name,
    id
  );
  const status = sensorStatus(latest, data);
  return {
    id,
    name,
    location: firstText(
      location.address,
      location.detailLocation,
      data.address,
      data.locationName,
      ""
    ),
    lat: firstNumber(location.latitude, data.latitude, data.lat),
    lng: firstNumber(location.longitude, data.longitude, data.lng),
    pm25: firstNumber(latest.pm25, latest.pm2_5, latest.pm02, data.pm25),
    co2: firstNumber(latest.co2, latest.rco2, data.co2),
    co: firstNumber(latest.co, latest.co_ppm, latest.carbon_monoxide, latest.carbonMonoxide, data.co, data.co_ppm, data.carbon_monoxide, data.carbonMonoxide),
    tvoc: firstNumber(latest.tvoc, latest.tvocIndex, data.tvoc),
    nox: firstNumber(latest.nox, latest.noxIndex, latest.noX, latest.no2, latest.no2Index, data.nox, data.no2),
    temperature: firstNumber(latest.temperature, latest.temp, data.temperature),
    humidity: firstNumber(latest.humidity, latest.rh, data.humidity),
    iaqi: firstNumber(latest.iaqi, data.iaqi),
    status,
    updatedAt: firstTime(latest.timestamp, latest.updatedAt, data.updatedAt, data.lastSeen),
    bound: data.bound !== false,
    archived: data.archived === true || data.deleted === true || data.disabled === true,
  };
}

function normalizeAlert(id, data = {}) {
  const severity = String(data.severity || data.level || data.riskLevel || "").toLowerCase();
  const type = String(data.type || data.alertType || "").toLowerCase();
  const title = firstText(
    data.title,
    type.includes("fire") ? "화재 의심 패턴 감지" : "",
    severity.includes("critical") ? "긴급 경고" : "",
    "공기질 알림"
  );
  return {
    id,
    type,
    severity,
    title,
    message: firstText(data.message, data.body, data.reason, ""),
    location: firstText(data.locationName, data.spaceName, data.address, ""),
    sensorId: firstText(data.sensorId, data.stationId, ""),
    createdAt: firstTime(data.createdAt, data.timestamp, data.sentAt),
    isCritical: severity.includes("critical")
      || severity.includes("emergency")
      || severity.includes("fire")
      || type.includes("fire"),
  };
}

function normalizeIncident(id, data = {}) {
  const severity = String(data.severity || data.level || "").toLowerCase();
  const status = String(data.status || "active").toLowerCase();
  return {
    id,
    ...data,
    status,
    severity,
    type: String(data.type || "").toLowerCase(),
    title: firstText(data.title, severity.includes("critical") ? "위급 상황" : "상황 확인 요청"),
    message: firstText(data.message, data.reason, ""),
    location: firstText(data.location, data.locationName, data.address, ""),
    sensorId: firstText(data.sensorId, data.stationId, ""),
    createdAt: firstTime(data.createdAt, data.timestamp, data.sentAt),
    updatedAt: firstTime(data.updatedAt, data.createdAt),
    resolvedAt: firstTime(data.resolvedAt, data.closedAt),
    archived: data.archived === true || data.deleted === true,
    isCritical: severity.includes("critical")
      || severity.includes("emergency")
      || String(data.type || "").includes("fire"),
  };
}

function normalizePlug(data = {}) {
  const telemetry = data.telemetry || {};
  return {
    ...data,
    plugId: data.plugId || data.id || "",
    displayName: firstText(data.displayName, data.name, data.plugId, "플러그"),
    sensorId: firstText(data.sensorId, data.stationId, data.linkedSensorId, ""),
    stationId: firstText(data.stationId, data.sensorId, data.linkedSensorId, ""),
    location: firstText(data.spaceName, data.locationName, data.linkedSpaceName, data.location, ""),
    actualState: firstText(data.actualState, data.power, data.desiredState, "UNKNOWN"),
    mode: String(data.mode || "manual").toLowerCase(),
    online: data.online !== false,
    voltage: firstNumber(telemetry.voltage, telemetry.Voltage, data.voltage),
    current: firstNumber(telemetry.current, telemetry.Current, data.current),
    power: firstNumber(telemetry.power, telemetry.Power, data.powerWatts),
    lastSeen: firstTime(data.lastSeen, data.updatedAt, data.createdAt),
    plugIp: firstText(data.plugIp, data.localIp, data.ipAddress, ""),
    tasmotaTopic: firstText(data.tasmotaTopic, data.mqttTopic, data.topic, ""),
    archived: data.archived === true || data.deleted === true || data.disabled === true,
  };
}

const samplePatterns = [
  "sample",
  "demo",
  "dummy",
  "test",
  "smoke",
  "verify",
  "loop",
  "mqtt-auto",
  "debug",
  "fixture",
  "example",
  "placeholder",
  "seed",
  "fake",
  "mock",
  "stub",
  "임시",
  "샘플",
  "테스트",
  "예시",
  "가짜",
];

function isSampleRecord(...parts) {
  const text = parts
    .filter((part) => part !== null && part !== undefined)
    .map((part) => String(part).toLowerCase())
    .join(" ");
  return samplePatterns.some((pattern) => text.includes(pattern));
}

function linkedSensorIds() {
  return new Set(state.sensorLinks.map((link) => link.sensorId).filter(Boolean));
}

function linkedPlugIds() {
  return new Set(state.plugLinks.map((plug) => plug.plugId).filter(Boolean));
}

function sensorLinkMap() {
  return new Map(state.sensorLinks.map((link) => [link.sensorId, link]));
}

function alertBelongsToUser(alert) {
  const ids = linkedSensorIds();
  if (!ids.size) return false;
  if (alert.sensorId && ids.has(alert.sensorId)) return true;
  return state.sensorLinks.some((link) =>
    sameText(alert.location, link.spaceName)
    || sameText(alert.location, link.address)
    || sameText(alert.location, link.detailLocation)
  );
}

function isVisibleSensor(sensor) {
  if (sensor.archived || sensor.bound === false) return false;
  if (isSampleRecord(sensor.id, sensor.name, sensor.location)) return false;
  const hasMeasurement = [
    sensor.pm25,
    sensor.co2,
    sensor.co,
    sensor.tvoc,
    sensor.temperature,
    sensor.humidity,
    sensor.iaqi,
  ].some((item) => item !== null && item !== undefined);
  const updatedAtMillis = toMillis(sensor.updatedAt);
  return hasMeasurement && (!updatedAtMillis || hasRecentUpdate(sensor.updatedAt, 30));
}

function isVisibleAlert(alert) {
  if (isSampleRecord(alert.id, alert.sensorId, alert.title, alert.message, alert.location)) return false;
  const maxAgeDays = alert.isCritical ? 3 : 30;
  return hasRecentUpdate(alert.createdAt, maxAgeDays);
}

function dismissedAlertStorageKey() {
  return `cleanair.dismissedAlerts.${state.user?.uid || "guest"}`;
}

function loadDismissedAlerts() {
  try {
    const raw = window.localStorage.getItem(dismissedAlertStorageKey());
    const ids = JSON.parse(raw || "[]");
    state.dismissedAlertIds = new Set(Array.isArray(ids) ? ids.map(String) : []);
  } catch (_) {
    state.dismissedAlertIds = new Set();
  }
}

function saveDismissedAlerts() {
  try {
    const ids = [...state.dismissedAlertIds].slice(-200);
    window.localStorage.setItem(dismissedAlertStorageKey(), JSON.stringify(ids));
  } catch (_) {
    // localStorage may be unavailable in private or blocked browser modes.
  }
}

function dismissAlert(alertId) {
  if (!alertId) return;
  state.dismissedAlertIds.add(String(alertId));
  saveDismissedAlerts();
}

function isDismissedAlert(alert) {
  return Boolean(alert?.id && state.dismissedAlertIds.has(String(alert.id)));
}

function isVisiblePlug(plug) {
  const identity = [
    plug.plugId,
    plug.displayName,
    plug.sensorId,
    plug.stationId,
    plug.location,
    plug.tasmotaTopic,
    plug.mqttTopic,
    plug.topic,
    plug.profileId,
  ];
  if (plug.archived) return false;
  if (isSampleRecord(...identity)) return false;
  if (!plug.plugId) return false;

  const hasControlTarget = Boolean(plug.plugIp || plug.tasmotaTopic);
  const hasConfirmedState = ["ON", "OFF"].includes(String(plug.actualState || "").toUpperCase());
  const recentlySeen = hasRecentUpdate(plug.lastSeen, 30);
  return hasControlTarget && (hasConfirmedState || recentlySeen);
}

function hasRecentUpdate(value, maxAgeDays) {
  const millis = toMillis(value);
  if (!millis) return false;
  return Date.now() - millis <= maxAgeDays * 24 * 60 * 60 * 1000;
}

function sameId(a, b) {
  if (!a || !b) return false;
  return String(a).trim().toLowerCase() === String(b).trim().toLowerCase();
}

function sameText(a, b) {
  if (!a || !b) return false;
  const left = String(a).trim().toLowerCase();
  const right = String(b).trim().toLowerCase();
  return left.length >= 2 && right.length >= 2
    && (left.includes(right) || right.includes(left));
}

function sensorStatus(latest, data) {
  const fire = String(data.fireRiskLevel || latest.fireRiskLevel || "").toLowerCase();
  if (fire.includes("fire") || fire.includes("critical")) return "danger";
  const iaqi = firstNumber(latest.iaqi, data.iaqi);
  if (iaqi !== null && iaqi >= 3) return "danger";
  if (iaqi !== null && iaqi >= 1) return "warning";
  const pm25 = firstNumber(latest.pm25, latest.pm2_5, data.pm25);
  const co2 = firstNumber(latest.co2, latest.rco2, data.co2);
  if ((pm25 !== null && pm25 >= 75) || (co2 !== null && co2 >= 1500)) return "warning";
  return "normal";
}

function getStatusCounts() {
  const counts = { normal: 0, warning: 0, danger: 0, offline: 0 };
  for (const sensor of state.sensors) counts[sensor.status] += 1;
  return counts;
}

function getCriticalAlert() {
  return state.alerts.find((alert) => alert.isCritical && !isDismissedAlert(alert)) || null;
}

function statusLabel(status) {
  if (status === "danger") return "화재 의심";
  if (status === "warning") return "주의";
  if (status === "offline") return "오프라인";
  return "정상";
}

function statusPillClass(status) {
  if (status === "danger") return "red";
  if (status === "warning") return "amber";
  return "cyan";
}

function emptyBlock(text) {
  return `<div class="alert-item"><span class="muted">${escapeHtml(text)}</span></div>`;
}

function formatError(error) {
  if (!error) return "unknown";
  const code = error.code ? `[${error.code}] ` : "";
  const message = error.message || String(error);
  return `${code}${message}`;
}

function showAuthError(context, error) {
  const detail = formatError(error);
  state.lastError = `${context}: ${detail}`;
  console.error(state.lastError, error);
  if (els.authMessage) {
    els.authMessage.textContent = `${context}: ${detail}`;
  }
  setSyncText("인증 오류");
  renderSettings();
}

function setError(error) {
  state.lastError = formatError(error);
  console.error("Dashboard sync error:", error);
  setSyncText("동기화 오류");
  renderSettings();
}

function setSyncText(text) {
  if (els.sidebarFoot) els.sidebarFoot.textContent = text;
}

function value(raw, unit) {
  if (raw === null || raw === undefined || Number.isNaN(Number(raw))) return "N/A";
  const fixed = Math.abs(Number(raw)) >= 100 ? Number(raw).toFixed(0) : Number(raw).toFixed(1);
  return `${fixed} ${unit}`;
}

function firstNumber(...values) {
  for (const value of values) {
    const number = Number(value);
    if (Number.isFinite(number)) return number;
  }
  return null;
}

function firstText(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) return value.trim();
    if (typeof value === "number" && Number.isFinite(value)) return String(value);
  }
  return "";
}

function firstTime(...values) {
  for (const value of values) {
    if (!value) continue;
    if (value.toDate) return value.toDate();
    if (value.seconds) return new Date(value.seconds * 1000);
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) return date;
  }
  return null;
}

function toMillis(value) {
  return firstTime(value)?.getTime() || 0;
}

function formatTime(value) {
  const date = firstTime(value);
  if (!date) return "시간 확인 중";
  return new Intl.DateTimeFormat("ko-KR", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function formatCsvTime(value) {
  const date = firstTime(value);
  if (!date) return "";
  return new Intl.DateTimeFormat("ko-KR", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).format(date);
}

function csvCell(value) {
  const text = String(value ?? "");
  return `"${text.replaceAll('"', '""')}"`;
}

function safeFileName(value) {
  return String(value || "plug")
    .replace(/[\\/:*?"<>|]/g, "_")
    .replace(/\s+/g, "_")
    .slice(0, 48);
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function escapeAttr(value) {
  return escapeHtml(value).replaceAll("`", "&#096;");
}

function cssEscape(value) {
  if (window.CSS?.escape) return window.CSS.escape(value);
  return String(value).replace(/[^a-zA-Z0-9_-]/g, "\\$&");
}

function initials(email) {
  const name = String(email || "CA").split("@")[0].replace(/[^a-zA-Z0-9가-힣]/g, "");
  return (name.slice(0, 2) || "CA").toUpperCase();
}
