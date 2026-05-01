# AGENTS.md

## Project goal

This project is a Cleanair Flutter app rebuild/integration.

The goal is not to create a new app from scratch.

The goal is to preserve the existing Cleanair functional pipeline while integrating the new Google Stitch-exported UI and adding the missing setup flows.

## Core product direction

Cleanair is positioned as:

- an indoor air-quality monitoring app during normal use
- an abnormal-pattern and disaster-prevention assistant during risky conditions
- a setup and control app for AirGradient sensors and Tasmota smart plugs

The app should not feel like a generic air-quality chart app.

It should help users answer:

- Is this space currently safe?
- Is the sensor actually working?
- Is the current abnormal pattern likely to be poor ventilation, cooking smoke, dust, or a possible fire-suspicious condition?
- Where is the sensor installed?
- Which responsible person or device should respond?
- Can a connected smart plug or response device be tested and controlled?

## Main tasks

The app must support:

1. Existing AirGradient sensor data pipeline
2. Existing Firebase/Firestore live data flow
3. Existing notification and alert pipeline where practical
4. Sensor location registration after sensor pairing
5. Address/map-based sensor location registration where practical
6. AirGradient local web settings access
7. AirGradient connection test
8. Tasmota smart plug registration
9. Tasmota local web settings access
10. Tasmota connection test and ON/OFF test
11. Disaster-prevention mode device linking
12. Stitch UI integration without destroying the visual style
13. A demo-ready user flow for the final presentation

## Reference priority

Use references in this priority order:

1. Direct user instruction
2. `AGENTS.md`
3. `docs/PROJECT_STATE.md`
4. `docs/CODEX_HANDOFF.md`
5. actual source code
6. `CLEANAIR_APP_PIPELINE_ANALYSIS.md`
7. archived or older markdown files

The legacy analysis document explains the intended pipeline, but the actual source code must be inspected before implementation.

If the legacy document and actual code disagree, report the mismatch before changing code.

## Important legacy reference

`CLEANAIR_APP_PIPELINE_ANALYSIS.md` is the main legacy analysis document.

Use it to understand:

- AirGradient sensor connection flow
- PIN-based device claim flow
- Firebase/Firestore data flow
- Firestore `sensors/{id}` live snapshot behavior
- notification and FCM behavior
- AirGradient local LAN behavior
- Tasmota plug service and control APIs
- backend function paths
- known technical debt

Do not treat the legacy document as always correct. Verify against the actual source code before implementation.

## Stitch export rules

The Stitch export folders are raw UI source material.

Do not directly overwrite:

- `lib/main.dart`
- `pubspec.yaml`
- Firebase configuration files
- Android/iOS platform folders
- existing backend files

When importing Stitch UI:

- copy only needed screens and components
- place imported UI under `lib/ui/stitch/` or feature-specific folders
- preserve the visual design
- avoid rewriting the entire app
- avoid adding duplicate themes
- merge duplicated colors/text styles into existing theme tokens where practical
- keep the current app buildable
- do not connect every feature at the same time
- first make the imported screens compile and open correctly

## UI rules

The Stitch UI is the visual source of truth.

Do not invent a new visual style.

When editing UI:

- preserve existing colors, cards, radius, spacing, typography, icons, and navigation patterns
- do not replace Stitch UI with old Cleanair UI
- do not use random Material defaults if a Stitch-style component exists
- do not redesign screens while attaching functionality
- prefer data binding over layout changes
- avoid large widgets when creating new code
- avoid changing layout unless the current task requires it
- if a visual change is necessary, explain why

The UI should feel:

- calm
- trustworthy
- safety-focused
- modern
- practical
- easy to understand during abnormal or emergency-like conditions

## Functional preservation rules

Preserve existing behavior where practical:

- AirGradient PIN pairing
- Firestore `sensors/{id}` live snapshot flow
- sensor history loading
- local snapshot cache
- notification preferences
- FCM token registration
- alerting behavior
- Tasmota plug local control
- Tasmota backend command paths
- sensor ID normalization compatibility

Do not rewrite working services unless there is a clear integration reason.

If existing logic is messy but working, wrap it behind a cleaner adapter/controller before replacing it.

## New setup flow requirements

The rebuilt app must include these setup flows.

### 1. Sensor location registration

After sensor pairing, the user should be able to register:

- space name
- facility type
- address or building name
- map/address-selected location when available
- floor
- detailed indoor location
- installation memo

This location must be usable in:

- alerts
- event history
- disaster-prevention mode
- smart plug linking
- future dashboard expansion

The location model should support both human-readable location information and coordinates where available.

Expected fields include:

- sensorId
- spaceName
- facilityType
- address
- buildingName
- latitude
- longitude
- floor
- detailLocation
- installationMemo
- updatedAt

### 2. AirGradient sensor settings

The app should support:

- opening the AirGradient local web settings page
- testing local connection
- showing local IP if available
- supporting existing LED/CO₂ calibration flows where practical
- falling back to external browser if in-app WebView is unavailable

The UI should explain that local web settings require the phone and sensor to be on the same Wi-Fi network.

### 3. Tasmota smart plug setup

The app should support:

- registering a Tasmota plug or response device
- opening the Tasmota local web settings page
- testing connection
- ON/OFF test control
- linking the plug to a registered sensor location
- storing device type and purpose

Expected fields include:

- plugId
- displayName
- deviceType
- linkedSensorId
- linkedLocationId or spaceName
- controlMethod
- plugIp
- mqttTopic
- autoControlEnabled
- purpose
- createdAt
- updatedAt

The UI should support device types such as:

- 사이렌
- 환기팬
- 경광등
- 스마트 플러그
- 밸브 제어 장치
- 기타

Control methods may include:

- local IP control
- MQTT control
- cloud control

Do not imply that Wi-Fi provisioning can be fully automatic unless it is actually implemented.

## MVP / presentation priority

Prioritize a demo-ready vertical slice over perfect completeness.

The first demo loop should be:

1. app opens
2. main UI/navigation works
3. sensor is registered or selected
4. sensor location is registered
5. home/status screen can show current state
6. disaster-prevention mode opens
7. Tasmota smart plug or response device can be registered
8. plug connection can be tested
9. ON/OFF test can be triggered or a clear failure state is shown
10. user can understand how this would support abnormal-pattern response

Do not spend too much time on:

- full web dashboard
- fire station account management
- organization-level permission system
- fully automatic emergency reporting
- complex multi-facility administration
- complete map/geocoding implementation
- perfect Wi-Fi provisioning
- rewriting every old health mode

## Security rules

Do not add new hardcoded secrets.

Do not move backend secrets into Flutter client code.

API keys must not be committed unless they already exist and the task is explicitly about migrating or isolating them.

Treat existing hardcoded keys as technical debt.

For local device access:

- local HTTP access may require Android/iOS platform configuration
- report required platform changes before making broad changes
- do not weaken device ownership checks
- do not replace PIN-based claiming with mDNS-only binding

## Agent behavior principles

### 1. Think before coding

Before non-trivial edits:

- inspect the relevant files first
- state assumptions explicitly
- if the task is ambiguous, ask or present options instead of silently choosing
- report contradictions between docs and actual code before editing
- do not pretend certainty when the codebase is unclear

### 2. Simplicity first

Prefer the smallest implementation that completes the current goal.

Do not add speculative abstractions.

Do not add generic frameworks for one-off needs.

Do not create new architecture unless the existing structure cannot support the task.

Avoid overengineering setup flows.

Keep the MVP demonstration path working before adding advanced features.

### 3. Surgical changes

Touch only the files required for the current step.

Do not rewrite unrelated screens.

Do not reformat unrelated files.

Do not delete old markdown or old UI files unless explicitly approved.

If unrelated dead code is found, report it instead of deleting it.

When importing Stitch UI, do not overwrite existing app entry points or Firebase configuration.

Every changed line should be explainable by the current task.

### 4. Goal-driven execution

For each implementation step, define:

- goal
- files to edit
- success criteria
- verification command

Examples:

- UI import success means the app builds and the imported screen can be opened.
- Sensor location registration success means input data is saved and can be read back.
- Tasmota test success means the app can send a test ON/OFF command or show a clear failure state.
- AirGradient settings success means the app can open the local web settings URL or fall back to an external browser.

After changes, run the most relevant check, usually `flutter analyze`.

If practical, also run `flutter run`.

### 5. No drive-by cleanup

Do not clean up unrelated code during feature work.

Allowed cleanup:

- imports made unused by the current change
- files created by the current change that are no longer needed
- route references directly affected by the current change

Not allowed without approval:

- deleting old docs
- deleting old screens
- changing unrelated service logic
- replacing state management patterns
- moving Firebase/backend configuration
- large theme rewrites

## Working rules

For non-trivial changes:

1. Inspect relevant files first.
2. Explain the plan.
3. List files to be edited.
4. Wait for approval before large structural edits.
5. Make small, reviewable changes.
6. Run `flutter analyze` after code changes.
7. Report build/test results.

## Initial phase rule

At the beginning, do not implement features immediately.

First:

1. inventory the project
2. inventory the docs
3. inventory the Stitch exports
4. identify source-of-truth documents
5. create an integration plan
6. only then start coding

## Do not delete yet

Do not delete old markdown files or old UI files immediately.

First classify them as:

- active
- legacy reference
- archive
- duplicate
- unsafe to delete

Only delete after explicit approval.

## Reporting format

After each analysis or implementation step, report:

- what was inspected
- what was changed
- files changed
- what was intentionally not changed
- verification command and result
- known risks
- recommended next step
