// Reusable pump helpers and fakes for settings presentation widget tests.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/locale_provider.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/settings/application/format_preferences_notifier.dart';
import 'package:ai_clinic/features/settings/application/idle_timeout_settings_notifier.dart';
import 'package:ai_clinic/features/settings/application/notification_preferences_notifier.dart';
import 'package:ai_clinic/features/settings/data/idle_timeout_preferences_store.dart';
import 'package:ai_clinic/features/settings/data/workstation_preferences_store.dart';
import 'package:ai_clinic/features/settings/domain/format_preferences.dart';
import 'package:ai_clinic/features/settings/domain/notification_preferences.dart';
import 'package:ai_clinic/features/settings/presentation/pages/settings_page.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

/// Matches [_breakpoint] in `settings_page.dart` and `settings_rail.dart`.
const double settingsLayoutBreakpoint = 768;

/// Wide surface so the settings rail and content render side by side.
const Size settingsWideSurfaceSize = Size(1024, 900);

/// Narrow surface so the rail renders as a horizontal strip.
const Size settingsNarrowSurfaceSize = Size(600, 900);

/// In-memory workstation preferences for widget tests.
class FakeWorkstationPreferencesStore extends WorkstationPreferencesStore {
  FakeWorkstationPreferencesStore({
    this.dateFormat = AppDateFormat.defaultValue,
    this.timeFormat = AppTimeFormat.defaultValue,
    NotificationPreferences? notificationPreferences,
    this.delayLoads = false,
  }) : notificationPreferences = notificationPreferences ?? NotificationPreferences.defaults;

  AppDateFormat dateFormat;
  AppTimeFormat timeFormat;
  NotificationPreferences notificationPreferences;
  final bool delayLoads;

  Completer<void>? _loadGate;

  void releaseLoads() {
    _loadGate?.complete();
    _loadGate = null;
  }

  Future<void> _maybeDelay() async {
    if (!delayLoads) {
      return;
    }
    _loadGate ??= Completer<void>();
    await _loadGate!.future;
  }

  @override
  Future<AppDateFormat> loadDateFormat() async {
    await _maybeDelay();
    return dateFormat;
  }

  @override
  Future<void> saveDateFormat(AppDateFormat value) async {
    dateFormat = value;
  }

  @override
  Future<AppTimeFormat> loadTimeFormat() async {
    await _maybeDelay();
    return timeFormat;
  }

  @override
  Future<void> saveTimeFormat(AppTimeFormat value) async {
    timeFormat = value;
  }

  @override
  Future<NotificationPreferences> loadNotificationPreferences() async {
    await _maybeDelay();
    return notificationPreferences;
  }

  @override
  Future<void> saveNotificationPreferences(NotificationPreferences value) async {
    notificationPreferences = value;
  }
}

/// In-memory idle timeout store for widget tests.
class FakeIdleTimeoutPreferencesStore extends IdleTimeoutPreferencesStore {
  FakeIdleTimeoutPreferencesStore({
    this.duration = const Duration(minutes: 15),
    this.delayLoads = false,
  });

  Duration duration;
  final bool delayLoads;
  Completer<void>? _loadGate;

  void releaseLoads() {
    _loadGate?.complete();
    _loadGate = null;
  }

  Future<void> _maybeDelay() async {
    if (!delayLoads) {
      return;
    }
    _loadGate ??= Completer<void>();
    await _loadGate!.future;
  }

  @override
  Future<Duration> loadIdleDuration() async {
    await _maybeDelay();
    return duration;
  }

  @override
  Future<void> saveIdleDuration(Duration value) async {
    duration = value;
  }
}

/// Fixed locale without touching [SharedPreferences].
class FixedLocaleNotifier extends LocaleNotifier {
  FixedLocaleNotifier(this._locale);

  final Locale _locale;

  @override
  Locale build() => _locale;

  @override
  Future<void> setLocale(Locale locale) async {
    state = locale;
  }
}

class _PresetStartupNotifier extends StartupSessionNotifier {
  _PresetStartupNotifier(this.themeMode);

  final ThemeMode themeMode;

  @override
  StartupSessionState build() {
    return StartupSessionState.initial().copyWith(
      configurationStatus: StartupConfigurationStatus.valid,
      currentView: StartupCurrentView.unauthenticatedEntry,
      themeMode: themeMode,
    );
  }
}

FormatPreferencesState defaultFormatPreferencesState() {
  return const FormatPreferencesState(
    dateFormat: AppDateFormat.dmy,
    timeFormat: AppTimeFormat.h12,
  );
}

IdleTimeoutSettingsState defaultIdleTimeoutSettingsState() {
  return const IdleTimeoutSettingsState(duration: Duration(minutes: 15));
}

