import 'package:ai_clinic/app/app.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import 'package:ai_clinic/app/services/startup_health_service.dart';
import 'package:ai_clinic/core/auth/idle_timeout_service.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability_reader.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/queue/presentation/providers/queue_provider.dart';
import 'package:ai_clinic/features/settings/data/idle_timeout_preferences_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/startup_test_support.dart';
import 'ai_surface_test_harness.dart';

void main() {
  group('E2E-P6.1-02', () {
    testWidgets('E2E-P6.1-02 resume and next_change_at timer refresh status via backend RPC only', (tester) async {
      final reader = _ShellStatusReaderSpy();

      await tester.pumpWidget(
        ProviderScope(
          overrides: _appOverrides(statusReader: reader),
          child: const AiClinicApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      final readsBeforeResume = reader.readCallCount;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        reader.readCallCount,
        greaterThan(readsBeforeResume),
        reason: 'AiClinicApp resume should call the one status refresh → SupabaseAiAvailabilityReader.read',
      );
      expect(reader.platformUrls, isEmpty, reason: 'status refresh must contact only the backend');

      reader.nextChangeAt = DateTime.now().add(const Duration(seconds: 2));
      final readsBeforeTimer = reader.readCallCount;
      await tester.pump(const Duration(seconds: 3));

      expect(
        reader.readCallCount,
        greaterThan(readsBeforeTimer),
        reason: 'next_change_at timer should call the one status refresh → SupabaseAiAvailabilityReader.read',
      );
      expect(reader.platformUrls, isEmpty, reason: 'timer refresh must contact only the backend');
    });
  });
}

_appOverrides({
  required _ShellStatusReaderSpy statusReader,
}) {
  return [
    supabaseClientProvider.overrideWithValue(_HarnessSupabaseClient()),
    idleTimeoutPreferencesStoreProvider.overrideWithValue(_FakeIdleStore(const Duration(minutes: 15))),
    idleTimeoutServiceProvider.overrideWith((ref) {
      final idle = IdleTimeoutService(
        idleDuration: const Duration(minutes: 15),
        onIdleTimeout: () {},
      );
      ref.onDispose(idle.dispose);
      return idle;
    }),
    startupSessionProvider.overrideWith(_HarnessStartupNotifier.new),
    authSessionProvider.overrideWith(
      () => _HarnessAuthNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(role: StaffRole.doctor),
        ),
      ),
    ),
    appointmentQueueProvider.overrideWith(_IdleQueueController.new),
    aiShellStatusReaderProvider.overrideWithValue(statusReader),
  ];
}

/// T017 moves this provider beside [AiClinicApp] and calls it from the one shell refresh.
final aiShellStatusReaderProvider = Provider<AiAvailabilityReader>((ref) {
  return SupabaseAiAvailabilityReader(client: ref.watch(supabaseClientProvider));
});

class _FakeIdleStore extends IdleTimeoutPreferencesStore {
  _FakeIdleStore(this.duration);

  final Duration duration;

  @override
  Future<Duration> loadIdleDuration() async => duration;

  @override
  Future<void> saveIdleDuration(Duration duration) async {}
}

class _HarnessStartupNotifier extends StartupSessionNotifier {
  @override
  StartupSessionState build() {
    return StartupSessionState(
      configurationStatus: StartupConfigurationStatus.valid,
      connectivityStatus: StartupConnectivityStatus.healthy,
      currentView: StartupCurrentView.unauthenticatedEntry,
      themeMode: ThemeMode.light,
      deploymentProfile: sampleDeploymentProfile(),
    );
  }

  @override
  Future<void> bootstrap() async {}
}

class _HarnessAuthNotifier extends MutableAuthSessionNotifier {
  _HarnessAuthNotifier(super.initial);

  @override
  Future<void> reloadContext() async {}
}

class _IdleQueueController extends AppointmentQueueController {
  @override
  AppointmentQueueState build() => const AppointmentQueueState(items: []);
}

class _ShellStatusReaderSpy implements AiAvailabilityReader {
  int readCallCount = 0;
  final List<String> platformUrls = [];
  DateTime? nextChangeAt;

  @override
  Future<AiAvailability> read() async {
    readCallCount++;
    return const AiAvailability(
      enrolled: true,
      platformBaseUrl: testPlatformBaseUrl,
    );
  }
}

class _HarnessSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #auth) {
      return _HarnessAuthClient();
    }
    if (invocation.memberName == #realtime) {
      return _HarnessRealtimeClient();
    }
    return null;
  }
}

class _HarnessAuthClient implements GoTrueClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _HarnessRealtimeClient implements RealtimeClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => _HarnessRealtimeChannel();
}

class _HarnessRealtimeChannel implements RealtimeChannel {
  @override
  dynamic noSuchMethod(Invocation invocation) => this;
}
