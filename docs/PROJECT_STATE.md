# Cleanair Project State

Last updated: 2026-05-02

## 1. Project Goal

Cleanair is a Flutter app rebuild and integration project. The goal is not to create a brand-new app from scratch, and not to patch the old UI screen by screen until it becomes unmaintainable.

The current strategy is:

1. Keep the existing Flutter project as the host project.
2. Build a new Stitch-based app shell and presentation layer inside the existing Flutter project.
3. Preserve the existing AirGradient, Firebase, Firestore, notification, alert, and Tasmota pipelines.
4. Reuse existing service logic through adapters/controllers instead of rewriting working services.
5. Keep the old UI as legacy until the new shell is stable.
6. Delay entry point switching until the new shell, navigation, and demo flow are buildable and verified.

The app should feel like a safety-focused indoor air-quality and disaster-prevention assistant, not a generic chart app.

It should help the user answer:

- Is this space currently safe?
- Is the sensor actually working?
- Where is this sensor installed?
- Is an abnormal pattern likely ventilation, cooking smoke, dust, or fire-suspicious?
- Which person or device should respond?
- Can a connected response device be tested and controlled?

## 2. Source Of Truth

Use references in this order:

1. Direct user instruction
2. `AGENTS.md`
3. `docs/PROJECT_STATE.md`
4. `docs/CODEX_HANDOFF.md`
5. Actual source code
6. `CLEANAIR_APP_PIPELINE_ANALYSIS.md`
7. Older markdown files and archived notes

Important note: `AGENTS.md` used to refer to `docs/legacy/CLEANAIR_APP_PIPELINE_ANALYSIS.md`, but the file currently exists at repository root as `CLEANAIR_APP_PIPELINE_ANALYSIS.md`. Do not move it without explicit approval.

## 3. Current Codebase Inventory

Actual Flutter app:

- `Indoorairqualityappv2-main/src/flutter`

Flutter entry point:

- `Indoorairqualityappv2-main/src/flutter/lib/main.dart`

Current navigation:

- `MaterialApp(home: HomePage)`
- `HomePage` uses an `IndexedStack` with four tabs: overview, monitoring, health, comparison.
- Settings opens through `Navigator.push(SettingsView)`.

Current state management:

- `provider`
- `AirQualityController`
- `NotificationPreferencesController`
- `DeviceBindingControllerV2`

Firebase initialization:

- `main.dart` calls `Firebase.initializeApp()` directly.
- `lib/config/firebase_env_options.dart` exists but is not currently used by `main.dart`.

Firestore live data:

- `lib/services/firestore_snapshot_service.dart`
- Listens to `sensors/{id}`
- Loads `sensors/{id}/history`
- Converts Firestore docs into `AirQualitySnapshot`
- Runs `NodeRedHealthEngine`
- Starts/stops `ExternalApiService`

AirGradient and sensor pairing:

- `lib/services/device_binding_service_v2.dart`
- `lib/widgets/settings_view.dart`
- `lib/services/airgradient_local_api.dart`
- `lib/services/airgradient_local_config.dart`
- `lib/services/led_control_service.dart`

Notifications and alerts:

- `lib/services/alert_notification_service.dart`
- `lib/services/alert_notification_engine.dart`
- `lib/services/alert_notification_presenter.dart`
- `lib/services/notification_preferences.dart`
- `lib/services/push_notification_service_v2.dart`
- `lib/services/background_service.dart`

Tasmota smart plug:

- `lib/services/tasmota_plug_service.dart`
- `lib/widgets/settings_view.dart`
- `iaq-v2-firebase/functions/index.js`
- `iaq-v2-firebase/functions/plug_mqtt_worker.js`

Existing old UI:

- `lib/screens/home_page.dart`
- `lib/widgets/air_quality_overview.dart`
- `lib/widgets/metric_detail_view.dart`
- `lib/widgets/health_mode_dashboard.dart`
- `lib/widgets/station_comparison.dart`
- `lib/widgets/settings_view.dart`
- `lib/widgets/sky_background.dart`

