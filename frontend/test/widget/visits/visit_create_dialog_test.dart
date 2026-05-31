import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/visit_create_dialog.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';

import '../../support/visit_rpc_test_client.dart';

void main() {
  group('VisitCreateDialog', () {
    testWidgets('trivial: shows doctor picker when appointment has no doctor', (tester) async {
      await _openDialog(tester, item: _item(doctorId: null));

      expect(find.byKey(const Key('visit_create_dialog')), findsOneWidget);
      expect(find.byKey(const Key('doctor_selector')), findsOneWidget);
    });

    testWidgets('trivial: hides doctor picker when doctor assigned', (tester) async {
      await _openDialog(
        tester,
        item: _item(doctorId: 'doc-1', doctorName: 'Dr Ada'),
      );

      expect(find.byKey(const Key('doctor_selector')), findsNothing);
      expect(find.textContaining('Dr Ada'), findsOneWidget);
    });

    testWidgets('stupid usage: blocks submit without doctor selection', (tester) async {
      await _openDialog(tester, item: _item(doctorId: null));

      await tester.tap(find.byKey(const Key('visit_create_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('visit_create_error')), findsOneWidget);
      expect(find.textContaining('Select a doctor'), findsOneWidget);
    });

    testWidgets('advanced: successful create pops result', (tester) async {
      CreateVisitResult? created;
      final client = VisitRpcTestClient();

      await _openDialog(
        tester,
        item: _item(doctorId: 'doc-1', doctorName: 'Dr Ada'),
        client: client,
        onResult: (value) => created = value,
      );

      await tester.tap(find.byKey(const Key('visit_create_confirm')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'create_visit');
      expect(created, isNotNull);
      expect(created!.visitId, 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
    });

    testWidgets('invalid state: eligibility error shown from RPC', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'create_visit': {'success': false, 'error_code': 'APPOINTMENT_NOT_ELIGIBLE', 'error_message': 'Not eligible'},
        },
      );

      await _openDialog(
        tester,
        item: _item(doctorId: 'doc-1', doctorName: 'Dr Ada'),
        client: client,
      );

      await tester.tap(find.byKey(const Key('visit_create_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('visit_create_error')), findsOneWidget);
      expect(find.textContaining('checked-in'), findsOneWidget);
    });

    testWidgets('edge case: cancel closes without result', (tester) async {
      CreateVisitResult? created;

      await _openDialog(
        tester,
        item: _item(doctorId: 'doc-1'),
        onResult: (value) => created = value,
      );

      await tester.tap(find.byKey(const Key('visit_create_cancel')));
      await tester.pumpAndSettle();

      expect(created, isNull);
    });
  });
}

Future<void> _openDialog(
  WidgetTester tester, {
  required AppointmentListItem item,
  VisitRpcTestClient? client,
  ValueChanged<CreateVisitResult?>? onResult,
}) async {
  await tester.pumpWidget(_host(item: item, client: client, onResult: onResult));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

AppointmentListItem _item({String? doctorId, String? doctorName}) {
  final start = DateTime.now();
  return AppointmentListItem(
    id: 'appt-1',
    patientId: 'patient-1',
    patientName: 'Jane Doe',
    doctorId: doctorId,
    doctorName: doctorName,
    startTime: start,
    endTime: start.add(const Duration(minutes: 30)),
    type: AppointmentType.planned,
    status: AppointmentStatus.checkedIn,
  );
}

Widget _host({
  required AppointmentListItem item,
  VisitRpcTestClient? client,
  ValueChanged<CreateVisitResult?>? onResult,
}) {
  return ProviderScope(
    overrides: [
      visitRepositoryProvider.overrideWith((ref) => VisitRepository(client ?? VisitRpcTestClient())),
      staffAdminRepositoryProvider.overrideWithValue(_VisitDialogStaffRepo()),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  final result = await VisitCreateDialog.show(context, item: item);
                  onResult?.call(result);
                },
                child: const Text('Open'),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _VisitDialogStaffRepo implements StaffAdminRepository {
  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    return const [StaffListItem(id: 'doc-1', fullName: 'Dr Ada', role: StaffRole.doctor, isActive: true)];
  }

  @override
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) => throw UnimplementedError();

  @override
  Future<bool> organizationHasOwner() => throw UnimplementedError();

  @override
  Future<String> updateStaffMember(UpdateStaffMemberInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) =>
      throw UnimplementedError();
}
