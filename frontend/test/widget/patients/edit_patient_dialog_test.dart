import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/edit_patient/edit_patient_dialog.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';

import '../../helpers/patient_test_support.dart';
import 'patients_widget_test_harness.dart';

const _patientId = patientsTestPatientId;

const _duplicateCandidate = DuplicateCandidate(
  id: '22222222-2222-4222-8222-222222222222',
  fullName: 'Existing Patient',
  branchName: 'Branch A',
  phone: '2012345678',
);

class _EditDialogLauncher extends StatelessWidget {
  const _EditDialogLauncher();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(
        onPressed: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const EditPatientDialog(patientId: _patientId),
            ),
          );
        },
        child: const Text('open-edit'),
      ),
    );
  }
}

Future<void> _openEditDialog(
  WidgetTester tester, {
  required FakePatientRepository repo,
  PatientDetail? detail,
  List<Override> extraOverrides = const [],
}) async {
  await pumpPatientsDialogShell(
    tester,
    home: const _EditDialogLauncher(),
    overrides: patientsProviderOverrides(
      patientId: _patientId,
      patientDetail: detail ?? samplePatientDetail(id: _patientId),
      patientRepo: repo,
      extraOverrides: extraOverrides,
    ),
  );
  await tester.tap(find.text('open-edit'));
  await pumpPatientsFrames(tester);
}

Finder _editNameField() {
  return find.descendant(
    of: find.bySemanticsIdentifier('edit-patient-fullName'),
    matching: find.byType(TextField),
  );
}

Finder _editPhoneField() {
  return find.descendant(
    of: find.bySemanticsIdentifier('edit-patient-phone'),
    matching: find.byType(TextField),
  );
}

AppButton _saveButton(WidgetTester tester) {
  return tester.widget<AppButton>(find.widgetWithText(AppButton, 'Save changes'));
}