Theme/style:

- `main.dart` defines a light Material 3 theme with Pretendard.
- Most old UI styling is embedded in individual widgets.
- Stitch should introduce a new shared visual token layer, not a broad rewrite of the old UI.

## 4. Current Strategy

### 4.1 New App Shell Inside Existing Flutter Project

Create a new Stitch-based shell under a new namespace, for example:

- `lib/ui/stitch/`
- `lib/ui/stitch/theme/`
- `lib/ui/stitch/components/`
- `lib/features/status/`
- `lib/features/setup/`
- `lib/features/disaster_prevention/`
- `lib/features/devices/`

The new shell should:

- Compile independently before being wired into the app.
- Use Stitch visual language as the presentation source.
- Consume existing services through small adapters/controllers.
- Avoid changing `main.dart` until the shell is ready.
- Avoid directly modifying old widgets unless a transition shim requires it.

### 4.2 Old UI Preservation

Do not directly redesign or rewrite the old UI during the shell build.

The old UI should remain available as legacy until:

- Stitch shell compiles.
- Stitch navigation works.
- Core setup flow works.
- Firestore live data appears in the new shell.
- The demo loop is complete.

Only after that should the app entry point be switched.

## 5. Existing Pipelines To Preserve

Preserve these where practical:

- AirGradient PIN claim flow
- mDNS direct binding as a secondary local option
- Sensor ID normalization compatibility
- Firestore `sensors/{id}` live snapshot flow
- Firestore history loading
- Local snapshot cache
- `AirQualitySnapshot` data model
- `NodeRedHealthEngine`
- External API comparison flow
- Notification preferences
- FCM token registration
- Local notification alert pipeline
- Android background monitoring where practical
- AirGradient local LAN control paths
- Tasmota local HTTP control
- Tasmota backend command paths

If an existing service is messy but working, wrap it behind a controller or adapter first.

## 6. Stitch Export Inventory

Actual export location:

- `stitch_map_view_ui_demo/`

There is no root `stitch_exports/` directory at the time of this inventory.

### 6.1 Batch 1: Sensor Onboarding

Path:

- `stitch_map_view_ui_demo/stitch_map_view (1)/stitch_map_view/`

Contents:

- 13 `code.html` screens
- 13 `screen.png` references
- 2 `DESIGN.md` files

Screen themes:

- Splash and first-run onboarding
- Location permission
- Background/battery permission
- Notification permission
- AirGradient setup preparation
- Sensor power-on
- Phone-to-sensor Wi-Fi instruction
- Sensor Wi-Fi settings form
- Connection method selection
- PIN input
- mDNS search
- Connection complete

Integration plan:

- Use as reference for setup/onboarding presentation.
- Bind PIN input to existing `DeviceBindingControllerV2.claimDevice`.
- Bind mDNS scan to existing `MDnsClient` logic or a small extracted adapter.
- Do not imply fully automatic Wi-Fi provisioning unless implemented.

### 6.2 Batch 2: Main Monitoring And Controls

Path:

- `stitch_map_view_ui_demo/stitch_map_view (2)/stitch_map_view/`

Contents:

- 13 `code.html` screens
- 13 `screen.png` references
- 2 `DESIGN.md` files

Screen themes:

- Main dashboard
- Monitoring detail and export
- Health mode for children
- Health mode for purification
- Health mode for seniors
- Comparison normal state
- Comparison empty state
- Comparison loading state
- Location search
- Air control and plug control
- Notification settings
- Advanced control/hysteresis

Integration plan:

- Use dashboard, monitoring, health, comparison, and plug control as visual references.
- Replace static mock values with `AirQualityController` data.
- Keep existing chart and export logic available through adapters.
- Treat placeholder city/location screens as candidates to discard or rewrite.

### 6.3 Batch 3: Tasmota Plug Setup

