// Test-only harness for billing page widget tests.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
<<<<<<< HEAD
=======
import 'package:flutter_riverpod/misc.dart';
>>>>>>> master
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
<<<<<<< HEAD
=======
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
>>>>>>> master
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_toast.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
<<<<<<< HEAD
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
=======
>>>>>>> master
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_controls.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_filters.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_editor_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_list_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/service_catalog/domain/effective_price.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_selector_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../helpers/auth_test_support.dart';
<<<<<<< HEAD
import '../../helpers/role_permission_seed.dart';
import '../../support/billing_rpc_test_client.dart';
import '../../support/visit_encounter_test_support.dart';
=======
import '../../helpers/breadcrumb_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import '../../support/billing_rpc_test_client.dart';
>>>>>>> master

const billingTestBranchId = '44444444-4444-4444-8444-444444444444';
const billingTestPatientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const billingTestVisitId = BillingRpcTestClient.visitId;
const billingTestDraftInvoiceId = BillingRpcTestClient.draftInvoiceId;
const billingTestIssuedInvoiceId = BillingRpcTestClient.issuedInvoiceId;
const billingTestItemId = BillingRpcTestClient.itemId;

const billingWideSurfaceSize = Size(1400, 1000);

/// Tracks [InvoiceListNotifier.reload] and [InvoiceListNotifier.applyControls].
class SpyInvoiceListNotifier extends InvoiceListNotifier {
  SpyInvoiceListNotifier(this._state);

  final InvoiceListUiState _state;

  var reloadCallCount = 0;
  var applyControlsCallCount = 0;
  InvoiceListControls? lastAppliedControls;

  @override
  Future<InvoiceListUiState> build() async {
    ref.watch(
      authSessionProvider.select((state) => state.context?.activeBranchId),
    );
    return _state;
  }

  @override
  Future<void> reload() async {
    reloadCallCount++;
    state = AsyncData(_state);
  }

  @override
  Future<void> applyControls(
    InvoiceListControls controls, {
    required bool multiBranch,
  }) async {
    applyControlsCallCount++;
    lastAppliedControls = controls;
  }
}

/// Never completes so [invoiceListProvider] stays in loading.
class LoadingInvoiceListNotifier extends InvoiceListNotifier {
  @override
  Future<InvoiceListUiState> build() async {
    ref.watch(
      authSessionProvider.select((state) => state.context?.activeBranchId),
    );
    return Completer<InvoiceListUiState>().future;
  }
<<<<<<< HEAD
=======

  @override
  Future<void> reload() async {
    // InvoiceListPage calls reload on mount; keep the loading build() pending.
  }
>>>>>>> master
}

/// Throws on build to surface the list error state.
class ErrorInvoiceListNotifier extends InvoiceListNotifier {
  ErrorInvoiceListNotifier(this.message);

  final String message;

  @override
  Future<InvoiceListUiState> build() async {
    throw Exception(message);
  }
}

/// Tracks [ServiceSelectorNotifier.search] calls.
class SpyServiceSelectorNotifier extends ServiceSelectorNotifier {
  SpyServiceSelectorNotifier(super.branchId);

  var searchCallCount = 0;
  String? lastQuery;

  @override
  void search(String query, {Duration debounce = const Duration(milliseconds: 300)}) {
    searchCallCount++;
    lastQuery = query;
    super.search(query, debounce: Duration.zero);
  }
}

/// Tracks [VisitBillingFlowNotifier.beginBilling].
class SpyVisitBillingFlowNotifier extends VisitBillingFlowNotifier {
  SpyVisitBillingFlowNotifier(super.visitId);

  var beginBillingCallCount = 0;

  @override
  void beginBilling() {
    beginBillingCallCount++;
    super.beginBilling();
  }
}

/// Fixed visit documentation snapshot for [VisitBillingPage].
class FixedVisitDocumentationNotifier extends VisitDocumentationNotifier {
<<<<<<< HEAD
  FixedVisitDocumentationNotifier(this._state);
=======
  FixedVisitDocumentationNotifier(super.visitId, this._state);
>>>>>>> master

  final VisitDocumentationState _state;

  @override
  Future<VisitDocumentationState> build() async => _state;
}

