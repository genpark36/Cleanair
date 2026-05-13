import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:provider/provider.dart';

import '../../../../services/device_binding_service_v2.dart';
import '../../../../services/push_notification_service_v2.dart';
import '../../design/design_frame.dart';
import '../disaster/disaster_screens.dart';
import '../initial/onboarding_battery_screen.dart';
import '../initial/onboarding_location_screen.dart';
import '../initial/onboarding_notifications_screen.dart';
import '../initial/sensor_auto_detect_screen.dart';
import '../initial/sensor_complete_screen.dart';
import '../initial/sensor_internet_screen.dart';
import '../initial/sensor_mode_screen.dart';
import '../initial/sensor_pin_screen.dart';
import '../initial/sensor_power_screen.dart';
import '../initial/sensor_prep_screen.dart';
import '../initial/sensor_wifi_screen.dart';
import '../initial/splash_screen.dart';
import '../initial/welcome_screen.dart';
import '../main_features/main_feature_screens.dart';
import '../plug/plug_setup_screens.dart';
import '../shared/cleanair_stitch_widgets.dart';

enum _FlowArea { setup, main, plugSetup, disaster }

enum _DetailPage {
  mainLocation,
  alertSettings,
  plugAdvanced,
  disasterSpace,
  disasterRules,
  disasterHistory,
  sensorOverview,
  sensorSettings,
  airGradientLocal,
  disasterDeviceConnection,
  locationSearch,
  locationMap,
  locationResults,
  locationDetailInput,
  locationComplete,
  userProfile,
}

class ReferenceFlowApp extends StatefulWidget {
  const ReferenceFlowApp({
    super.key,
    this.disasterScreenBuilder,
    this.sensorPinScreenBuilder,
    this.airGradientLocalScreenBuilder,
  });

  final Widget? Function(
    BuildContext context,
    int tabIndex,
    VoidCallback onOpenLocation,
    VoidCallback onExitDisaster,
  )? disasterScreenBuilder;
  final Widget? Function(
    BuildContext context,
    VoidCallback onBack,
    VoidCallback onNext,
    VoidCallback onRetryAutoDetect,
  )? sensorPinScreenBuilder;
  final Widget? Function(
    BuildContext context,
    VoidCallback onBack,
  )? airGradientLocalScreenBuilder;

  @override
  State<ReferenceFlowApp> createState() => _ReferenceFlowAppState();
}

class _ReferenceFlowAppState extends State<ReferenceFlowApp> {
  static const _forceOnboarding = bool.fromEnvironment('FORCE_ONBOARDING');

  _FlowArea _area = _FlowArea.setup;
  final List<_DetailPage> _detailStack = [];
  int _setupIndex = 1;
  int _plugSetupIndex = 0;
  int _mainTab = 0;
  int _detailInitialMetricIndex = 0;
  int _healthTab = 0;
  int _plugView = 0;
  int _disasterTab = 0;
  bool _initialAreaResolved = false;
  bool _setupLaunchedFromMain = false;
  bool _notificationOpenSubscribed = false;
  StreamSubscription<PushNotificationOpenIntent>? _notificationOpenSub;

