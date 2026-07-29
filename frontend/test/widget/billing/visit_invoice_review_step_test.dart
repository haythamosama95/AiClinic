import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/billing/presentation/providers/organization_currency_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import '../../helpers/settings_test_support.dart';
import '../../support/visit_encounter_test_support.dart';

const _visitId = encounterTestVisitId;

VisitSelectedServiceLine _selectedLine({double unitPrice = 100}) {
  return VisitSelectedServiceLine(
    id: 'line-1',
    serviceId: 'svc-1',
    name: 'Consultation',
    unitPrice: unitPrice,
    quantity: 1,
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

PatientDetail _patient() {
  return PatientDetail(
    id: encounterTestPatientId,
    fullName: 'Test Patient',
    phone: '+20 100 000 0000',
    branchId: encounterTestBranchId,
    branchName: 'Main',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

Future<void> _pumpReviewStep(
  WidgetTester tester, {
  required List<Override> overrides,
  VoidCallback? onBack,
  VoidCallback? onFinalize,
  bool isSubmitting = false,
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
          body: VisitInvoiceReviewStep(
            visitId: _visitId,
            onBack: onBack ?? () {},
            onFinalize: isSubmitting ? null : onFinalize,
            isSubmitting: isSubmitting,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

List<Override> _reviewOverrides({
  VisitBillingFlowState? billingState,
  Set<String>? permissions,
  bool overrideBilling = true,
}) {
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
    if (overrideBilling)
      visitBillingFlowProvider(_visitId).overrideWith(
        () => _SeededVisitBillingFlowNotifier(
          _visitId,
          billingState ??
              VisitBillingFlowState(
                step: VisitBillingStep.invoice,
                selectedLines: [_selectedLine()],
                invoicePreviewNumber: 'INV-TEST-0001',
              ),
        ),
      ),
    visitDocumentationProvider(_visitId).overrideWith(
      () => _SeededVisitDocumentationNotifier(_visitId, sampleEncounterDocState()),
    ),
    patientDetailProvider(encounterTestPatientId).overrideWith((ref) async => _patient()),
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
  group('VisitInvoiceReviewStep', () {
    testWidgets('builds invoice card and discount sidebar', (tester) async {
      await _pumpReviewStep(tester, overrides: _reviewOverrides());

      expect(find.text('Review invoice'), findsOneWidget);
      expect(find.text('Discount'), findsWidgets);
      expect(find.text('Consultation'), findsOneWidget);
      expect(find.text('Discount type'), findsOneWidget);
    });

    testWidgets('shows discount controls only when apply-discount permission is granted', (tester) async {
      await _pumpReviewStep(
        tester,
        overrides: _reviewOverrides(permissions: RolePermissionSeed.administrator),
      );

      expect(find.text('Discount type'), findsOneWidget);
      expect(find.text('No discount'), findsOneWidget);

      await _pumpReviewStep(
        tester,
        overrides: _reviewOverrides(permissions: RolePermissionSeed.receptionist),
      );

      expect(find.text('Discount type'), findsNothing);
      expect(
        find.text(
          'Finalizing issues the invoice linked to this visit. Payment can be recorded from the patient billing tab.',
        ),
        findsWidgets,
      );
    });

    testWidgets('fixed discount above subtotal shows warning without blocking finalize', (tester) async {
      var finalizeTapped = false;

      await _pumpReviewStep(
        tester,
        overrides: _reviewOverrides(
          billingState: VisitBillingFlowState(
            step: VisitBillingStep.invoice,
            selectedLines: [_selectedLine(unitPrice: 50)],
            invoicePreviewNumber: 'INV-TEST-0001',
            discountType: VisitBillingDiscountType.fixed,
            discountValue: 100,
          ),
        ),
        onFinalize: () => finalizeTapped = true,
      );

      expect(find.text('Amount exceeds invoice subtotal'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Finalize visit & invoice'));
      await tester.pump();

      expect(finalizeTapped, isTrue);
    });

    testWidgets('changing discount type resets the rendered value field', (tester) async {
      await _pumpReviewStep(
        tester,
        overrides: _reviewOverrides(overrideBilling: false),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(VisitInvoiceReviewStep)),
      );
      final notifier = container.read(visitBillingFlowProvider(_visitId).notifier);
      notifier.setDiscountType(VisitBillingDiscountType.fixed);
      notifier.setDiscountValue(25);
      await tester.pump();

      expect(find.text('Amount off'), findsOneWidget);

      await tester.tap(find.text('Percentage off'));
      await tester.pump();

      expect(container.read(visitBillingFlowProvider(_visitId)).discountValue, 0);
      expect(
        container.read(visitBillingFlowProvider(_visitId)).discountType,
        VisitBillingDiscountType.percentage,
      );
      expect(find.text('Percentage'), findsOneWidget);
      expect(find.text('Amount off'), findsNothing);
    });

    testWidgets('Edit services invokes its callback', (tester) async {
      var backTapped = false;

      await _pumpReviewStep(
        tester,
        overrides: _reviewOverrides(),
        onBack: () => backTapped = true,
      );

      await tester.tap(find.widgetWithText(AppButton, 'Edit services'));
      await tester.pump();

      expect(backTapped, isTrue);
    });

    testWidgets('Finalize visit & invoice is disabled while submitting', (tester) async {
      await _pumpReviewStep(
        tester,
        overrides: _reviewOverrides(),
        isSubmitting: true,
        onFinalize: () {},
      );

      final finalize = _button(tester, 'Finalize visit & invoice');
      expect(finalize.onPressed, isNull);
      expect(finalize.loading, isTrue);
    });
  });
}
