import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_toast.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_service_selection_step.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import '../../support/billing_rpc_test_client.dart';
import '../../support/visit_encounter_test_support.dart';
import '../../support/fake_postgrest_rpc.dart';

const _visitId = encounterTestVisitId;

VisitSelectedServiceLine _selectedLine() {
  return const VisitSelectedServiceLine(
    id: 'line-1',
    serviceId: 'svc-consult',
    name: 'Consultation',
    unitPrice: 100,
    quantity: 1,
  );
}

class _SeededVisitBillingFlowNotifier extends VisitBillingFlowNotifier {
  _SeededVisitBillingFlowNotifier(super.visitId, this._seed);

  final VisitBillingFlowState _seed;

  @override
  VisitBillingFlowState build() => _seed;
}

class _SpyVisitDocumentationNotifier extends VisitDocumentationNotifier {
  _SpyVisitDocumentationNotifier(super.visitId, this._seed, {this.completeVisitFailure});

  final VisitDocumentationState _seed;
  final RpcFailure? completeVisitFailure;

  var completeVisitCallCount = 0;

  @override
  Future<VisitDocumentationState> build() async => _seed;

  @override
  Future<CompleteVisitResult> completeVisit({DateTime? expectedUpdatedAt}) async {
    completeVisitCallCount++;
    if (completeVisitFailure != null) {
      throw completeVisitFailure!;
    }

    final completed = _seed.visit.copyWith(status: VisitStatus.completed);
    final next = _seed.copyWith(
      visit: completed,
      persistedVisit: completed,
      workspaceEditMode: WorkspaceEditMode.viewing,
      noteEditMode: DocumentationEditMode.readOnly,
      saveStatus: DocumentationSaveStatus.saved,
    );
    state = AsyncData(next);
    return const CompleteVisitResult(
      visitId: encounterTestVisitId,
      visitStatus: 'completed',
      appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      appointmentStatus: 'completed',
    );
  }
}

class _TrackingCatalogClient extends RpcCaptureSupabaseClient {
  final List<String> calls = <String>[];

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    calls.add(fn);
    lastFunction = fn;
    lastParams = params == null ? null : Map<String, dynamic>.from(params);
    return FakePostgrestRpc({
      'success': true,
      'data': {
        'item_id': BillingRpcTestClient.itemId,
        'quantity': '1',
        'unit_price': '100.00',
        'applied_rule': 'default',
      },
    }) as PostgrestFilterBuilder<T>;
  }
}

Future<void> _pumpFlow(
  WidgetTester tester, {
  required List<Override> overrides,
  VoidCallback? onBackToReview,
  VoidCallback? onCompleted,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppToastHost(
          child: Scaffold(
            body: VisitBillingFlow(
              visitId: _visitId,
              onBackToReview: onBackToReview,
              onCompleted: onCompleted,
            ),
          ),
        ),
      ),
    ),
  );
}

List<Override> _baseFlowOverrides({
  VisitBillingFlowState? billingState,
  _SpyVisitDocumentationNotifier? docNotifier,
  BillingRpcTestClient? billingClient,
  _TrackingCatalogClient? catalogClient,
  Set<String>? permissions,
}) {
  final billing = billingState ?? const VisitBillingFlowState();
  final doc = docNotifier ??
      _SpyVisitDocumentationNotifier(_visitId, sampleEncounterDocState());
  final billingRpc = billingClient ?? BillingRpcTestClient();
  final catalogRpc = catalogClient ?? _TrackingCatalogClient();

  return [
    authSessionProvider.overrideWith(
      () => MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            branchIds: [encounterTestBranchId],
            activeBranchId: encounterTestBranchId,
            permissions: permissions ?? RolePermissionSeed.administrator,
          ),
        ),
      ),
    ),
    permissionServiceProvider.overrideWith(
      (ref) => PermissionService(ref.watch(authSessionProvider).context),
    ),
    visitBillingFlowProvider(_visitId).overrideWith(
      () => _SeededVisitBillingFlowNotifier(_visitId, billing),
    ),
    visitDocumentationProvider(_visitId).overrideWith(() => doc),
    invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(billingRpc)),
    serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(catalogRpc)),
  ];
}

AppButton _button(WidgetTester tester, String label) {
  return tester.widget<AppButton>(find.widgetWithText(AppButton, label));
}