  bool get _inDetail => _detailStack.isNotEmpty;
  bool get _showMainNav => !_inDetail && _area == _FlowArea.main;
  bool get _showDisasterNav => !_inDetail && _area == _FlowArea.disaster;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_notificationOpenSubscribed) {
      _notificationOpenSubscribed = true;
      final push = context.read<PushNotificationServiceV2>();
      _notificationOpenSub =
          push.openedMessages.listen(_handleNotificationOpen);
      final pending = push.consumePendingOpenIntent();
      if (pending != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleNotificationOpen(pending);
        });
      }
    }

    if (_initialAreaResolved) {
      return;
    }

    _initialAreaResolved = true;
    if (_forceOnboarding) {
      _area = _FlowArea.setup;
      _setupIndex = 1;
      return;
    }
    final binding = context.read<DeviceBindingControllerV2>().value;
    if (binding.isBound) {
      _area = _FlowArea.main;
      _setupIndex = _setupScreenCount - 1;
    }
  }

  @override
  void dispose() {
    _notificationOpenSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: const Color(0xFF0B0F12),
        body: DesignFrame(
          child: _FlowStage(
            hotspots: _hotspots,
            showMainNav: _showMainNav,
            mainTab: _mainTab,
            showDisasterNav: _showDisasterNav,
            disasterTab: _disasterTab,
            onMainTab: _goMainTab,
            onDisasterTab: _goDisasterTab,
            child: _currentScreen,
          ),
        ),
      ),
    );
  }

  Widget get _currentScreen {
    if (_inDetail) {
      return _detailScreen(_detailStack.last);
    }

    switch (_area) {
      case _FlowArea.setup:
        return _setupScreen;
      case _FlowArea.plugSetup:
        return _plugSetupScreen;
      case _FlowArea.main:
        return _mainScreen;
      case _FlowArea.disaster:
        return _disasterScreen;
    }
  }

  Widget get _mainScreen {
    switch (_mainTab) {
      case 0:
        return MainDashboardScreen(
          onLocationSettings: () => _pushDetail(_DetailPage.mainLocation),
          onNotifications: () => _pushDetail(_DetailPage.alertSettings),
          onDisasterMode: _enterDisaster,
          onProfile: () => _pushDetail(_DetailPage.userProfile),
          onConnectSensor: _restartSensorSetup,
          onMetricSelected: _openDetailMetric,
        );
      case 1:
        return DataLoggingScreen(
          initialMetricIndex: _detailInitialMetricIndex,
          onConnectSensor: _restartSensorSetup,
          onProfile: () => _pushDetail(_DetailPage.userProfile),
        );
      case 2:
        return switch (_healthTab) {
          1 => HealthSeniorScreen(
              onTabSelected: _goHealthTab,
              onProfile: () => _pushDetail(_DetailPage.userProfile),
            ),
          2 => HealthPurificationScreen(
              onTabSelected: _goHealthTab,
              onProfile: () => _pushDetail(_DetailPage.userProfile),
            ),
          _ => HealthChildScreen(
              onTabSelected: _goHealthTab,
              onProfile: () => _pushDetail(_DetailPage.userProfile),
            ),
        };
      case 3:
        return ComparisonNormalScreen(
          onTabSelected: _goComparisonRootTab,
          onConnectSensor: _restartSensorSetup,
          onLocationSettings: () => _pushDetail(_DetailPage.mainLocation),
          onProfile: () => _pushDetail(_DetailPage.userProfile),
        );
      case 4:
        return _plugView == 0
            ? SmartPlugSettingsScreen(
                onRegisterPlug: _enterPlugSetup,
                onAdvancedControl: () => setState(() => _plugView = 1),
                onProfile: () => _pushDetail(_DetailPage.userProfile),
              )
            : ControlHysteresisScreen(
                onBack: () => setState(() => _plugView = 0),
              );
      case 5:
      default:
        return NotificationsScreen(
          onAlertSettings: () => _pushDetail(_DetailPage.alertSettings),
          onLocationSettings: () => _pushDetail(_DetailPage.mainLocation),
          onConnectSensor: _restartSensorSetup,
          onPlugSettings: () => _goMainTab(4),
          onAirGradientSettings: () =>
              _pushDetail(_DetailPage.airGradientLocal),
          onProfile: () => _pushDetail(_DetailPage.userProfile),
        );
    }
  }

  Widget get _disasterScreen {
    final override = widget.disasterScreenBuilder?.call(
      context,
      _disasterTab,
      () => _pushDetail(_DetailPage.mainLocation),
      _exitDisaster,
    );
    if (override != null) {
      return override;
    }

    switch (_disasterTab) {
      case 0:
        return const SafetyDashboardScreen();
      case 1:
        return const AnomalyAnalysisScreen();
      case 2:
        return const SituationBroadcastScreen();
      case 3:
        return const ConnectedDevicesScreen();
      case 4:
      default:
        return const SystemSettingsExtendedScreen();
    }
  }

  Widget get _plugSetupScreen {
    return switch (_plugSetupIndex) {
      0 => PlugPowerScreen(onBack: _goBack, onNext: _nextPlugSetup),
      1 => PlugWifiScreen(onBack: _goBack, onNext: _nextPlugSetup),
      2 => PlugInternetScreen(onBack: _goBack, onNext: _nextPlugSetup),
      _ => PlugCompleteScreen(
          onBack: _goBack,
          onDone: _nextPlugSetup,
          onAddMore: () => setState(() => _plugSetupIndex = 0),
        ),
    };
  }

  Widget get _setupScreen {
    return switch (_setupIndex) {
      0 => SplashScreen(onTap: _nextSetup),
      1 => WelcomeScreen(onStart: _nextSetup),
      2 => OnboardingBatteryScreen(
          onBack: _goBack,
          onNext: _nextSetup,
          onSkip: _nextSetup,
        ),
      3 => OnboardingLocationScreen(
          onBack: _goBack,
          onNext: _nextSetup,
          onSkip: _nextSetup,
        ),
      4 => OnboardingNotificationsScreen(
          onBack: _goBack,
          onNext: _nextSetup,
          onSkip: _nextSetup,
        ),
      5 => SensorPrepScreen(onBack: _goBack, onNext: _nextSetup),
      6 => SensorPowerScreen(onBack: _goBack, onNext: _nextSetup),
      7 => SensorWifiScreen(onBack: _goBack, onNext: _nextSetup),
      8 => SensorInternetScreen(onBack: _goBack, onNext: _nextSetup),
      9 => SensorModeScreen(
          onBack: _goBack,
          onNext: _nextSetup,
          onManualPin: () => _goSetupIndex(11),
        ),
      10 => SensorAutoDetectScreen(
          onBack: _goBack,
          onNext: _completeSensorSetup,
          onManualPin: () => _goSetupIndex(11),
        ),
      11 => widget.sensorPinScreenBuilder?.call(
            context,
            () => _goSetupIndex(9),
            _completeSensorSetup,
            () => _goSetupIndex(10),
          ) ??
          SensorPinScreen(
            onBack: () => _goSetupIndex(9),
            onNext: _completeSensorSetup,
            onRetryAutoDetect: () => _goSetupIndex(10),
          ),
      _ => SensorCompleteScreen(
          onBack: _goBack,
          onDone: _finishSensorSetupWithLocation,
        ),
    };
  }

  Widget _detailScreen(_DetailPage page) {
    switch (page) {
      case _DetailPage.mainLocation:
        return LocationSettingsScreen(onBack: _goBack, onConfirm: _goBack);
      case _DetailPage.alertSettings:
        return AlertSettingsScreen(onBack: _goBack);
      case _DetailPage.plugAdvanced:
        return ControlHysteresisScreen(onBack: _goBack);
      case _DetailPage.disasterSpace:
        return const SpaceSensorManagementScreen();
      case _DetailPage.disasterRules:
        return const AutoControlRulesScreen();
      case _DetailPage.disasterHistory:
        return const IncidentHistoryScreen();
      case _DetailPage.sensorOverview:
        return const SensorLocationOverviewScreen();
      case _DetailPage.sensorSettings:
        return const SensorSettingsScreen();
      case _DetailPage.airGradientLocal:
        return widget.airGradientLocalScreenBuilder?.call(context, _goBack) ??
            const SensorSettingsScreen();
      case _DetailPage.disasterDeviceConnection:
        return const DisasterDeviceConnectionScreen();
      case _DetailPage.locationSearch:
        return const SensorLocationSearchBeforeScreen();
      case _DetailPage.locationMap:
        return const SensorLocationMapSelectScreen();
      case _DetailPage.locationResults:
        return const SensorLocationSearchResultsScreen();
      case _DetailPage.locationDetailInput:
        return const SensorLocationDetailInputScreen();
      case _DetailPage.locationComplete:
        return const SensorLocationCompleteScreen();
      case _DetailPage.userProfile:
        return UserProfileScreen(onBack: _goBack);
    }
  }

  List<_Hotspot> get _hotspots {
    if (_inDetail) {
      return _area == _FlowArea.main
          ? const <_Hotspot>[]
          : _detailHotspots(_detailStack.last);
    }

    switch (_area) {
      case _FlowArea.setup:
        return _setupHotspots;
      case _FlowArea.plugSetup:
        return const <_Hotspot>[];
      case _FlowArea.main:
        return _mainHotspots;
      case _FlowArea.disaster:
        return _disasterHotspots;
    }
  }

  List<_Hotspot> get _setupHotspots {
    return const <_Hotspot>[];
  }

  // ignore: unused_element
  List<_Hotspot> get _mainHotspots {
    return const <_Hotspot>[];
  }

  List<_Hotspot> get _disasterHotspots => const <_Hotspot>[];

  List<_Hotspot> _detailHotspots(_DetailPage page) {
    return [
      _Hotspot(
        rect: const Rect.fromLTWH(0, 0, 96, 84),
        label: '이전',
        onTap: _goBack,
      ),
      if (page == _DetailPage.sensorOverview)
        _Hotspot(
          rect: const Rect.fromLTWH(24, 724, 342, 98),
          label: '위치 등록 시작',
          onTap: () => _replaceDetail(_DetailPage.locationSearch),
        ),
      if (page == _DetailPage.locationSearch) ...[
        _Hotspot(
          rect: const Rect.fromLTWH(24, 196, 342, 86),
          label: '지도에서 선택',
          onTap: () => _replaceDetail(_DetailPage.locationMap),
        ),
        _Hotspot(
          rect: const Rect.fromLTWH(24, 724, 342, 98),
          label: '검색',
          onTap: () => _replaceDetail(_DetailPage.locationResults),
        ),
      ],
      if (page == _DetailPage.locationMap)
        _Hotspot(
          rect: const Rect.fromLTWH(24, 724, 342, 98),
          label: '이 위치로 설정',
          onTap: () => _replaceDetail(_DetailPage.locationDetailInput),
        ),
      if (page == _DetailPage.locationResults)
        _Hotspot(
          rect: const Rect.fromLTWH(24, 184, 342, 312),
          label: '검색 결과 선택',
          onTap: () => _replaceDetail(_DetailPage.locationDetailInput),
        ),
      if (page == _DetailPage.locationDetailInput)
        _Hotspot(
          rect: const Rect.fromLTWH(24, 724, 342, 98),
          label: '등록 완료',
          onTap: () => _replaceDetail(_DetailPage.locationComplete),
        ),
      if (page == _DetailPage.locationComplete)
        _Hotspot(
          rect: const Rect.fromLTWH(24, 724, 342, 98),
          label: '대시보드로 이동',
          onTap: () {
            setState(() {
              _detailStack.clear();
              _area = _FlowArea.disaster;
              _disasterTab = 0;
            });
          },
        ),
    ];
  }

  void _nextSetup() {
    setState(() {
      if (_setupIndex < _setupScreenCount - 1) {
        _setupIndex += 1;
      } else {
        _area = _FlowArea.main;
        _mainTab = 0;
        _setupLaunchedFromMain = false;
      }
    });
  }

  void _completeSensorSetup() {
    setState(() => _setupIndex = _setupScreenCount - 1);
  }

  void _finishSensorSetupWithLocation() {
    setState(() {
      _area = _FlowArea.main;
      _mainTab = 0;
      _setupLaunchedFromMain = false;
      _detailStack
        ..clear()
        ..add(_DetailPage.mainLocation);
    });
  }

  void _enterPlugSetup() {
    setState(() {
      _area = _FlowArea.plugSetup;
      _plugSetupIndex = 0;
      _detailStack.clear();
    });
  }

  void _nextPlugSetup() {
    setState(() {
      if (_plugSetupIndex < _plugSetupCount - 1) {
        _plugSetupIndex += 1;
      } else {
        _area = _FlowArea.main;
        _mainTab = 4;
        _plugSetupIndex = 0;
        _plugView = 0;
      }
    });
  }

  void _goMainTab(int index) {
    if (index == 6) {
      _enterDisaster();
      return;
    }

    setState(() {
      _area = _FlowArea.main;
      _mainTab = index;
      _detailStack.clear();
    });
  }

  void _openDetailMetric(int metricIndex) {
    setState(() {
      _area = _FlowArea.main;
      _mainTab = 1;
      _detailInitialMetricIndex = metricIndex;
      _detailStack.clear();
    });
  }

  void _goHealthTab(int index) {
    setState(() => _healthTab = index);
  }

  void _goComparisonRootTab(int index) {
    setState(() {
      _mainTab = switch (index) {
        0 => 0,
        1 => 1,
        2 => 2,
        _ => 3,
      };
      if (index == 2) _healthTab = 0;
    });
  }

  void _restartSensorSetup() {
    setState(() {
      _area = _FlowArea.setup;
      _setupIndex = 5;
      _setupLaunchedFromMain = true;
      _detailStack.clear();
    });
  }

  void _goSetupIndex(int index) {
    setState(() {
      if (index < 0) {
        _setupIndex = 0;
      } else if (index >= _setupScreenCount) {
        _setupIndex = _setupScreenCount - 1;
      } else {
        _setupIndex = index;
      }
    });
  }

  void _enterDisaster() {
    setState(() {
      _area = _FlowArea.disaster;
      _disasterTab = 0;
      _detailStack.clear();
    });
  }

  void _exitDisaster() {
    setState(() {
      _area = _FlowArea.main;
      _mainTab = 0;
      _detailStack.clear();
    });
  }

  void _goDisasterTab(int index) {
    setState(() {
      _area = _FlowArea.disaster;
      _disasterTab = index;
      _detailStack.clear();
    });
  }

  void _handleNotificationOpen(PushNotificationOpenIntent intent) {
    if (!mounted) return;

    if (intent.type == 'fire_risk') {
      _enterDisaster();
      return;
    }

    final metricIndex = switch (intent.type) {
      'pm25_high' => 0,
      'co2_high' => 1,
      'tvoc_high' => 2,
      'nox_high' => 3,
      _ => null,
    };
    if (metricIndex != null) {
      _openDetailMetric(metricIndex);
      return;
    }

    final healthTab = switch (intent.type) {
      'cardio_low' ||
      'sleep_quality_low' ||
      'apparent_temp_morning' ||
      'apparent_temp_evening' =>
        1,
      'mold_risk' => 2,
      'respiratory_low' || 'infection_risk' || 'focus_poor' => 0,
      _ => null,
    };
    if (healthTab != null) {
      setState(() {
        _area = _FlowArea.main;
        _mainTab = 2;
        _healthTab = healthTab;
        _detailStack.clear();
      });
      return;
    }

    setState(() {
      _area = _FlowArea.main;
      _mainTab = 5;
      _detailStack
        ..clear()
        ..add(_DetailPage.alertSettings);
    });
  }

  void _pushDetail(_DetailPage page) {
    setState(() => _detailStack.add(page));
  }

  void _replaceDetail(_DetailPage page) {
    setState(() {
      if (_detailStack.isNotEmpty) _detailStack.removeLast();
      _detailStack.add(page);
    });
  }

  void _goBack() {
    setState(() {
      if (_detailStack.isNotEmpty) {
        _detailStack.removeLast();
      } else if (_area == _FlowArea.plugSetup) {
        if (_plugSetupIndex > 0) {
          _plugSetupIndex -= 1;
        } else {
          _area = _FlowArea.main;
          _mainTab = 4;
        }
      } else if (_area == _FlowArea.disaster) {
        _area = _FlowArea.main;
        _mainTab = 0;
      } else if (_area == _FlowArea.setup && _setupIndex > 0) {
        if (_setupLaunchedFromMain && _setupIndex <= 5) {
          _area = _FlowArea.main;
          _mainTab = 0;
          _setupLaunchedFromMain = false;
        } else {
          _setupIndex -= 1;
        }
      }
    });
  }
}

