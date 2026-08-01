import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_controls.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_sort_key.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_list_controls.dart';

import '../../helpers/auth_test_support.dart';

class _ControlsHarness extends StatefulWidget {
  const _ControlsHarness({
    required this.initialControls,
    required this.authState,
    required this.branches,
  });

  final InvoiceListControls initialControls;
  final AuthSessionState authState;
  final List<({String id, String name})> branches;

  @override
  State<_ControlsHarness> createState() => _ControlsHarnessState();
}

class _ControlsHarnessState extends State<_ControlsHarness> {
  late InvoiceListControls controls;
  InvoiceListControls? lastApplied;

  @override
  void initState() {
    super.initState();
    controls = widget.initialControls;
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(
          () => MutableAuthSessionNotifier(widget.authState),
        ),
        invoiceBranchFilterOptionsProvider.overrideWith(
          (ref) async => widget.branches,
        ),
      ],
      child: InvoiceListControlsBar(
        controls: controls,
        onApply: (next) {
          lastApplied = next;
          setState(() => controls = next);
        },
      ),
    );
  }
}

AuthSessionState _authSession({required List<String> branchIds}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(branchIds: branchIds),
  );
}

Future<_ControlsHarnessState> _pumpControlsBar(
  WidgetTester tester, {
  InvoiceListControls initialControls = InvoiceListControls.defaultControls,
  required List<String> branchIds,
  List<({String id, String name})> branches = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 600));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: _ControlsHarness(
          initialControls: initialControls,
          authState: _authSession(branchIds: branchIds),
          branches: branches,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return tester.state<_ControlsHarnessState>(find.byType(_ControlsHarness));
}

void main() {
  testWidgets('InvoiceListControlsBar renders search placeholder and sort options', (tester) async {
    await _pumpControlsBar(tester, branchIds: ['branch-1']);

    expect(
      find.text('Search by invoice number, patient, or MRN…'),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('Sort invoices'));
    await tester.pumpAndSettle();

    for (final option in InvoiceSortKey.options) {
      expect(find.text(option.label), findsOneWidget);
    }
  });

  testWidgets('InvoiceListControlsBar search change invokes onApply with updated search', (tester) async {
    final harness = await _pumpControlsBar(tester, branchIds: ['branch-1']);

    await tester.enterText(find.bySemanticsLabel('Search invoices'), 'MRN-42');
    await tester.pump(const Duration(milliseconds: 350));

    expect(harness.lastApplied?.search, 'MRN-42');
    expect(harness.lastApplied?.page, 1);
  });

  testWidgets('InvoiceListControlsBar sort change invokes onApply with updated sort', (tester) async {
    final harness = await _pumpControlsBar(tester, branchIds: ['branch-1']);

    await tester.tap(find.bySemanticsLabel('Sort invoices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Created (oldest)'));
    await tester.pumpAndSettle();

    expect(harness.lastApplied?.sort, InvoiceSortKey.dateAsc);
    expect(harness.lastApplied?.page, 1);
  });

  testWidgets('InvoiceListControlsBar status filter invokes onApply with updated status', (tester) async {
    final harness = await _pumpControlsBar(tester, branchIds: ['branch-1']);

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Issued'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.lastApplied?.status, InvoiceStatus.issued);
    expect(harness.lastApplied?.page, 1);
  });

  testWidgets('InvoiceListControlsBar shows Branch filter only for multi-branch sessions', (tester) async {
    await _pumpControlsBar(
      tester,
      branchIds: ['branch-1', 'branch-2'],
      branches: [
        (id: 'branch-1', name: 'Main'),
        (id: 'branch-2', name: 'Side'),
      ],
    );

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    expect(find.text('Branch'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await _pumpControlsBar(tester, branchIds: ['branch-1']);

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    expect(find.text('Branch'), findsNothing);
  });

  testWidgets('InvoiceListControlsBar branch filter invokes onApply with updated branch', (tester) async {
    final harness = await _pumpControlsBar(
      tester,
      branchIds: ['branch-1', 'branch-2'],
      branches: [
        (id: 'branch-1', name: 'Main'),
        (id: 'branch-2', name: 'Side'),
      ],
    );

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Side'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.lastApplied?.branch, 'branch-2');
    expect(harness.lastApplied?.page, 1);
  });

  testWidgets('InvoiceListControlsBar active filter chips clear via onApply', (tester) async {
    final harness = await _pumpControlsBar(
      tester,
      branchIds: ['branch-1', 'branch-2'],
      initialControls: const InvoiceListControls(
        search: 'Ahmed',
        status: InvoiceStatus.issued,
        branch: 'branch-2',
      ),
      branches: [
        (id: 'branch-1', name: 'Main'),
        (id: 'branch-2', name: 'Side'),
      ],
    );

    expect(find.text('Issued'), findsOneWidget);
    expect(find.text('Side'), findsOneWidget);
    expect(find.text('Search: Ahmed'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Remove Issued'));
    await tester.pumpAndSettle();
    expect(harness.lastApplied?.status, isNull);

    await tester.tap(find.bySemanticsLabel('Remove Side'));
    await tester.pumpAndSettle();
    expect(harness.lastApplied?.branch, isNull);

    await tester.tap(find.bySemanticsLabel('Remove Search: Ahmed'));
    await tester.pumpAndSettle();
    expect(harness.lastApplied?.search, '');
  });
}
