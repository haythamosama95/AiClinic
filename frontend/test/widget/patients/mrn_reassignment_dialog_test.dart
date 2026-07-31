import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/features/patients/presentation/pages/mrn_reassignment_dialog.dart';

import '../../helpers/patient_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import 'patients_widget_test_harness.dart';

const _patientId = patientsTestPatientId;
const _currentMrn = 'MRN-000001';
const _mrnFormatHint = 'MRN-NNNNNN';
const _mrnExistsMessage = 'Another patient already uses this MRN.';

class _MrnDialogHost extends StatelessWidget {
  const _MrnDialogHost();

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => MrnReassignmentDialog.show(
        context,
        patientId: _patientId,
        currentMrn: _currentMrn,
      ),
      child: const Text('Open reassign dialog'),
    );
  }
}

class _SpyReassignPatientRepository extends FakePatientRepository {
  _SpyReassignPatientRepository({
    this.reassignDelay = Duration.zero,
    this.reassignError,
  });

  final Duration reassignDelay;
  final Object? reassignError;

  var reassignCallCount = 0;
  String? lastPatientId;
  String? lastNewMrn;

  @override
  Future<String> reassignPatientMrn({
    required String patientId,
    required String newMrn,
  }) async {
    reassignCallCount++;
    lastPatientId = patientId;
    lastNewMrn = newMrn;

    if (reassignDelay > Duration.zero) {
      await Future<void>.delayed(reassignDelay);
    }
    if (reassignError != null) {
      throw reassignError!;
    }
    return newMrn;
  }
}

Finder _mrnField() {
  return find.descendant(
    of: find.bySemanticsIdentifier('reassign-mrn'),
    matching: find.byType(TextField),
  );
}

AppButton _saveButton(WidgetTester tester) {
  return tester.widget<AppButton>(find.widgetWithText(AppButton, 'Save'));
}

Future<void> _openDialog(
  WidgetTester tester, {
  FakePatientRepository? patientRepo,
  Set<String>? permissions,
}) async {
  await pumpPatientsDialogShell(
    tester,
    permissions: permissions ?? patientsWithReassignMrnPermission(),
    overrides: patientsProviderOverrides(patientRepo: patientRepo),
    home: const _MrnDialogHost(),
  );
  await pumpPatientsFrames(tester);

  await tester.tap(find.text('Open reassign dialog'));
  await pumpPatientsFrames(tester);
}

void main() {
  group('MrnReassignmentDialog', () {
    testWidgets('trivial: renders MRN field, Cancel, and Save', (tester) async {
      await _openDialog(tester);

      expect(find.bySemanticsIdentifier('reassign-mrn'), findsOneWidget);
      expect(find.text('Medical record number'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Save'), findsOneWidget);
      expect(find.text('Reassign MRN'), findsOneWidget);
    });

    testWidgets('trivial: Save stays disabled until MRN changes to a valid value', (tester) async {
      await _openDialog(tester);

      expect(_saveButton(tester).onPressed, isNull);

      await tester.enterText(_mrnField(), _currentMrn);
      await pumpPatientsFrames(tester);
      expect(_saveButton(tester).onPressed, isNull);

      await tester.enterText(_mrnField(), 'MRN-000099');
      await pumpPatientsFrames(tester);
      expect(_saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('advanced: saving invokes reassign use case with trimmed MRN', (tester) async {
      final repo = _SpyReassignPatientRepository();

      await _openDialog(tester, patientRepo: repo);

      await tester.enterText(_mrnField(), '  MRN-000099  ');
      await pumpPatientsFrames(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await pumpPatientsFrames(tester);

      expect(repo.reassignCallCount, 1);
      expect(repo.lastPatientId, _patientId);
      expect(repo.lastNewMrn, 'MRN-000099');
    });

    testWidgets('advanced: MRN_EXISTS failure renders inline field error', (tester) async {
      final repo = _SpyReassignPatientRepository(
        reassignError: RpcFailure(
          const RpcResult(success: false, errorCode: 'MRN_EXISTS'),
        ),
      );

      await _openDialog(tester, patientRepo: repo);

      await tester.enterText(_mrnField(), 'MRN-000099');
      await pumpPatientsFrames(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await pumpPatientsFrames(tester);

      expect(find.text(_mrnExistsMessage), findsOneWidget);
      expect(repo.reassignCallCount, 1);
    });

    testWidgets('advanced: INVALID_INPUT failure renders inline format hint', (tester) async {
      final repo = _SpyReassignPatientRepository(
        reassignError: RpcFailure(
          const RpcResult(
            success: false,
            errorCode: 'INVALID_INPUT',
            errorMessage: 'Bad format',
          ),
        ),
      );

      await _openDialog(tester, patientRepo: repo);

      await tester.enterText(_mrnField(), 'MRN-000099');
      await pumpPatientsFrames(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await pumpPatientsFrames(tester);

      expect(find.text(_mrnFormatHint), findsWidgets);
      expect(repo.reassignCallCount, 1);
    });

    testWidgets('advanced: submission disables field and shows Save loading state', (tester) async {
      final repo = _SpyReassignPatientRepository(
        reassignDelay: const Duration(milliseconds: 500),
      );

      await _openDialog(tester, patientRepo: repo);

      await tester.enterText(_mrnField(), 'MRN-000099');
      await pumpPatientsFrames(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await tester.pump();

      final input = tester.widget<AppTextInput>(find.byType(AppTextInput));
      expect(input.disabled, isTrue);
      expect(_saveButton(tester).loading, isTrue);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });

    testWidgets('advanced: Cancel dismisses without invoking reassign use case', (tester) async {
      final repo = _SpyReassignPatientRepository();

      await _openDialog(tester, patientRepo: repo);

      await tester.enterText(_mrnField(), 'MRN-000099');
      await pumpPatientsFrames(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await pumpPatientsFrames(tester);

      expect(repo.reassignCallCount, 0);
      expect(find.text('Reassign MRN'), findsNothing);
    });

    testWidgets('edge case: requires patients.reassign_mrn permission in session', (tester) async {
      await pumpPatientsDialogShell(
        tester,
        permissions: RolePermissionSeed.administrator,
        home: const _MrnDialogHost(),
      );
      await pumpPatientsFrames(tester);

      final container = patientsProviderContainer(tester);
      expect(
        container.read(permissionServiceProvider).canReassignPatientMrn(),
        isFalse,
      );

      await pumpPatientsDialogShell(
        tester,
        permissions: patientsWithReassignMrnPermission(),
        home: const _MrnDialogHost(),
      );
      await pumpPatientsFrames(tester);

      final grantedContainer = patientsProviderContainer(tester);
      expect(
        grantedContainer.read(permissionServiceProvider).canReassignPatientMrn(),
        isTrue,
      );
    });
  });
}
