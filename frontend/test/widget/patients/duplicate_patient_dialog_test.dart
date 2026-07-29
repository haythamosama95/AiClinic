import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/presentation/add_patient/duplicate_patient_dialog.dart';

import 'patients_widget_test_harness.dart';

const _candidateA = DuplicateCandidate(
  id: '22222222-2222-4222-8222-222222222222',
  fullName: 'Sara Hassan',
  branchName: 'Branch A',
  phone: '2012345678',
  dateOfBirth: null,
);

const _candidateB = DuplicateCandidate(
  id: '33333333-3333-4333-8333-333333333333',
  fullName: 'Sara Hassan Ibrahim',
  branchName: 'Branch B',
  phone: '2098765432',
  dateOfBirth: null,
);

class _DuplicateDialogHarness extends StatefulWidget {
  const _DuplicateDialogHarness({
    required this.candidates,
    this.loading = false,
  });

  final List<DuplicateCandidate> candidates;
  final bool loading;

  @override
  State<_DuplicateDialogHarness> createState() => _DuplicateDialogHarnessState();
}

class _DuplicateDialogHarnessState extends State<_DuplicateDialogHarness> {
  var _open = true;
  var _goBackCount = 0;
  var _registerAnywayCount = 0;
  String? _openedPatientId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DuplicatePatientDialog(
          open: _open,
          loading: widget.loading,
          candidates: widget.candidates,
          onOpenChange: (open) {
            if (!open) {
              _goBackCount++;
            }
            setState(() => _open = open);
          },
          onRegisterAnyway: () => setState(() => _registerAnywayCount++),
          onOpenPatient: (id) => setState(() => _openedPatientId = id),
        ),
        Text('go-back-count:$_goBackCount'),
        Text('register-anyway-count:$_registerAnywayCount'),
        Text('opened-patient:${_openedPatientId ?? ''}'),
      ],
    );
  }
}

Finder _openButtonForCandidate(String candidateId) {
  return find.descendant(
    of: find.byKey(ValueKey<String>(candidateId)),
    matching: find.widgetWithText(AppButton, 'Open'),
  );
}

void main() {
  group('DuplicatePatientDialog', () {
    testWidgets('trivial: renders one list entry per candidate keyed by id', (tester) async {
      await pumpPatientsDialogShell(
        tester,
        home: const _DuplicateDialogHarness(
          candidates: [_candidateA, _candidateB],
        ),
      );
      await pumpPatientsFrames(tester);

      expect(find.text('Possible duplicate found'), findsOneWidget);
      expect(find.byKey(ValueKey<String>(_candidateA.id)), findsOneWidget);
      expect(find.byKey(ValueKey<String>(_candidateB.id)), findsOneWidget);
      expect(find.text(_candidateA.fullName), findsOneWidget);
      expect(find.text(_candidateB.fullName), findsOneWidget);
      expect(
        find.text('2 existing patients match the details you entered.'),
        findsOneWidget,
      );
    });

    testWidgets('advanced: Go back invokes onOpenChange(false)', (tester) async {
      await pumpPatientsDialogShell(
        tester,
        home: const _DuplicateDialogHarness(candidates: [_candidateA]),
      );
      await pumpPatientsFrames(tester);

      await tester.tap(find.widgetWithText(AppButton, 'Go back'));
      await pumpPatientsFrames(tester);
      expect(find.text('go-back-count:1'), findsOneWidget);
    });

    testWidgets('advanced: Register anyway invokes callback', (tester) async {
      await pumpPatientsFrames(tester);
      expect(find.text('register-anyway-count:1'), findsOneWidget);
    });

    testWidgets('advanced: per-candidate Open invokes onOpenPatient with candidate id', (tester) async {
      await pumpPatientsDialogShell(
        tester,
        home: const _DuplicateDialogHarness(
          candidates: [_candidateA, _candidateB],
        ),
      );
      await pumpPatientsFrames(tester);

      await tester.tap(_openButtonForCandidate(_candidateB.id));
      await pumpPatientsFrames(tester);

      expect(find.text('opened-patient:${_candidateB.id}'), findsOneWidget);
    });

    testWidgets('edge case: loading disables footer actions', (tester) async {
      await pumpPatientsDialogShell(
        tester,
        home: const _DuplicateDialogHarness(
          candidates: [_candidateA],
          loading: true,
        ),
      );
      await pumpPatientsFrames(tester);

      final goBack = tester.widget<AppButton>(find.widgetWithText(AppButton, 'Go back'));
      final registerAnyway = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Register anyway'),
      );

      expect(goBack.disabled, isTrue);
      expect(goBack.onPressed, isNull);
      expect(registerAnyway.loading, isTrue);
      expect(registerAnyway.onPressed, isNull);
    });

    testWidgets('edge case: empty candidate list still renders sanely', (tester) async {
      await pumpPatientsDialogShell(
        tester,
        home: const _DuplicateDialogHarness(candidates: []),
      );
      await pumpPatientsFrames(tester);

      expect(find.text('Possible duplicate found'), findsOneWidget);
      expect(
        find.text('0 existing patients match the details you entered.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(AppButton, 'Go back'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Register anyway'), findsOneWidget);
    });
  });
}