Path:

- `stitch_map_view_ui_demo/stitch_map_view (3)/stitch_map_view/`

Contents:

- 4 `code.html` screens
- 4 `screen.png` references
- 1 `DESIGN.md`

Screen themes:

- Plug power-on
- Phone-to-plug Wi-Fi instruction
- Plug Wi-Fi settings instruction
- Plug registration complete

Integration plan:

- Use as an instructional Tasmota setup flow.
- Keep the UI honest: the app can guide the user to the Tasmota local web setup page, but should not claim automatic provisioning unless that is actually implemented.

### 6.4 Batch 4: Location And Disaster Prevention

Path:

- `stitch_map_view_ui_demo/stitch_map_view (4)/stitch_map_view/`

Contents:

- 16 `code.html` screens
- 16 `screen.png` references
- 1 `DESIGN.md`

Screen themes:

- Facility safety dashboard
- Abnormal-pattern analysis
- Emergency propagation
- Connected device management
- Sensor location registration
- Sensor local settings
- Disaster-prevention device linking
- Space management
- Automatic control rules
- Event history
- System settings

Integration plan:

- Highest priority for the new missing product flows.
- Use location registration screens for the first setup feature.
- Use sensor settings screen for AirGradient local web/settings/test.
- Use device linking screen for Tasmota registration and ON/OFF test.
- Use facility safety dashboard as the disaster-prevention mode entry.

## 7. Stitch Theme And Component Strategy

Stitch exports are HTML/Tailwind/Material Symbols references, not directly usable Flutter source.

Observed visual tokens:

- Pretendard font
- Primary: `#00677d`
- Primary container/accent: `#00b4d8`
- Background: `#f5fafd` or `#f8fafb`
- Surface containers: near-white and cool gray layers
- Error: `#ba1a1a`
- Secondary: `#396472` or `#4a626d`
- Minimal dividers
- Tonal layering rather than heavy shadows
- Rounded forms and action buttons

Implementation approach:

- Create a small Stitch token layer in Flutter.
- Do not add duplicate global themes until needed.
- Prefer local Stitch widgets under the new shell.
- Reuse existing Pretendard font assets already in `src/flutter/assets/fonts/`.
- Avoid `pubspec.yaml` changes until a needed asset or dependency is confirmed.
- Do not copy Tailwind or CDN dependencies.

Likely component candidates:

- Stitch app shell scaffold
- Top app bar
- Bottom navigation
- Status card
- Sensor status chip
- Form field block
- Segmented choice chips
- Setup action bar
- Device control card
- Event/history row

## 8. Feature Attachment Plan

### 8.1 Sensor Location Registration

Goal:

- After sensor pairing, register where the sensor is installed.

Expected fields:

- `sensorId`
- `spaceName`
- `facilityType`
- `address`
- `buildingName`
- `latitude`
- `longitude`
- `floor`
- `detailLocation`
- `installationMemo`
- `updatedAt`

Implementation order:

1. Define a small location model.
2. Add local storage first for MVP read-back.
3. Add a Stitch location registration screen.
4. Bind the screen to the selected/bound sensor.
5. Display saved location on the new status shell.
6. Decide whether Firestore persistence uses a Cloud Function or a server-owned write path.

Risk:

- Current Firestore rules deny client writes. Direct client save to Firestore is not compatible with current security rules.

### 8.2 Address And Map-Based Location

Goal:

- Support address/building search and selected coordinates where practical.

MVP approach:

- Provide address/building text input.
- Store optional latitude/longitude if user selects from a mock/search result.
- Do not add full map/geocoding until dependencies and API choices are approved.

Stitch references:

- Batch 4 `_12`, `_13`, `_14`, `_16`.

### 8.3 AirGradient Web Settings

Goal:

- Open the AirGradient local web settings page.
- Test local connection.
- Show local IP when available.

Existing code:

- `airgradient_local_api.dart`
- `led_control_service.dart`
- `settings_view.dart` has `_fetchDeviceIp`.

Implementation order:

1. Extract/reuse IP lookup behavior behind an adapter.
2. Add a sensor settings Stitch screen.
3. Add connection test using local HTTP.
4. Add open web settings action.
5. Use external browser fallback if WebView is unavailable.

Risk:

- iOS local network and cleartext HTTP settings may need platform changes later.
- Android cleartext/multicast settings appear present, but should be verified before final device testing.

### 8.4 AirGradient Connection Test

Goal:

- Confirm the sensor can be reached on the same local Wi-Fi.

Implementation options:

- Try `AirGradientLocalClient.fetchSnapshot(ip)`.
- Try `LedControlService.isReachable(ip)` against `/config`.
- Present a clear failure state if local access fails.

### 8.5 Tasmota Plug Registration

Goal:

- Register a Tasmota plug or response device and link it to a sensor/location.

Expected fields:

- `plugId`
- `displayName`
- `deviceType`
- `linkedSensorId`
- `linkedLocationId` or `spaceName`
- `controlMethod`
- `plugIp`
- `mqttTopic`
- `autoControlEnabled`
- `purpose`
- `createdAt`
- `updatedAt`

Existing code:

- `tasmota_plug_service.dart`
- `settings_view.dart`
- `iaq-v2-firebase/functions/index.js` register/list/get/command plug endpoints

Current mismatch:

- Existing backend stores `plugId`, `displayName`, `stationId`, `sensorId`, `tasmotaTopic`, `profileId`, mode, transport fields, desired/actual state, metadata, and `controlEnabled`.
- It does not currently expose first-class `deviceType`, `purpose`, `linkedLocationId`, or `plugIpAddress` in the register payload.

Implementation order:

1. Add Flutter-side device setup model.
2. Use local IP for MVP connection and ON/OFF test.
3. Reuse existing `registerPlug` for backend metadata where compatible.
4. Store extra fields locally first or under `metadata` if backend accepts it.
5. Only expand backend schema after confirming required demo behavior.

### 8.6 Tasmota Web Settings

Goal:

- Open `http://<plugIp>` or Tasmota command page in browser/WebView fallback.

MVP:

- Require manual IP input.
- Explain phone and plug must be on same Wi-Fi.

### 8.7 Tasmota Connection Test

Goal:

- Verify Tasmota responds locally.

Existing code:

- `TasmotaPlugService.getPlugState()` sends `Power` command locally when `plugIpAddress` is set.

MVP:

- Use `getPlugState`.
- Show ON, OFF, or clear failure.

### 8.8 Tasmota ON/OFF Test

Goal:

- Trigger manual ON/OFF.

Existing code:

- `TasmotaPlugService.setPlugState(bool)`
- Local first, remote fallback.

MVP:

- Use local IP first.
- If remote `plugId` is configured, allow backend fallback.
- Always show success/failure state.

### 8.9 Existing Firestore Data Connection

Goal:

- Bind Stitch status/dashboard screens to the existing live data flow.

Implementation order:

1. Read from `AirQualityController`.
2. Map current snapshot to Stitch view models.
3. Preserve old `AirQualitySnapshot` parsing.
4. Add abnormal-pattern summary as presentation logic first.
5. Avoid changing `FirestoreSnapshotService` unless required.

## 9. MVP Demo Loop

Target demo loop:

1. App opens.
2. New Stitch shell can be opened without replacing the entry point yet.
3. Sensor is registered or selected.
4. Sensor location is registered and read back.
5. Status screen shows current air-quality state.
6. Disaster-prevention mode opens.
7. Tasmota plug or response device can be registered.
8. Plug connection can be tested.
9. ON/OFF test can be triggered or a clear failure state is shown.
10. User can understand how the system supports abnormal-pattern response.

## 10. Not In Scope For Now

Do not prioritize:

