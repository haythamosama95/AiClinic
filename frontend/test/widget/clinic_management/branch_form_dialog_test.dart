import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/clinic-management/presentation/components/branch_form_dialog.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/branch_form_values.dart';

import 'clinic_management_widget_test_harness.dart';

class _BranchFormDialogHost extends StatefulWidget {
  const _BranchFormDialogHost({required this.onSubmit});

  final ValueChanged<BranchFormValues> onSubmit;

  @override
  State<_BranchFormDialogHost> createState() => _BranchFormDialogHostState();
}

class _BranchFormDialogHostState extends State<_BranchFormDialogHost> {
  var _open = true;

  @override
  Widget build(BuildContext context) {
    return BranchFormDialog(
      open: _open,
      onOpenChange: (open) => setState(() => _open = open),
      mode: BranchFormDialogMode.create,
      initialValues: emptyBranchFormValues(),
      onSubmit: widget.onSubmit,
    );
  }
}

void main() {
  testWidgets('BranchFormDialog create mode shows title and submit label', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      scrollable: false,
      child: BranchFormDialog(
        open: true,
        onOpenChange: (_) {},
        mode: BranchFormDialogMode.create,
        initialValues: emptyBranchFormValues(),
        onSubmit: (_) {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    expect(find.text('Add branch'), findsOneWidget);
    expect(find.text('Create branch'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('BranchFormDialog shows validation error for empty name', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      scrollable: false,
      child: BranchFormDialog(
        open: true,
        onOpenChange: (_) {},
        mode: BranchFormDialogMode.create,
        initialValues: emptyBranchFormValues(),
        onSubmit: (_) {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    await tester.tap(find.text('Create branch'));
    await settleClinicMgmtWidget(tester);

    expect(find.text('Branch name is required'), findsOneWidget);
  });

  testWidgets('BranchFormDialog cancel closes dialog', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      scrollable: false,
      child: const _BranchFormDialogHost(onSubmit: _noopSubmit),
    );
    await settleClinicMgmtWidget(tester);

    expect(find.text('Add branch'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await settleClinicMgmtWidget(tester);

    expect(find.text('Add branch'), findsNothing);
  });

  testWidgets('BranchFormDialog submit with valid data calls onSubmit', (tester) async {
    BranchFormValues? submitted;

    await pumpClinicMgmtWidget(
      tester,
      scrollable: false,
      child: BranchFormDialog(
        open: true,
        onOpenChange: (_) {},
        mode: BranchFormDialogMode.create,
        initialValues: clinicMgmtValidBranchFormValues(),
        onSubmit: (values) => submitted = values,
      ),
    );
    await settleClinicMgmtWidget(tester);

    await tester.tap(find.text('Create branch'));
    await settleClinicMgmtWidget(tester);

    expect(submitted, isNotNull);
    expect(submitted!.name, 'New Branch');
    expect(submitted!.code, 'NEW');
  });
}

void _noopSubmit(BranchFormValues _) {}
