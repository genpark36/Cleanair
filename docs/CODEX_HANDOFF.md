# Codex Handoff

Last updated: 2026-05-02

## Current Direction

Build a new Stitch-based app shell and presentation layer inside the existing Flutter project:

- Host app: `Indoorairqualityappv2-main/src/flutter`
- Preserve existing AirGradient/Firebase/Firestore/notification/Tasmota services.
- Keep old UI as legacy until the new shell is stable.
- Do not switch `main.dart` until the final integration phase.
- Do not create a separate Flutter project.

## Confirmed During Analysis

- Flutter entry point: `src/flutter/lib/main.dart`
- Navigation: `HomePage` with `IndexedStack` tabs, settings pushed with `Navigator`.
- State management: `provider`.
- Firestore live flow: `FirestoreSnapshotService` listens to `sensors/{id}` and loads history.
- Sensor pairing: `DeviceBindingControllerV2` plus PIN and mDNS logic in `settings_view.dart`.
- AirGradient local code exists but is not fully wired into UI: `airgradient_local_api.dart`, `airgradient_local_config.dart`, `led_control_service.dart`.
- Tasmota local/cloud control exists: `tasmota_plug_service.dart`.
- Stitch export location is `stitch_map_view_ui_demo/`, not `stitch_exports/`.
- Legacy pipeline analysis is currently `CLEANAIR_APP_PIPELINE_ANALYSIS.md` at repo root.

## Read First Next Session

1. `AGENTS.md`
2. `docs/PROJECT_STATE.md`
3. `docs/CODEX_HANDOFF.md`
4. `Indoorairqualityappv2-main/src/flutter/lib/main.dart`
5. `Indoorairqualityappv2-main/src/flutter/lib/services/firestore_snapshot_service.dart`
6. `Indoorairqualityappv2-main/src/flutter/lib/services/device_binding_service_v2.dart`
7. `Indoorairqualityappv2-main/src/flutter/lib/services/tasmota_plug_service.dart`
8. `Indoorairqualityappv2-main/src/flutter/lib/widgets/settings_view.dart`

## Next Recommended Work

1. Create `lib/ui/stitch/` in `Indoorairqualityappv2-main/src/flutter`.
2. Add Stitch theme tokens and small reusable components.
3. Build one sensor location registration screen from Stitch batch 4.
4. Store location locally first for MVP read-back.
5. Add a temporary way to open the new screen without changing the app entry point.
6. Run `flutter analyze`.

## Do Not Touch Yet

- `src/flutter/lib/main.dart`
- `src/flutter/pubspec.yaml`
- Firebase config files
- Android/iOS platform files
- Existing backend files
- Existing old UI widgets
- Existing markdown files, except the two new docs and minimal `AGENTS.md` reference updates

## Remaining Uncertainty

- Whether sensor location should persist through a new Cloud Function or stay local for the first demo.
- Whether Tasmota extra fields should be first-class backend fields or stored under metadata.
- Whether iOS local network/ATS settings are required for demo devices.
- How to expose the new Stitch shell before final entry point switch.
- Whether the existing dirty worktree contains user changes that affect future edits.