void main() {
  group('EditPatientDialog', () {
    testWidgets('trivial: unhydrated state shows skeleton and disables Save', (tester) async {
      final repo = FakePatientRepository(
        detail: samplePatientDetail(id: _patientId),
      );

      await _openEditDialog(
        tester,
        repo: repo,
        extraOverrides: [
          patientDetailProvider(_patientId).overrideWith(
            (ref) async {
              await Future<void>.delayed(const Duration(seconds: 30));
              return samplePatientDetail(id: _patientId);
            },
          ),
        ],
      );

      expect(find.byType(AppSkeleton), findsWidgets);
      expect(find.bySemanticsIdentifier('edit-patient-fullName'), findsNothing);
      expect(_saveButton(tester).onPressed, isNull);
    });

    testWidgets('advanced: hydrated detail prefills fields and enables Save', (tester) async {
      final detail = samplePatientDetail(
        id: _patientId,
        fullName: 'Hydrated Patient',
        phone: '2012345678',
        notes: 'Allergy noted',
      );
      final repo = FakePatientRepository(detail: detail);

      await _openEditDialog(tester, repo: repo, detail: detail);
      await pumpPatientsFrames(tester);

      expect(find.bySemanticsIdentifier('edit-patient-fullName'), findsOneWidget);
      expect(
        tester.widget<TextField>(_editNameField()).controller?.text,
        'Hydrated Patient',
      );
      expect(
        tester.widget<TextField>(_editPhoneField()).controller?.text,
        contains('123'),
      );
      expect(find.text('Allergy noted'), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('advanced: saving invokes update and closes dialog on success', (tester) async {
      final detail = samplePatientDetail(
        id: _patientId,
        fullName: 'Hydrated Patient',
        phone: '2012345678',
      );
      final repo = FakePatientRepository(detail: detail);

      await _openEditDialog(tester, repo: repo, detail: detail);
      await pumpPatientsFrames(tester);

      await tester.tap(find.widgetWithText(AppButton, 'Save changes'));
      await pumpPatientsFrames(tester);

      expect(repo.lastUpdateInput, isNotNull);
      expect(repo.lastUpdateInput?.patientId, _patientId);
      expect(find.byType(EditPatientDialog), findsNothing);
    });

    testWidgets('advanced: stale update conflict shows Record changed dialog', (tester) async {
      final detail = samplePatientDetail(
        id: _patientId,
        fullName: 'Hydrated Patient',
        phone: '2012345678',
      );
      final repo = FakePatientRepository(
        detail: detail,
        updateException: RpcFailure(
          const RpcResult(
            success: false,
            errorCode: 'STALE_PATIENT',
            errorMessage: 'stale',
          ),
        ),
      );

      await _openEditDialog(tester, repo: repo, detail: detail);
      await pumpPatientsFrames(tester);

      await tester.tap(find.widgetWithText(AppButton, 'Save changes'));
      await pumpPatientsFrames(tester);

      expect(find.text('Record changed'), findsOneWidget);
      expect(
        find.text('This record was modified by someone else. Reload and discard your edits?'),
        findsOneWidget,
      );
      expect(find.widgetWithText(AppButton, 'Keep editing'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Reload'), findsOneWidget);
    });

    testWidgets('advanced: Reload triggers detail re-hydration path', (tester) async {
      final detail = samplePatientDetail(
        id: _patientId,
        fullName: 'Before Reload',
        phone: '2012345678',
      );
      final repo = _MutableDetailPatientRepository(
        initialDetail: detail,
        updateException: RpcFailure(
          const RpcResult(
            success: false,
            errorCode: 'STALE_PATIENT',
            errorMessage: 'stale',
          ),
        ),
      );

      await _openEditDialog(tester, repo: repo, detail: detail);
      await pumpPatientsFrames(tester);

      await tester.tap(find.widgetWithText(AppButton, 'Save changes'));
      await pumpPatientsFrames(tester);

      final callsBeforeReload = repo.getPatientCallCount;

      await tester.tap(find.widgetWithText(AppButton, 'Reload'));
      await pumpPatientsFrames(tester);

      expect(repo.getPatientCallCount, greaterThan(callsBeforeReload));
      expect(find.byType(EditPatientDialog), findsNothing);
    });

    testWidgets('advanced: duplicate dialog surfaces from edit save', (tester) async {
      final detail = samplePatientDetail(
        id: _patientId,
        fullName: 'Hydrated Patient',
        phone: '2012345678',
      );
      final repo = FakePatientRepository(
        detail: detail,
        duplicates: const [_duplicateCandidate],
      );

      await _openEditDialog(tester, repo: repo, detail: detail);
      await pumpPatientsFrames(tester);

      await tester.tap(find.widgetWithText(AppButton, 'Save changes'));
      await pumpPatientsFrames(tester);

      expect(find.text('Possible duplicate found'), findsOneWidget);
      expect(find.byKey(ValueKey<String>(_duplicateCandidate.id)), findsOneWidget);
      expect(repo.lastUpdateInput, isNull);
    });

    testWidgets('advanced: Cancel closes without saving', (tester) async {
      final detail = samplePatientDetail(
        id: _patientId,
        fullName: 'Hydrated Patient',
        phone: '2012345678',
      );
      final repo = FakePatientRepository(detail: detail);

      await _openEditDialog(tester, repo: repo, detail: detail);
      await pumpPatientsFrames(tester);

      await tester.enterText(_editNameField(), 'Edited Name');
      await pumpPatientsFrames(tester);

      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await pumpPatientsFrames(tester);

      expect(find.byType(EditPatientDialog), findsNothing);
      expect(repo.lastUpdateInput, isNull);
    });
  });
}

class _MutableDetailPatientRepository extends FakePatientRepository {
  _MutableDetailPatientRepository({
    required PatientDetail initialDetail,
    super.updateException,
  })  : _mutableDetail = initialDetail,
        super(detail: initialDetail);

  final PatientDetail _mutableDetail;

  @override
  Future<PatientDetail> getPatient(String patientId) async {
    getPatientCallCount++;
    if (_mutableDetail.id == patientId) {
      return _mutableDetail;
    }
    throw StateError('Patient not found: $patientId');
  }
}
