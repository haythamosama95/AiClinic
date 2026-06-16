import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

const calendarWidgetSurfaceSize = Size(1280, 900);

/// Bounded pumps for Syncfusion calendar widget tests (never use [pumpAndSettle]).
Future<void> settleCalendarWidgetTest(
  WidgetTester tester, {
  int passes = 2,
  Duration step = const Duration(milliseconds: 300),
}) async {
  for (var i = 0; i < passes; i++) {
    await tester.pump(step);
  }
}

class PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class MutableAuthSessionNotifier extends AuthSessionNotifier {
  MutableAuthSessionNotifier(this._state);

  AuthSessionState _state;

  @override
  AuthSessionState build() => _state;

  void replace(AuthSessionState next) {
    _state = next;
    state = next;
  }
}

Future<void> pumpAppointmentCalendarPage(
  WidgetTester tester, {
  required AuthSessionState authState,
  SupabaseClient? rpcClient,
  CalendarStubBranchRepository? branchRepository,
  CalendarStubStaffRepository? staffRepository,
}) async {
  final client = rpcClient ?? AppointmentRpcTestClient();

  await tester.binding.setSurfaceSize(calendarWidgetSurfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(authState)),
        appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
        listBranchesUseCaseProvider.overrideWith(
          (ref) => ListBranches(branchRepository ?? CalendarStubBranchRepository()),
        ),
        listStaffUseCaseProvider.overrideWith((ref) => ListStaff(staffRepository ?? CalendarStubStaffRepository())),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child!),
        home: const Scaffold(body: AppointmentCalendarPage()),
      ),
    ),
  );
  await tester.pump();
}

AuthSessionState calendarAuthState({
  Set<String> permissions = const {'appointments.read'},
  String? activeBranchId,
  List<String> branchIds = const [calendarTestBranchAId],
}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(permissions: permissions, activeBranchId: activeBranchId, branchIds: branchIds),
  );
}

SfCalendar calendarWidget(WidgetTester tester) {
  return tester.widget<SfCalendar>(find.byType(SfCalendar));
}
