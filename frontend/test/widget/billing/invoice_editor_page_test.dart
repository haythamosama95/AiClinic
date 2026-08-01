import 'dart:async';

import 'package:flutter/material.dart';
<<<<<<< HEAD
import 'package:flutter_riverpod/flutter_riverpod.dart';
=======
>>>>>>> master
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
<<<<<<< HEAD
=======
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
>>>>>>> master
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_editor_page.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_editor_notifier.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_selector_notifier.dart';

import 'billing_widget_test_harness.dart';

void main() {
  group('InvoiceEditorPage', () {
    testWidgets('shows loading spinner', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceEditorPage(invoiceId: billingTestDraftInvoiceId),
        overrides: billingProviderOverrides(
          extraOverrides: [
            invoiceEditorProvider(billingTestDraftInvoiceId).overrideWith(
<<<<<<< HEAD
              () => _DelayedInvoiceEditorNotifier(
                Future<InvoiceEditorState>.delayed(
                  const Duration(days: 1),
                  () => buildBillingEditorState(),
                ),
              ),
=======
              () => _LoadingInvoiceEditorNotifier(billingTestDraftInvoiceId),
>>>>>>> master
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error with Retry', (tester) async {
      final retryState = _EditorRetryState();

      await pumpBillingSurface(
        tester,
        child: const InvoiceEditorPage(invoiceId: billingTestDraftInvoiceId),
        overrides: billingProviderOverrides(
          extraOverrides: [
            invoiceEditorProvider(billingTestDraftInvoiceId).overrideWith(
<<<<<<< HEAD
              () => _CountingErrorInvoiceEditorNotifier(retryState),
=======
              () => _CountingErrorInvoiceEditorNotifier(
                billingTestDraftInvoiceId,
                retryState,
              ),
>>>>>>> master
            ),
          ],
        ),
      );
      await pumpBillingFrames(tester);

      expect(find.text('Could not load draft'), findsOneWidget);
      expect(retryState.buildCount, 1);

      await tester.tap(find.text('Retry'));
      await pumpBillingFrames(tester);

      expect(retryState.buildCount, greaterThan(1));
    });

    testWidgets('header shows Edit number', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceEditorPage(invoiceId: billingTestDraftInvoiceId),
        overrides: billingProviderOverrides(
          editorInvoiceId: billingTestDraftInvoiceId,
          editorNotifier: SpyInvoiceEditorNotifier(
            billingTestDraftInvoiceId,
            initialState: buildBillingEditorState(
              invoice: buildBillingInvoiceDetail(
                id: billingTestDraftInvoiceId,
                status: InvoiceStatus.draft,
                invoiceNumber: null,
              ),
            ),
          ),
        ),
      );
      await pumpBillingFrames(tester);

      expect(find.textContaining('Edit '), findsOneWidget);
    });

    testWidgets('Cancel pops the route', (tester) async {
      final router = await pumpBillingRouter(
        tester,
        home: const Scaffold(body: Text('Previous page')),
        overrides: billingProviderOverrides(
          editorInvoiceId: billingTestDraftInvoiceId,
          editorNotifier: SpyInvoiceEditorNotifier(
            billingTestDraftInvoiceId,
            initialState: buildBillingEditorState(),
          ),
        ),
        invoiceEditBuilder: (context, state) => InvoiceEditorPage(
          invoiceId: state.pathParameters['invoiceId']!,
        ),
      );
      await pumpBillingFrames(tester);

      router.push(AppRoutes.billingInvoiceEdit(billingTestDraftInvoiceId));
      await pumpBillingFrames(tester);

      await tester.tap(find.text('Cancel'));
      await pumpBillingFrames(tester);

      expect(find.text('Previous page'), findsOneWidget);
    });

    testWidgets('Issue invoice disabled without line items', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceEditorPage(invoiceId: billingTestDraftInvoiceId),
        overrides: billingProviderOverrides(
          editorInvoiceId: billingTestDraftInvoiceId,
          editorNotifier: SpyInvoiceEditorNotifier(
            billingTestDraftInvoiceId,
            initialState: buildBillingEditorState(
              invoice: buildBillingInvoiceDetail(
                id: billingTestDraftInvoiceId,
                status: InvoiceStatus.draft,
                items: const [],
              ),
            ),
          ),
        ),
      );
      await pumpBillingFrames(tester);

      final issueButton = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Issue invoice'),
      );
      expect(issueButton.onPressed, isNull);
    });

    testWidgets('Issue invoice enabled when line items exist', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceEditorPage(invoiceId: billingTestDraftInvoiceId),
        overrides: billingProviderOverrides(
          editorInvoiceId: billingTestDraftInvoiceId,
          editorNotifier: SpyInvoiceEditorNotifier(
            billingTestDraftInvoiceId,
            initialState: buildBillingEditorState(
              invoice: buildBillingInvoiceDetail(
                id: billingTestDraftInvoiceId,
                status: InvoiceStatus.draft,
                items: [buildBillingInvoiceItem()],
              ),
            ),
          ),
        ),
      );
      await pumpBillingFrames(tester);

      final issueButton = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Issue invoice'),
      );
      expect(issueButton.onPressed, isNotNull);
    });

    testWidgets('successful issue navigates to invoice detail', (tester) async {
      final editor = SpyInvoiceEditorNotifier(
        billingTestDraftInvoiceId,
        initialState: buildBillingEditorState(
          invoice: buildBillingInvoiceDetail(
            id: billingTestDraftInvoiceId,
            status: InvoiceStatus.draft,
            items: [buildBillingInvoiceItem()],
          ),
        ),
      );

      await pumpBillingRouter(
        tester,
        home: const SizedBox.shrink(),
        initialLocation: AppRoutes.billingInvoiceEdit(billingTestDraftInvoiceId),
        overrides: billingProviderOverrides(
          editorInvoiceId: billingTestDraftInvoiceId,
          editorNotifier: editor,
        ),
        invoiceEditBuilder: (context, state) => InvoiceEditorPage(
          invoiceId: state.pathParameters['invoiceId']!,
        ),
      );
      await pumpBillingFrames(tester);

      await tester.tap(find.text('Issue invoice'));
      await pumpBillingFrames(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('stub:invoice-detail-$billingTestDraftInvoiceId'), findsOneWidget);
      expect(editor.issueCallCount, 1);
    });

    testWidgets('shows empty line-items message', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceEditorPage(invoiceId: billingTestDraftInvoiceId),
        overrides: billingProviderOverrides(
          editorInvoiceId: billingTestDraftInvoiceId,
          editorNotifier: SpyInvoiceEditorNotifier(
            billingTestDraftInvoiceId,
            initialState: buildBillingEditorState(
              invoice: buildBillingInvoiceDetail(
                id: billingTestDraftInvoiceId,
                status: InvoiceStatus.draft,
                items: const [],
              ),
            ),
          ),
          serviceSelectorBranchId: billingTestBranchId,
        ),
      );
      await pumpBillingFrames(tester);

      expect(
        find.text('No services added yet. Search the catalog on the right.'),
        findsOneWidget,
      );
    });

    testWidgets('catalog panel shows loading state', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceEditorPage(invoiceId: billingTestDraftInvoiceId),
        overrides: billingProviderOverrides(
          editorInvoiceId: billingTestDraftInvoiceId,
          editorNotifier: SpyInvoiceEditorNotifier(
            billingTestDraftInvoiceId,
            initialState: buildBillingEditorState(),
          ),
          serviceSelectorOverride: serviceSelectorProvider(billingTestBranchId).overrideWith(
            () => _LoadingServiceSelectorNotifier(billingTestBranchId),
          ),
        ),
      );
      await pumpBillingFrames(tester);

      expect(find.text('Add from catalog'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('catalog panel shows error state', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceEditorPage(invoiceId: billingTestDraftInvoiceId),
        overrides: billingProviderOverrides(
          editorInvoiceId: billingTestDraftInvoiceId,
          editorNotifier: SpyInvoiceEditorNotifier(
            billingTestDraftInvoiceId,
            initialState: buildBillingEditorState(),
          ),
          serviceSelectorOverride: serviceSelectorProvider(billingTestBranchId).overrideWith(
            () => _ErrorServiceSelectorNotifier(billingTestBranchId),
          ),
        ),
      );
      await pumpBillingFrames(tester);

      expect(find.textContaining('catalog unavailable'), findsOneWidget);
    });

    testWidgets('catalog panel shows empty eligible services message', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceEditorPage(invoiceId: billingTestDraftInvoiceId),
        overrides: billingProviderOverrides(
          editorInvoiceId: billingTestDraftInvoiceId,
          editorNotifier: SpyInvoiceEditorNotifier(
            billingTestDraftInvoiceId,
            initialState: buildBillingEditorState(),
          ),
          serviceSelectorOverride: serviceSelectorProvider(billingTestBranchId).overrideWith(
            () => _EmptyServiceSelectorNotifier(billingTestBranchId),
          ),
        ),
      );
      await pumpBillingFrames(tester);

      expect(find.text('No eligible services'), findsOneWidget);
    });

    testWidgets('typing in search field calls service selector search', (tester) async {
      SpyServiceSelectorNotifier? catalogSpy;

      await pumpBillingSurface(
        tester,
        child: const InvoiceEditorPage(invoiceId: billingTestDraftInvoiceId),
        overrides: billingProviderOverrides(
          editorInvoiceId: billingTestDraftInvoiceId,
          editorNotifier: SpyInvoiceEditorNotifier(
            billingTestDraftInvoiceId,
            initialState: buildBillingEditorState(),
          ),
          serviceSelectorOverride: serviceSelectorProvider(billingTestBranchId).overrideWith(() {
            catalogSpy = SpyServiceSelectorNotifier(billingTestBranchId);
            return catalogSpy!;
          }),
        ),
      );
      await pumpBillingFrames(tester);

<<<<<<< HEAD
      await tester.enterText(find.byType(TextField), 'consult');
      await pumpBillingFrames(tester);
=======
      await tester.enterText(find.bySemanticsLabel('Search services'), 'consult');
      await tester.pump(const Duration(milliseconds: 300));
>>>>>>> master

      expect(catalogSpy?.searchCallCount, greaterThan(0));
      expect(catalogSpy?.lastQuery, 'consult');
    });

    testWidgets('Add adds a line item', (tester) async {
      final editor = MutableInvoiceEditorNotifier(
        billingTestDraftInvoiceId,
        buildBillingEditorState(
          invoice: buildBillingInvoiceDetail(
            id: billingTestDraftInvoiceId,
            status: InvoiceStatus.draft,
            items: const [],
          ),
        ),
      );

      await pumpBillingSurface(
        tester,
        child: const InvoiceEditorPage(invoiceId: billingTestDraftInvoiceId),
        overrides: billingProviderOverrides(
          editorInvoiceId: billingTestDraftInvoiceId,
          editorNotifier: editor,
          serviceSelectorOverride: serviceSelectorProvider(billingTestBranchId).overrideWith(
            () => _FixedServiceSelectorNotifier(
              billingTestBranchId,
              [buildBillingEligibleService()],
            ),
          ),
        ),
      );
      await pumpBillingFrames(tester);

      await tester.tap(find.text('Add'));
      await pumpBillingFrames(tester);

<<<<<<< HEAD
      expect(find.text('Consultation'), findsOneWidget);
=======
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Line items'),
            matching: find.byType(DecoratedBox),
          ).first,
          matching: find.text('Consultation'),
        ),
        findsOneWidget,
      );