/// Surfaces visit documentation load errors on [VisitBillingPage].
class ErrorVisitDocumentationNotifier extends VisitDocumentationNotifier {
<<<<<<< HEAD
  ErrorVisitDocumentationNotifier(this._error);
=======
  ErrorVisitDocumentationNotifier(super.visitId, this._error);
>>>>>>> master

  final Object _error;

  @override
  Future<VisitDocumentationState> build() async => throw _error;
}

/// Fixed editor state with optional mutation hooks.
class SpyInvoiceEditorNotifier extends InvoiceEditorNotifier {
  SpyInvoiceEditorNotifier(
    super.invoiceId, {
    required InvoiceEditorState initialState,
    this.onAddItemFromService,
    this.onRemoveItem,
    this.onIssue,
  }) : _initialState = initialState;

  final InvoiceEditorState _initialState;
  final Future<String> Function(EligibleService service)? onAddItemFromService;
  final Future<void> Function(String itemId)? onRemoveItem;
  final Future<String> Function()? onIssue;

  var addItemCallCount = 0;
  var removeItemCallCount = 0;
  var issueCallCount = 0;

  @override
  Future<InvoiceEditorState> build() async => _initialState;

  @override
  Future<String> addItemFromService(EligibleService service) async {
    addItemCallCount++;
    if (onAddItemFromService != null) {
      return onAddItemFromService!(service);
    }
    return billingTestItemId;
  }

  @override
  Future<void> removeItem(String itemId) async {
    removeItemCallCount++;
    if (onRemoveItem != null) {
      await onRemoveItem!(itemId);
    }
  }

  @override
  Future<String> issue() async {
    issueCallCount++;
    if (onIssue != null) {
      return onIssue!();
    }
    return 'INV-MAIN-000001';
  }
}

/// Editor notifier that mutates draft line items for add/remove widget tests.
class MutableInvoiceEditorNotifier extends InvoiceEditorNotifier {
  MutableInvoiceEditorNotifier(super.invoiceId, InvoiceEditorState initialState)
      : _state = initialState;

  InvoiceEditorState _state;

  @override
  Future<InvoiceEditorState> build() async => _state;

  void replaceState(InvoiceEditorState next) {
    _state = next;
    state = AsyncData(next);
  }

  @override
  Future<String> addItemFromService(EligibleService service) async {
    final invoice = _state.invoice;
    final item = buildBillingInvoiceItem(description: service.name);
    replaceState(
      InvoiceEditorState(
        invoice: buildBillingInvoiceDetail(
          id: invoice.id,
          status: invoice.status,
          items: [...invoice.items, item],
        ),
      ),
    );
    return item.id;
  }

  @override
  Future<void> removeItem(String itemId) async {
    final invoice = _state.invoice;
    replaceState(
      InvoiceEditorState(
        invoice: buildBillingInvoiceDetail(
          id: invoice.id,
          status: invoice.status,
          items: invoice.items.where((item) => item.id != itemId).toList(),
        ),
      ),
    );
  }
}

AuthSessionState billingAuthSession({
  Set<String>? permissions,
  List<String>? branchIds,
  String? activeBranchId,
}) {
  final branches = branchIds ?? [billingTestBranchId];
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: permissions ?? RolePermissionSeed.administrator,
      branchIds: branches,
      activeBranchId: activeBranchId ?? branches.first,
    ),
  );
}

InvoiceListItem buildBillingInvoiceListItem({
  String id = billingTestIssuedInvoiceId,
  String? invoiceNumber = 'INV-MAIN-000001',
  InvoiceStatus status = InvoiceStatus.issued,
  String patientDisplayName = 'Test Patient',
  String? patientId = billingTestPatientId,
}) {
  return InvoiceListItem(
    id: id,
    invoiceNumber: invoiceNumber,
    status: status,
    patientDisplayName: patientDisplayName,
    patientId: patientId,
    branchId: billingTestBranchId,
    branchCode: 'MAIN',
    subtotal: Money.parse('100.00'),
    discountAmount: Money.zero,
    insuranceCoveredAmount: Money.zero,
    paidAmount: Money.zero,
    balance: Money.parse('100.00'),
    createdAt: DateTime.utc(2026, 6, 2, 10),
    issuedAt: DateTime.utc(2026, 6, 2, 11),
    currency: 'USD',
  );
}

