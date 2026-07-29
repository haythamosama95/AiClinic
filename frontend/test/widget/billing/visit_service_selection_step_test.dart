import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/providers/organization_currency_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_service_selection_grid_view.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_service_selection_list_view.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_service_selection_sidebar.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_service_selection_step.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/service_catalog/domain/effective_price.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_selector_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../helpers/settings_test_support.dart';
import '../../support/visit_encounter_test_support.dart';

const _visitId = encounterTestVisitId;

EligibleService _service({String id = 'svc-1', String name = 'Consultation'}) {
  return EligibleService(
    serviceId: id,
    name: name,
    unitPrice: Money.parse('100.00'),
    appliedRule: AppliedPriceRule.defaultPrice,
    onPromotion: false,
  );
}

class _SeededVisitBillingFlowNotifier extends VisitBillingFlowNotifier {
  _SeededVisitBillingFlowNotifier(super.visitId, this._seed);

  final VisitBillingFlowState _seed;

  @override
  VisitBillingFlowState build() => _seed;
}

class _SeededVisitDocumentationNotifier extends VisitDocumentationNotifier {
  _SeededVisitDocumentationNotifier(super.visitId, this._state);

  final VisitDocumentationState _state;

  @override
  Future<VisitDocumentationState> build() async => _state;
}

enum _CatalogMode { loading, error, empty, data }

String? _lastCatalogSearchQuery;

class _SpyServiceSelectorNotifier extends ServiceSelectorNotifier {
  _SpyServiceSelectorNotifier(super.branchId, this._mode, this._services);

  final _CatalogMode _mode;
  final List<EligibleService> _services;

  @override
  Future<List<EligibleService>> build() async => const [];

  @override
  void search(String query, {Duration debounce = const Duration(milliseconds: 300)}) {
    _lastCatalogSearchQuery = query;
    switch (_mode) {
      case _CatalogMode.loading:
        state = const AsyncLoading();
      case _CatalogMode.error:
        state = AsyncError<List<EligibleService>>(Exception('catalog failed'), StackTrace.current);
      case _CatalogMode.empty:
        state = const AsyncData([]);
      case _CatalogMode.data:
        final trimmed = query.trim().toLowerCase();
        final results = trimmed.isEmpty
            ? _services
            : _services.where((service) => service.name.toLowerCase().contains(trimmed)).toList();
        state = AsyncData(results);
    }
  }
}

class _StepHost extends ConsumerWidget {
  const _StepHost({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billing = ref.watch(visitBillingFlowProvider(_visitId));
    return VisitServiceSelectionStep(
      visitId: _visitId,
      onBack: onBack,
      onContinue: billing.selectedLines.isEmpty
          ? null
          : () {},
    );
  }
}

Future<void> _pumpStep(
  WidgetTester tester, {
  required List<Override> overrides,
  VoidCallback? onBack,
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
        home: Scaffold(
          body: _StepHost(onBack: onBack ?? () {}),
        ),
      ),
    ),
  );
}

List<Override> _stepOverrides({
  VisitBillingFlowState? billingState,
  _CatalogMode catalogMode = _CatalogMode.data,
  List<EligibleService>? services,
  bool overrideBilling = true,
}) {
  final catalogServices = services ?? [_service(), _service(id: 'svc-2', name: 'Labs')];

  return [
    if (overrideBilling)
      visitBillingFlowProvider(_visitId).overrideWith(
        () => _SeededVisitBillingFlowNotifier(_visitId, billingState ?? const VisitBillingFlowState()),
      ),
    visitDocumentationProvider(_visitId).overrideWith(
      () => _SeededVisitDocumentationNotifier(_visitId, sampleEncounterDocState()),
    ),
    serviceSelectorProvider(encounterTestBranchId).overrideWith(
      () => _SpyServiceSelectorNotifier(encounterTestBranchId, catalogMode, catalogServices),
    ),
    organizationCurrencyProvider.overrideWith((ref) => 'USD'),
    clinicSetupOrganizationProvider.overrideWith(
      (ref) => Future.value(sampleOrganizationProfile(currencyCode: 'USD')),
    ),
  ];
}

AppButton _button(WidgetTester tester, String label) {
  return tester.widget<AppButton>(find.widgetWithText(AppButton, label));
}

void main() {
  group('VisitServiceSelectionStep', () {
    testWidgets('builds with search input and sidebar', (tester) async {
      await _pumpStep(tester, overrides: _stepOverrides());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 301));

      expect(find.byType(VisitServiceSelectionStep), findsOneWidget);
      expect(find.byType(VisitServiceSelectionSidebar), findsOneWidget);
      expect(find.text('Search services…'), findsOneWidget);
    });

    testWidgets('typing in search invokes the service selector search', (tester) async {
      final overrides = _stepOverrides();
      await _pumpStep(tester, overrides: overrides);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 301));

      await tester.enterText(find.byType(TextField), 'lab');
      await tester.pump();

      expect(_lastCatalogSearchQuery, 'lab');
    });

    testWidgets('shows catalog loading state', (tester) async {
      await _pumpStep(
        tester,
        overrides: _stepOverrides(catalogMode: _CatalogMode.loading),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 301));

      expect(find.byType(AppSkeleton), findsOneWidget);
    });

    testWidgets('shows catalog error state', (tester) async {
      await _pumpStep(
        tester,
        overrides: _stepOverrides(catalogMode: _CatalogMode.error),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 301));

      expect(find.text('Could not load services. Try searching again.'), findsOneWidget);
    });

    testWidgets('shows catalog empty state', (tester) async {
      await _pumpStep(
        tester,
        overrides: _stepOverrides(catalogMode: _CatalogMode.empty),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 301));

      expect(find.text('No services in the catalog yet.'), findsOneWidget);
    });

    testWidgets('grid/list toggle switches between grid and list views', (tester) async {
      await _pumpStep(tester, overrides: _stepOverrides());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 301));

      expect(find.byType(VisitServiceSelectionGridView), findsOneWidget);
      expect(find.byType(VisitServiceSelectionListView), findsNothing);

      await tester.tap(find.byIcon(Icons.view_list_rounded));
      await tester.pump();

      expect(find.byType(VisitServiceSelectionListView), findsOneWidget);
      expect(find.byType(VisitServiceSelectionGridView), findsNothing);

      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pump();

      expect(find.byType(VisitServiceSelectionGridView), findsOneWidget);
    });

    testWidgets('Review invoice is disabled until a service is selected', (tester) async {
      await _pumpStep(tester, overrides: _stepOverrides(overrideBilling: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 301));

      expect(_button(tester, 'Review invoice').onPressed, isNull);

      await tester.tap(find.text('Consultation'));
      await tester.pump();

      expect(_button(tester, 'Review invoice').onPressed, isNotNull);
    });

    testWidgets('Back to review invokes its callback', (tester) async {
      var backTapped = false;

      await _pumpStep(
        tester,
        overrides: _stepOverrides(),
        onBack: () => backTapped = true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 301));

      await tester.tap(find.widgetWithText(AppButton, 'Back to review'));
      await tester.pump();

      expect(backTapped, isTrue);
    });
  });
}