>>>>>>> master
    });

    testWidgets('Remove removes a line item', (tester) async {
      final item = buildBillingInvoiceItem(description: 'To remove');
      final editor = MutableInvoiceEditorNotifier(
        billingTestDraftInvoiceId,
        buildBillingEditorState(
          invoice: buildBillingInvoiceDetail(
            id: billingTestDraftInvoiceId,
            status: InvoiceStatus.draft,
            items: [item],
          ),
        ),
      );

      await pumpBillingSurface(
        tester,
        child: const InvoiceEditorPage(invoiceId: billingTestDraftInvoiceId),
        overrides: billingProviderOverrides(
          editorInvoiceId: billingTestDraftInvoiceId,
          editorNotifier: editor,
          serviceSelectorBranchId: billingTestBranchId,
        ),
      );
      await pumpBillingFrames(tester);

      expect(find.text('To remove'), findsOneWidget);

<<<<<<< HEAD
      await tester.tap(find.bySemanticsLabel('Remove line'));
=======
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Line items'),
            matching: find.byType(DecoratedBox),
          ).first,
          matching: find.byType(AppIconButton),
        ),
      );
>>>>>>> master
      await pumpBillingFrames(tester);

      expect(find.text('To remove'), findsNothing);
      expect(
        find.text('No services added yet. Search the catalog on the right.'),
        findsOneWidget,
      );
    });
  });
}

