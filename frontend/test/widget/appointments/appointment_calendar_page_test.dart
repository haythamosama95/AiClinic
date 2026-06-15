import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

void main() {
  Future<void> pumpCalendar(WidgetTester tester, {required Set<String> permissions}) async {
    final authState = AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(permissions: permissions),
    );

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(authState)),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(AppointmentRpcTestClient())),
          listBranchesUseCaseProvider.overrideWith((ref) => ListBranches(_StubBranchRepository())),
          listStaffUseCaseProvider.overrideWith((ref) => ListStaff(_StubStaffRepository())),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: const Scaffold(body: AppointmentCalendarPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('AppointmentCalendarPage', () {
    testWidgets('shows permission denied without appointment access', (tester) async {
      await pumpCalendar(tester, permissions: {PermissionKeys.patientsView});

      expect(find.text('You do not have permission to view appointments.'), findsOneWidget);
    });

    testWidgets('renders view controls when appointment access granted', (tester) async {
      await pumpCalendar(tester, permissions: {PermissionKeys.appointmentsRead});

      expect(find.text('Branch'), findsOneWidget);
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.byType(SfCalendar), findsOneWidget);
    });
  });
}

class _StubBranchRepository implements BranchRepository {
  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    return [
      BranchListItem(
        id: '00000000-0000-4000-8000-000000000001',
        name: 'Main',
        code: 'M1',
        isActive: true,
        workingSchedule: BranchWorkingSchedule.defaultSchedule(),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubStaffRepository implements StaffAdminRepository {
  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