/// Never completes so [formatPreferencesProvider] stays loading.
class LoadingFormatPreferencesNotifier extends FormatPreferencesNotifier {
  @override
  Future<FormatPreferencesState> build() async {
    return Completer<FormatPreferencesState>().future;
  }
}

/// Never completes so [notificationPreferencesProvider] stays loading.
class LoadingNotificationPreferencesNotifier extends NotificationPreferencesNotifier {
  @override
  Future<NotificationPreferences> build() async {
    return Completer<NotificationPreferences>().future;
  }
}

/// Never completes so [idleTimeoutSettingsProvider] stays loading.
class LoadingIdleTimeoutSettingsNotifier extends IdleTimeoutSettingsNotifier {
  @override
  Future<IdleTimeoutSettingsState> build() async {
    return Completer<IdleTimeoutSettingsState>().future;
  }
}

/// Tracks [FormatPreferencesNotifier] mutations without a backing store.
class SpyFormatPreferencesNotifier extends FormatPreferencesNotifier {
  SpyFormatPreferencesNotifier(this._state);

  final FormatPreferencesState _state;

  var setDateFormatCallCount = 0;
  var setTimeFormatCallCount = 0;
  AppDateFormat? lastDateFormat;
  AppTimeFormat? lastTimeFormat;

  @override
  Future<FormatPreferencesState> build() async => _state;

  @override
  Future<void> setDateFormat(AppDateFormat value) async {
    setDateFormatCallCount++;
    lastDateFormat = value;
    state = AsyncData(_state.copyWith(dateFormat: value));
  }

  @override
  Future<void> setTimeFormat(AppTimeFormat value) async {
    setTimeFormatCallCount++;
    lastTimeFormat = value;
    state = AsyncData(_state.copyWith(timeFormat: value));
  }
}

/// Tracks [NotificationPreferencesNotifier.setPreference] calls.
class SpyNotificationPreferencesNotifier extends NotificationPreferencesNotifier {
  SpyNotificationPreferencesNotifier(this._preferences);

  final NotificationPreferences _preferences;

  var setPreferenceCallCount = 0;
  NotificationPreferenceKey? lastKey;
  bool? lastValue;

  @override
  Future<NotificationPreferences> build() async => _preferences;

  @override
  Future<void> setPreference(NotificationPreferenceKey key, bool value) async {
    setPreferenceCallCount++;
    lastKey = key;
    lastValue = value;
    final current = state.value ?? _preferences;
    final next = switch (key) {
      NotificationPreferenceKey.appointmentReminders => current.copyWith(appointmentReminders: value),
      NotificationPreferenceKey.billingAlerts => current.copyWith(billingAlerts: value),
      NotificationPreferenceKey.labResults => current.copyWith(labResults: value),
      NotificationPreferenceKey.shiftHandoffs => current.copyWith(shiftHandoffs: value),
      NotificationPreferenceKey.productUpdates => current.copyWith(productUpdates: value),
    };
    state = AsyncData(next);
  }
}

/// Tracks [IdleTimeoutSettingsNotifier.selectPresetMinutes] calls.
class SpyIdleTimeoutSettingsNotifier extends IdleTimeoutSettingsNotifier {
  SpyIdleTimeoutSettingsNotifier(this._state);

  final IdleTimeoutSettingsState _state;

  var selectPresetMinutesCallCount = 0;
  int? lastPresetMinutes;

  @override
  Future<IdleTimeoutSettingsState> build() async => _state;

  @override
  Future<void> selectPresetMinutes(int minutes) async {
    selectPresetMinutesCallCount++;
    lastPresetMinutes = minutes;
    state = AsyncData(
      _state.copyWith(
        duration: Duration(minutes: minutes),
        saveMessage: 'Idle timeout set to $minutes minutes.',
      ),
    );
  }
}

