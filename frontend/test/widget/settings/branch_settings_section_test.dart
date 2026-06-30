import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/branch_settings_section.dart';

import '../../support/appointment_rpc_test_client.dart';
import '../../support/settings_rpc_test_client.dart';

const _testBranch = BranchListItem(
  id: 'branch-1',
  name: 'Main Branch',
  isActive: true,
  code: 'MAIN',
  address: '123 Street',
  phone: '5551234567',
  mapsUrl: 'https://maps.example.com/main',
);

void main() {
  group('FUNC-I — Settings default appointment duration', () {
    Future<void> pumpSection(
      WidgetTester tester, {
      BranchListItem branch = _testBranch,
      bool canManage = true,
      AppointmentRpcTestClient? appointmentClient,
      SettingsRpcTestClient? branchClient,
      bool settle = true,
    }) async {
      final apptClient = appointmentClient ?? AppointmentRpcTestClient();
      final brClient = branchClient ?? SettingsRpcTestClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(apptClient)),
            branchRepositoryProvider.overrideWithValue(BranchRepositoryImpl(brClient)),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: Scaffold(body: BranchSettingsSection(branch: branch, canManage: canManage)),
          ),
        ),
      );

      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
    }

    /// Flushes Forui [FTappable] press/release animation timers (100 ms each).
    Future<void> tapForuiControl(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 150));
    }

    Future<void> enterEditMode(WidgetTester tester) async {
      await tapForuiControl(tester, find.byTooltip('Edit'));
      await tester.pumpAndSettle();
    }

    Future<void> selectDuration(WidgetTester tester, String label) async {
      await tapForuiControl(tester, find.widgetWithText(AppSelect<int>, 'Default appointment duration'));
      await tester.pumpAndSettle();
      await tapForuiControl(tester, find.text(label).last);
      await tester.pumpAndSettle();
    }

    Future<void> tapSave(WidgetTester tester) async {
      await tapForuiControl(tester, find.widgetWithText(AppButton, 'Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('FUNC-I01: loads current default appointment duration', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['get_appointment_settings'] = {
          'success': true,
          'data': {
            'default_duration_minutes': 45,
            'min_duration_minutes': 5,
            'max_duration_minutes': 240,
          },
        };

      await pumpSection(tester, appointmentClient: client);

      expect(client.rpcLog, contains('get_appointment_settings'));
      expect(client.lastParams?['p_branch_id'], _testBranch.id);
      expect(find.text('45 minutes'), findsOneWidget);
      expect(find.text('Loading…'), findsNothing);
    });

    testWidgets('FUNC-I02: save duration calls set_appointment_default_duration', (tester) async {
      final apptClient = AppointmentRpcTestClient();
      final branchClient = SettingsRpcTestClient();

      await pumpSection(tester, appointmentClient: apptClient, branchClient: branchClient);
      await enterEditMode(tester);
      await selectDuration(tester, '45 minutes');

      await tapSave(tester);

      expect(apptClient.rpcLog, contains('set_appointment_default_duration'));
      expect(apptClient.lastParams?['p_duration_minutes'], 45);
      expect(apptClient.lastParams?['p_branch_id'], _testBranch.id);
      expect(branchClient.lastFunction, 'update_branch');
      expect(find.text('45 minutes'), findsOneWidget);
      expect(find.widgetWithText(AppSelect<int>, 'Default appointment duration'), findsNothing);
    });

    testWidgets('FUNC-I03: invalid duration save shows validation error', (tester) async {
      final apptClient = AppointmentRpcTestClient()
        ..rpcResults['set_appointment_default_duration'] = {
          'success': false,
          'error_code': 'INVALID_INPUT',
          'error_message': 'Duration must be at least 5 minutes.',
        };

      await pumpSection(tester, appointmentClient: apptClient);
      await enterEditMode(tester);
      await selectDuration(tester, '45 minutes');

      await tapSave(tester);

      expect(find.text('Duration must be at least 5 minutes.'), findsOneWidget);
      expect(find.byType(AppAlert), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Save'), findsOneWidget);
    });

    testWidgets('FUNC-I04: saved 45-minute duration yields 45-minute slot blocks', (tester) async {
      final apptClient = AppointmentRpcTestClient();

      await pumpSection(tester, appointmentClient: apptClient);
      await enterEditMode(tester);
      await selectDuration(tester, '45 minutes');

      await tapSave(tester);

      expect(apptClient.lastParams?['p_duration_minutes'], 45);

      apptClient.rpcResults['get_simplified_booking_slots'] = {
        'success': true,
        'data': {
          'default_duration_minutes': 45,
          'blocks': [
            {
              'start_time': '2026-06-27T10:00:00.000',
              'end_time': '2026-06-27T10:45:00.000',
              'state': 'available',
              'available_doctor_ids': ['doctor-a'],
            },
          ],
        },
      };

      final repository = AppointmentRepository(apptClient);
      final slots = await repository.getSimplifiedBookingSlots(
        branchId: _testBranch.id,
        localDate: DateTime(2026, 6, 27),
        preferredDoctorId: 'doctor-a',
      );

      expect(slots.defaultDurationMinutes, 45);
      expect(slots.blocks.single.endTime.difference(slots.blocks.single.startTime).inMinutes, 45);
    });

    // BE-only: server resolves duration fallback when no setting row.
    testWidgets('FUNC-I05: fallback 30 when no setting row', (_) async {}, skip: true);

    // BE-only: server resolves corrupt json setting fallback.
    testWidgets('FUNC-I06: invalid stored value falls back to 30', (_) async {}, skip: true);

    testWidgets('FUNC-I07: branch scope label shows branch name', (tester) async {
      await pumpSection(tester);

      expect(find.text('Main Branch (MAIN)'), findsOneWidget);
    });

    testWidgets('FUNC-I08: permission gate disables duration field', (tester) async {
      await pumpSection(tester, canManage: false);

      expect(find.text('30 minutes'), findsOneWidget);
      expect(find.text('Default appointment duration'), findsOneWidget);
      expect(find.widgetWithText(AppSelect<int>, 'Default appointment duration'), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);
    });
  });
}