<<<<<<< HEAD
class _DelayedInvoiceEditorNotifier extends InvoiceEditorNotifier {
  _DelayedInvoiceEditorNotifier(this._future);

  final Future<InvoiceEditorState> _future;

  @override
  Future<InvoiceEditorState> build() async => _future;
=======
class _LoadingInvoiceEditorNotifier extends InvoiceEditorNotifier {
  _LoadingInvoiceEditorNotifier(super.invoiceId);

  @override
  Future<InvoiceEditorState> build() async {
    return Completer<InvoiceEditorState>().future;
  }
>>>>>>> master
}

class _EditorRetryState {
  var buildCount = 0;
  var succeeded = false;
}

class _CountingErrorInvoiceEditorNotifier extends InvoiceEditorNotifier {
<<<<<<< HEAD
  _CountingErrorInvoiceEditorNotifier(this._retryState);
=======
  _CountingErrorInvoiceEditorNotifier(super.invoiceId, this._retryState);
>>>>>>> master

  final _EditorRetryState _retryState;

  @override
  Future<InvoiceEditorState> build() async {
    _retryState.buildCount++;
    if (!_retryState.succeeded) {
      _retryState.succeeded = true;
      throw Exception('draft load failed');
    }
    return buildBillingEditorState();
  }
}

class _LoadingServiceSelectorNotifier extends ServiceSelectorNotifier {
  _LoadingServiceSelectorNotifier(super.branchId);

  @override
  Future<List<EligibleService>> build() async {
    return Completer<List<EligibleService>>().future;
  }
}

class _ErrorServiceSelectorNotifier extends ServiceSelectorNotifier {
  _ErrorServiceSelectorNotifier(super.branchId);

  @override
  Future<List<EligibleService>> build() async => throw Exception('catalog unavailable');
}

class _EmptyServiceSelectorNotifier extends ServiceSelectorNotifier {
  _EmptyServiceSelectorNotifier(super.branchId);

  @override
  Future<List<EligibleService>> build() async => const [];
}

class _FixedServiceSelectorNotifier extends ServiceSelectorNotifier {
  _FixedServiceSelectorNotifier(super.branchId, this._services);

  final List<EligibleService> _services;

  @override
  Future<List<EligibleService>> build() async => _services;
}