List<Override> settingsProviderOverrides({
  FakeWorkstationPreferencesStore? workstationStore,
  FakeIdleTimeoutPreferencesStore? idleTimeoutStore,
  ThemeMode themeMode = ThemeMode.light,
  Locale locale = const Locale('en'),
  FormatPreferencesNotifier? formatNotifier,
  NotificationPreferencesNotifier? notificationNotifier,
  IdleTimeoutSettingsNotifier? idleNotifier,
  Override? formatPreferencesOverride,
  Override? notificationPreferencesOverride,
  Override? idleTimeoutSettingsOverride,
  List<Override> extraOverrides = const [],
}) {
  final overrides = <Override>[
    startupSessionProvider.overrideWith(() => _PresetStartupNotifier(themeMode)),
    localeProvider.overrideWith(() => FixedLocaleNotifier(locale)),
  ];

  if (workstationStore != null) {
    overrides.add(workstationPreferencesStoreProvider.overrideWithValue(workstationStore));
  }

  if (idleTimeoutStore != null) {
    overrides.add(idleTimeoutPreferencesStoreProvider.overrideWithValue(idleTimeoutStore));
  }

  if (formatPreferencesOverride != null) {
    overrides.add(formatPreferencesOverride);
  } else if (formatNotifier != null) {
    overrides.add(formatPreferencesProvider.overrideWith(() => formatNotifier));
  } else if (workstationStore == null) {
    overrides.add(
      formatPreferencesProvider.overrideWith(
        () => SpyFormatPreferencesNotifier(defaultFormatPreferencesState()),
      ),
    );
  }

  if (notificationPreferencesOverride != null) {
    overrides.add(notificationPreferencesOverride);
  } else if (notificationNotifier != null) {
    overrides.add(notificationPreferencesProvider.overrideWith(() => notificationNotifier));
  } else if (workstationStore == null) {
    overrides.add(
      notificationPreferencesProvider.overrideWith(
        () => SpyNotificationPreferencesNotifier(NotificationPreferences.defaults),
      ),
    );
  }

  if (idleTimeoutSettingsOverride != null) {
    overrides.add(idleTimeoutSettingsOverride);
  } else if (idleNotifier != null) {
    overrides.add(idleTimeoutSettingsProvider.overrideWith(() => idleNotifier));
  } else if (idleTimeoutStore == null) {
    overrides.add(
      idleTimeoutSettingsProvider.overrideWith(
        () => SpyIdleTimeoutSettingsNotifier(defaultIdleTimeoutSettingsState()),
      ),
    );
  }

  overrides.addAll(extraOverrides);
  return overrides;
}

GoRouter createSettingsTestRouter({
  String initialLocation = AppRoutes.settingsAppearance,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.settings,
        redirect: (_, _) => AppRoutes.settingsAppearance,
      ),
      GoRoute(
        path: '${AppRoutes.settings}/:screenId',
        builder: (_, state) => SettingsPage(screenId: state.pathParameters['screenId']),
      ),
    ],
  );
}

Widget _settingsTestMediaQuery({required Size surfaceSize, required Widget child}) {
  return MediaQuery(
    data: MediaQueryData(size: surfaceSize, disableAnimations: true),
    child: child,
  );
}

Widget _settingsMaterialApp({required Widget child}) {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

Widget _settingsRouterMaterialApp({required GoRouter router}) {
  return MaterialApp.router(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
  );
}

/// Pumps [child] inside the canonical settings widget-test shell.
Future<void> pumpSettingsWidget(
  WidgetTester tester, {
  required Widget child,
  List<Override> overrides = const [],
  Size surfaceSize = settingsWideSurfaceSize,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: _settingsTestMediaQuery(
        surfaceSize: surfaceSize,
        child: _settingsMaterialApp(
          child: Scaffold(
            body: SizedBox(
              width: surfaceSize.width,
              height: surfaceSize.height,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pumps [SettingsPage] behind a settings [GoRouter].
Future<GoRouter> pumpSettingsPage(
  WidgetTester tester, {
  String initialLocation = AppRoutes.settingsAppearance,
  List<Override> overrides = const [],
  Size surfaceSize = settingsWideSurfaceSize,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = createSettingsTestRouter(initialLocation: initialLocation);

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: _settingsTestMediaQuery(
        surfaceSize: surfaceSize,
        child: _settingsRouterMaterialApp(router: router),
      ),
    ),
  );

  return router;
}

Future<void> pumpSettingsFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> settleSettingsWidget(WidgetTester tester) async {
  await pumpSettingsFrames(tester);
  await tester.pumpAndSettle();
}

ProviderContainer settingsProviderContainer(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Finder settingsRailSection(String label) => find.text(label);

Finder settingsSegmentedOption(String label) => find.text(label);

Finder settingsIdlePresetButton(int minutes) => find.text('$minutes min');

/// Alias used by settings widget tests written against an earlier harness draft.
Future<void> pumpSettingsSurface(
  WidgetTester tester, {
  required Widget child,
  List<Override> overrides = const [],
  Size surfaceSize = settingsWideSurfaceSize,
}) {
  return pumpSettingsWidget(
    tester,
    child: child,
    overrides: overrides,
    surfaceSize: surfaceSize,
  );
}

Future<void> settleSettingsSurface(WidgetTester tester) => settleSettingsWidget(tester);

GoRouter settingsTestRouter({String initialLocation = AppRoutes.settingsAppearance}) {
  return createSettingsTestRouter(initialLocation: initialLocation);
}

Future<void> pumpSettingsRouterSurface(
  WidgetTester tester, {
  required GoRouter router,
  List<Override> overrides = const [],
  Size surfaceSize = settingsWideSurfaceSize,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: _settingsTestMediaQuery(
        surfaceSize: surfaceSize,
        child: _settingsRouterMaterialApp(router: router),
      ),
    ),
  );
}