- New standalone Flutter project
- Immediate `main.dart` entry point replacement
- Direct old UI redesign
- Full web dashboard
- Fire station account management
- Organization-level permission system
- Fully automatic emergency reporting
- Complex multi-facility administration
- Complete map/geocoding implementation
- Perfect Wi-Fi provisioning
- Rewriting every old health mode
- Moving or deleting old markdown files

## 11. Document And File Classification Summary

Active:

- `AGENTS.md`
- `docs/PROJECT_STATE.md`
- `docs/CODEX_HANDOFF.md`
- `Indoorairqualityappv2-main/docs/SYSTEM_ARCHITECTURE.md`
- `CURRENT_SYSTEM_OVERVIEW.md`

Legacy reference:

- `CLEANAIR_APP_PIPELINE_ANALYSIS.md`
- `NODE_RED_COMPUTATION_LOGIC.md`
- `HEALTH_MODE_CURRENT_IMPLEMENTATION_KR.md`
- `UI_REDESIGN_ARTICLE_KR.md`

Archive:

- `Indoorairqualityappv2-main/docs/DEV_LOG.md`
- `Indoorairqualityappv2-main/docs/DEV_PLAN.md`
- `Indoorairqualityappv2-main/docs/DEV_STATUS.md`
- `Indoorairqualityappv2-main/src/flutter/DOWNLOAD_GUIDE.md`
- `Indoorairqualityappv2-main/src/flutter/FILE_INDEX.md`
- `IAQI_ANALYSIS_SESSION_SUMMARY_20260413_KR.md`

Duplicate or overlapping:

- `SMART_PLUG_FREE_EXECUTION_PLAN_KR.md`
- `SMART_PLUG_PROGRESS_LOG_KR.md`
- `SMART_PLUG_FULL_RECORD_20260406_KR.md`
- `CURRENT_SYSTEM_OVERVIEW.md` and `SYSTEM_ARCHITECTURE.md` overlap but both should remain for now.

Unsafe to delete:

- `AGENTS.md`
- `CLEANAIR_APP_PIPELINE_ANALYSIS.md`
- `Indoorairqualityappv2-main/docs/SYSTEM_ARCHITECTURE.md`
- `iaq-v2-firebase/MIGRATION_PLAN.md`
- Firebase/platform configuration files
- Existing backend files
- Existing old UI files
- Stitch export folders

Do not delete or move any old markdown yet.

## 12. Known Risks

Firestore writes:

- Client writes are denied by current Firestore rules.
- Sensor location persistence needs local-first MVP storage or a Cloud Function endpoint.

Backend schema mismatch:

- Tasmota expected fields now exceed existing `registerPlug` payload.
- Use compatible fields or `metadata` first, then expand backend intentionally.

Local device access:

- AirGradient and Tasmota local HTTP require same Wi-Fi.
- iOS may need local network and cleartext configuration.
- Android settings should still be verified on device.

Security:

- Existing client code contains hardcoded default API keys and third-party API keys.
- Do not add new secrets.
- Treat existing secrets as technical debt.

Source path confusion:

- Flutter app is under `Indoorairqualityappv2-main/src/flutter`, not root `lib/`.
- Stitch export is under `stitch_map_view_ui_demo`, not `stitch_exports/`.
- Legacy analysis is currently at root, not `docs/legacy/`.

Dirty worktree:

- `Indoorairqualityappv2-main` already has many modified/deleted/untracked files.
- Do not revert user changes.

## 13. Recommended Next Code Work

First code task:

1. Add a new Stitch UI namespace under the existing Flutter project.
2. Add Stitch theme tokens and a small app-shell preview route/screen.
3. Add one buildable sensor location registration screen using local state only.
4. Do not switch `main.dart`.
5. Run `flutter analyze`.

Success criteria:

- New Stitch screen compiles.
- Old UI remains unchanged.
- No Firebase/platform/pubspec changes unless explicitly required.
- The new screen can later be connected to existing sensor binding state.