InvoiceListUiState buildBillingListState({
  List<InvoiceListItem>? items,
  bool hasMore = false,
  bool hasInvoices = true,
  InvoiceListFilters filters = const InvoiceListFilters(),
  int? estimatedTotal,
}) {
  final resolvedItems = items ?? [buildBillingInvoiceListItem()];
  return InvoiceListUiState(
    items: resolvedItems,
    hasMore: hasMore,
    filters: filters,
    estimatedTotal: estimatedTotal ?? resolvedItems.length,
    hasInvoices: hasInvoices,
  );
}

InvoiceItem buildBillingInvoiceItem({
  String id = billingTestItemId,
  String description = 'Consultation',
  String quantity = '1',
  String unitPrice = '100.00',
}) {
  final price = Money.parse(unitPrice);
  return InvoiceItem(
    id: id,
    description: description,
    quantity: quantity,
    unitPrice: price,
    lineSubtotal: price,
    lineDiscountAmount: Money.zero,
    lineTotal: price,
  );
}

InvoiceDetail buildBillingInvoiceDetail({
  String id = billingTestIssuedInvoiceId,
  String? invoiceNumber = 'INV-MAIN-000001',
  InvoiceStatus status = InvoiceStatus.issued,
  String patientId = billingTestPatientId,
  String visitId = billingTestVisitId,
  List<InvoiceItem>? items,
  VisitSummary? visitSummary,
  String? voidReason,
  DateTime? voidedAt,
}) {
  final resolvedItems = items ??
      (status == InvoiceStatus.draft
          ? const <InvoiceItem>[]
          : [buildBillingInvoiceItem()]);
  return InvoiceDetail(
    id: id,
    invoiceNumber: invoiceNumber,
    status: status,
    branchId: billingTestBranchId,
    patientId: patientId,
    visitId: visitId,
    subtotal: Money.parse('100.00'),
    discountAmount: Money.zero,
    insuranceCoveredAmount: Money.zero,
    currency: 'USD',
    balance: status.isVoided ? Money.zero : Money.parse('100.00'),
    createdAt: DateTime.utc(2026, 6, 1, 10),
    updatedAt: DateTime.utc(2026, 6, 2, 12),
    issuedAt: status.isDraft ? null : DateTime.utc(2026, 6, 1, 11),
    voidedAt: voidedAt,
    voidReason: voidReason,
    items: resolvedItems,
    payments: const [],
    patientDisplayName: 'Test Patient',
    patientMrn: 'MRN-000001',
    patientPhone: '+20 100 000 0000',
    branchName: 'Main',
    visitSummary: visitSummary ??
        VisitSummary(
          date: DateTime.utc(2026, 6, 1),
          doctor: 'Dr. Ada',
          branch: 'Main',
        ),
  );
}

InvoiceDetailViewState buildBillingDetailView({
  InvoiceDetail? invoice,
  bool? canCreate,
  bool? canVoid,
  bool? canRecordPayment,
}) {
  final resolved = invoice ?? buildBillingInvoiceDetail();
  return InvoiceDetailViewState(
    invoice: resolved,
    canCreate: canCreate ?? true,
    canApplyDiscount: true,
    canVoid: canVoid ?? true,
    canRecordPayment: canRecordPayment ?? true,
    canRefund: true,
  );
}

InvoiceEditorState buildBillingEditorState({
  InvoiceDetail? invoice,
  bool isMutating = false,
}) {
  return InvoiceEditorState(
    invoice: invoice ?? buildBillingInvoiceDetail(id: billingTestDraftInvoiceId, status: InvoiceStatus.draft),
    isMutating: isMutating,
  );
}

EligibleService buildBillingEligibleService({
  String serviceId = 'svc-consultation',
  String name = 'Consultation',
  String unitPrice = '100.00',
}) {
  return EligibleService(
    serviceId: serviceId,
    name: name,
    unitPrice: Money.parse(unitPrice),
    appliedRule: AppliedPriceRule.defaultPrice,
    onPromotion: false,
  );
}

RpcFailure billingNotFoundFailure() {
  return RpcFailure(
    const RpcResult(
      success: false,
      errorCode: 'NOT_FOUND',
      errorMessage: 'Invoice not found.',
    ),
  );
}