class _FlowStage extends StatelessWidget {
  const _FlowStage({
    required this.child,
    required this.hotspots,
    required this.showMainNav,
    required this.mainTab,
    required this.showDisasterNav,
    required this.disasterTab,
    required this.onMainTab,
    required this.onDisasterTab,
  });

  final Widget child;
  final List<_Hotspot> hotspots;
  final bool showMainNav;
  final int mainTab;
  final bool showDisasterNav;
  final int disasterTab;
  final ValueChanged<int> onMainTab;
  final ValueChanged<int> onDisasterTab;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        for (final hotspot in hotspots)
          Positioned.fromRect(
            rect: hotspot.rect,
            child: Semantics(
              label: hotspot.label,
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: hotspot.onTap,
                  splashColor: CleanColors.primaryContainer.withValues(
                    alpha: 0.08,
                  ),
                  highlightColor: CleanColors.primaryContainer.withValues(
                    alpha: 0.04,
                  ),
                ),
              ),
            ),
          ),
        if (showMainNav)
          _FlowBottomNav(
            labels: const ['메인', '상세', '건강', '비교', '플러그', '설정', '방재'],
            icons: const [
              Symbols.dashboard,
              Symbols.analytics,
              Symbols.health_and_safety,
              Symbols.compare_arrows,
              Symbols.settings_input_component,
              Symbols.settings,
              Symbols.shield,
            ],
            activeIndex: mainTab,
            onTap: onMainTab,
          ),
        if (showDisasterNav)
          _FlowBottomNav(
            labels: const ['홈', '분석', '상황 전파', '방재 대비', '설정'],
            icons: const [
              Symbols.dashboard,
              Symbols.analytics,
              Symbols.campaign,
              Symbols.settings_remote,
              Symbols.settings,
            ],
            activeIndex: disasterTab,
            onTap: onDisasterTab,
          ),
      ],
    );
  }
}

class _FlowBottomNav extends StatelessWidget {
  const _FlowBottomNav({
    required this.labels,
    required this.icons,
    required this.activeIndex,
    required this.onTap,
  });

  final List<String> labels;
  final List<IconData> icons;
  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 108,
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 18),
            color: Colors.white.withValues(alpha: 0.94),
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Tooltip(
                      message: labels[i],
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => onTap(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          height: 74,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: i == activeIndex
                                ? CleanColors.primaryFixed
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                icons[i],
                                size: 22,
                                fill: i == activeIndex ? 1 : 0,
                                color: i == activeIndex
                                    ? CleanColors.primary
                                    : CleanColors.outline,
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  labels[i],
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: i == activeIndex
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                    color: i == activeIndex
                                        ? CleanColors.primary
                                        : CleanColors.outline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hotspot {
  const _Hotspot({
    required this.rect,
    required this.label,
    required this.onTap,
  });

  final Rect rect;
  final String label;
  final VoidCallback onTap;
}

const _setupScreenCount = 13;
const _plugSetupCount = 4;