void main() {
  group('VisitBillingFlow', () {
    testWidgets('builds and renders the service selection step by default', (tester) async {
      await _pumpFlow(tester, overrides: _baseFlowOverrides());
      await tester.pump();

      expect(find.byType(VisitServiceSelectionStep), findsOneWidget);
      expect(find.text('Services performed'), findsOneWidget);
    });

    testWidgets('renders the invoice review step when billing step is invoice', (tester) async {
      await _pumpFlow(
        tester,
        overrides: _baseFlowOverrides(
          billingState: VisitBillingFlowState(
            step: VisitBillingStep.invoice,
            selectedLines: [_selectedLine()],
            invoicePreviewNumber: 'INV-TEST-0001',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(VisitInvoiceReviewStep), findsOneWidget);
      expect(find.text('Finalize visit & invoice'), findsOneWidget);
    });

    testWidgets('advancing and going back switch the rendered step', (tester) async {
      await _pumpFlow(
        tester,
        overrides: _baseFlowOverrides(
          billingState: const VisitBillingFlowState(
            selectedLines: [],
          ).copyWith(
            selectedLines: [_selectedLine()],
            invoicePreviewNumber: 'INV-TEST-0001',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(VisitServiceSelectionStep), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Review invoice'));
      await tester.pump();

      expect(find.byType(VisitInvoiceReviewStep), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Edit services'));
      await tester.pump();

      expect(find.byType(VisitServiceSelectionStep), findsOneWidget);
    });

    testWidgets('finalize invokes expected repository calls on success', (tester) async {
      final billingClient = BillingRpcTestClient();
      final catalogClient = _TrackingCatalogClient();
      final docNotifier = _SpyVisitDocumentationNotifier(_visitId, sampleEncounterDocState());

      await _pumpFlow(
        tester,
        overrides: _baseFlowOverrides(
          billingState: VisitBillingFlowState(
            step: VisitBillingStep.invoice,
            selectedLines: [_selectedLine()],
            invoicePreviewNumber: 'INV-TEST-0001',
          ),
          docNotifier: docNotifier,
          billingClient: billingClient,
          catalogClient: catalogClient,
        ),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(AppButton, 'Finalize visit & invoice'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(docNotifier.completeVisitCallCount, 1);
      expect(billingClient.rpcLog, contains('create_invoice_from_visit'));
      expect(catalogClient.calls, contains('add_invoice_item_from_service'));
      expect(billingClient.rpcLog, contains('issue_invoice'));
      expect(billingClient.rpcLog, contains('get_invoice_detail'));
    });

    testWidgets('finalize failure surfaces an error without crashing', (tester) async {
      final docNotifier = _SpyVisitDocumentationNotifier(
        _visitId,
        sampleEncounterDocState(),
        completeVisitFailure: RpcFailure(
          RpcResult(success: false, errorCode: 'FORBIDDEN', errorMessage: 'Completion failed.'),
        ),
      );

      await _pumpFlow(
        tester,
        overrides: _baseFlowOverrides(
          billingState: VisitBillingFlowState(
            step: VisitBillingStep.invoice,
            selectedLines: [_selectedLine()],
            invoicePreviewNumber: 'INV-TEST-0001',
          ),
          docNotifier: docNotifier,
        ),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(AppButton, 'Finalize visit & invoice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('You do not have permission to perform this action.'), findsOneWidget);
      expect(find.byType(VisitBillingFlow), findsOneWidget);
    });

    testWidgets('submitting state disables the finalize control', (tester) async {
      await _pumpFlow(
        tester,
        overrides: _baseFlowOverrides(
          billingState: VisitBillingFlowState(
            step: VisitBillingStep.invoice,
            selectedLines: [_selectedLine()],
            invoicePreviewNumber: 'INV-TEST-0001',
            isSubmitting: true,
          ),
        ),
      );
      await tester.pump();

      final finalize = _button(tester, 'Finalize visit & invoice');
      expect(finalize.onPressed, isNull);
      expect(finalize.loading, isTrue);
    });

    testWidgets('Back to review invokes callback and resets billing flow', (tester) async {
      var backTapped = false;

      await _pumpFlow(
        tester,
        overrides: _baseFlowOverrides(
          billingState: const VisitBillingFlowState(
            selectedLines: [],
          ).copyWith(
            selectedLines: [_selectedLine()],
            invoicePreviewNumber: 'INV-TEST-0001',
          ),
        ),
        onBackToReview: () => backTapped = true,
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(AppButton, 'Back to review'));
      await tester.pump();

      expect(backTapped, isTrue);
    });
  });
}