List<Override> billingProviderOverrides({
  AuthSessionState? auth,
  BillingRpcTestClient? rpcClient,
  SpyInvoiceListNotifier? listNotifier,
  Override? invoiceListOverride,
  String? detailInvoiceId,
  InvoiceDetailViewState? detailView,
  Object? detailError,
  String? editorInvoiceId,
<<<<<<< HEAD
  SpyInvoiceEditorNotifier? editorNotifier,
=======
  InvoiceEditorNotifier? editorNotifier,
>>>>>>> master
  Override? editorOverride,
  String? visitId,
  VisitDocumentationState? visitDocState,
  Object? visitDocError,
  SpyVisitBillingFlowNotifier? visitBillingFlowNotifier,
  String? serviceSelectorBranchId,
  Override? serviceSelectorOverride,
<<<<<<< HEAD
=======
  BreadcrumbTrail? breadcrumbTrail,
>>>>>>> master
  List<Override> extraOverrides = const [],
}) {
  final client = rpcClient ?? BillingRpcTestClient();
  final resolvedAuth = auth ?? billingAuthSession();

  return [
<<<<<<< HEAD
=======
    if (breadcrumbTrail != null) breadcrumbTrailOverride(breadcrumbTrail),
>>>>>>> master
    authSessionProvider.overrideWith(
      () => MutableAuthSessionNotifier(resolvedAuth),
    ),
    permissionServiceProvider.overrideWith(
      (ref) => PermissionService(ref.watch(authSessionProvider).context),
    ),
    invoiceRepositoryProvider.overrideWith((ref) => InvoiceRepository(client)),
    if (invoiceListOverride != null)
      invoiceListOverride
    else if (listNotifier != null)
      invoiceListProvider.overrideWith(() => listNotifier),
    if (detailInvoiceId != null)
      if (detailError != null)
        invoiceDetailViewProvider(detailInvoiceId).overrideWith(
          (ref) async => throw detailError,
        )
      else
        invoiceDetailViewProvider(detailInvoiceId).overrideWith(
          (ref) async => detailView ?? buildBillingDetailView(),
        ),
    if (editorOverride != null)
      editorOverride
    else if (editorInvoiceId != null && editorNotifier != null)
      invoiceEditorProvider(editorInvoiceId).overrideWith(() => editorNotifier),
    if (visitId != null)
      if (visitDocError != null)
        visitDocumentationProvider(visitId).overrideWith(
<<<<<<< HEAD
          () => ErrorVisitDocumentationNotifier(visitDocError),
        )
      else if (visitDocState != null)
        visitDocumentationProvider(visitId).overrideWith(
          () => FixedVisitDocumentationNotifier(visitDocState),
=======
          () => ErrorVisitDocumentationNotifier(visitId, visitDocError),
        )
      else if (visitDocState != null)
        visitDocumentationProvider(visitId).overrideWith(
          () => FixedVisitDocumentationNotifier(visitId, visitDocState),
>>>>>>> master
        ),
    if (visitId != null && visitBillingFlowNotifier != null)
      visitBillingFlowProvider(visitId).overrideWith(() => visitBillingFlowNotifier),
    if (serviceSelectorOverride != null)
      serviceSelectorOverride
    else if (serviceSelectorBranchId != null)
      serviceSelectorProvider(serviceSelectorBranchId).overrideWith(
        () => SpyServiceSelectorNotifier(serviceSelectorBranchId),
      ),
    ...extraOverrides,
  ];
}

