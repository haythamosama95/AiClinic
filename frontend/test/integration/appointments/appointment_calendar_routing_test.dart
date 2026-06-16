import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_item_row.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/startup_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/pump_auth_app.dart';
import '../../widget/appointments/appointment_calendar_test_support.dart';

void main() {
  group('CAL-A01 — calendar routing', () {
    testWidgets('authenticated user reaches AppointmentCalendarPage via shell nav', (tester) async {
      final client = AppointmentRpcTestClient();

      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(
            () => PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.appointmentsRead}),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          listBranchesUseCaseProvider.overrideWith((ref) => ListBranches(CalendarStubBranchRepository())),
          listStaffUseCaseProvider.overrideWith((ref) => ListStaff(CalendarStubStaffRepository())),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.home);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Appointments'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.widgetWithText(ShellNavItemRow, 'Calendar'));
      await tester.pump();
      await settleCalendarWidgetTest(tester);

      expect(find.byType(AppointmentCalendarPage), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.byType(SfCalendar), findsOneWidget);
      expect(find.text('UI Pending Migration'), findsNothing);
      expect(
        container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path,
        AppRoutes.appointmentsCalendar,
      );
    });
  });
}