/// GoRouter with stub destination markers for billing navigation assertions.
GoRouter createBillingTestRouter({
  required Widget home,
  String initialLocation = AppRoutes.billingInvoices,
  List<RouteBase> extraRoutes = const [],
  Widget Function(BuildContext context, GoRouterState state)? invoiceDetailBuilder,
  Widget Function(BuildContext context, GoRouterState state)? invoiceEditBuilder,
  Widget Function(BuildContext context, GoRouterState state)? invoiceReviewBuilder,
  Widget Function(BuildContext context, GoRouterState state)? visitBillingBuilder,
<<<<<<< HEAD
=======
  Widget Function(BuildContext context, GoRouterState state)? visitDocumentBuilder,
>>>>>>> master
}) {
  Widget marker(String label) => Scaffold(
        key: Key('route_$label'),
        body: Center(child: Text('stub:$label')),
      );

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.billingInvoices,
<<<<<<< HEAD
        builder: (_, __) => home,
=======
        builder: (_, _) => home,
>>>>>>> master
      ),
      GoRoute(
        path: '${AppRoutes.billingInvoices}/:invoiceId/${AppRoutes.billingInvoiceEditSegment}',
        builder: invoiceEditBuilder ??
            (context, state) => marker(
                  'invoice-edit-${state.pathParameters['invoiceId']}',
                ),
      ),
      GoRoute(
        path: '${AppRoutes.billingInvoices}/:invoiceId/${AppRoutes.billingInvoiceReviewSegment}',
        builder: invoiceReviewBuilder ??
            (context, state) => marker(
                  'invoice-review-${state.pathParameters['invoiceId']}',
                ),
      ),
      GoRoute(
        path: '${AppRoutes.billingInvoices}/:invoiceId',
        builder: invoiceDetailBuilder ??
            (context, state) => marker(
                  'invoice-detail-${state.pathParameters['invoiceId']}',
                ),
      ),
      GoRoute(
        path: '${AppRoutes.billing}/${AppRoutes.billingVisitSegment}/:visitId',
        builder: visitBillingBuilder ??
            (context, state) => marker(
                  'visit-billing-${state.pathParameters['visitId']}',
                ),
      ),
      GoRoute(
        path: '/patients/:patientId',
        builder: (context, state) => marker(
          'patient-${state.pathParameters['patientId']}',
        ),
      ),
      GoRoute(
        path: '/visits/:visitId/document',
<<<<<<< HEAD
        builder: (context, state) => marker(
          'visit-document-${state.pathParameters['visitId']}',
        ),
=======
        builder: visitDocumentBuilder ??
            (context, state) => marker(
                  'visit-document-${state.pathParameters['visitId']}',
                ),
>>>>>>> master
      ),
      ...extraRoutes,
    ],
  );
}

/// Pumps [child] inside the canonical billing widget-test shell.
Future<void> pumpBillingSurface(
  WidgetTester tester, {
  required Widget child,
  List<Override> overrides = const [],
  Size surfaceSize = billingWideSurfaceSize,
  bool wrapToastHost = true,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final appChild = wrapToastHost
      ? AppToastHost(
          child: Scaffold(
            body: SizedBox(
              width: surfaceSize.width,
              height: surfaceSize.height,
              child: child,
            ),
          ),
        )
      : Scaffold(
          body: SizedBox(
            width: surfaceSize.width,
            height: surfaceSize.height,
            child: child,
          ),
        );

  await tester.pumpWidget(
    ProviderScope(
<<<<<<< HEAD
=======
      key: UniqueKey(),
>>>>>>> master
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: appChild,
      ),
    ),
  );
}

/// Pumps [home] behind a billing [GoRouter] with stub route markers.
Future<GoRouter> pumpBillingRouter(
  WidgetTester tester, {
  required Widget home,
  String initialLocation = AppRoutes.billingInvoices,
  List<Override> overrides = const [],
  Size surfaceSize = billingWideSurfaceSize,
  List<RouteBase> extraRoutes = const [],
  Widget Function(BuildContext context, GoRouterState state)? invoiceDetailBuilder,
  Widget Function(BuildContext context, GoRouterState state)? invoiceEditBuilder,
  Widget Function(BuildContext context, GoRouterState state)? invoiceReviewBuilder,
  Widget Function(BuildContext context, GoRouterState state)? visitBillingBuilder,
<<<<<<< HEAD
=======
  Widget Function(BuildContext context, GoRouterState state)? visitDocumentBuilder,
>>>>>>> master
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = createBillingTestRouter(
    home: home,
    initialLocation: initialLocation,
    extraRoutes: extraRoutes,
    invoiceDetailBuilder: invoiceDetailBuilder,
    invoiceEditBuilder: invoiceEditBuilder,
    invoiceReviewBuilder: invoiceReviewBuilder,
    visitBillingBuilder: visitBillingBuilder,
<<<<<<< HEAD
=======
    visitDocumentBuilder: visitDocumentBuilder,
>>>>>>> master
  );

  await tester.pumpWidget(
    ProviderScope(
<<<<<<< HEAD
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
=======
      key: UniqueKey(),
      overrides: overrides,
      child: AppToastHost(
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
>>>>>>> master
      ),
    ),
  );

  return router;
}

ProviderContainer billingProviderContainer(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Future<void> pumpBillingFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
