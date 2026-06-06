import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/data/insurance_provider_repository.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/billing_rpc_test_client.dart';

void main() {
  group('InsurancePanel', () {
    testWidgets('shows empty state when no active providers are configured', (tester) async {
      final client = BillingRpcTestClient();
      client.insuranceProviders.clear();

      await _pumpEditor(tester, client: client);
      await _addSampleItem(tester);

      expect(find.byKey(const Key('insurance_panel_empty_state')), findsOneWidget);
      expect(find.byKey(const Key('insurance_provider_selector')), findsNothing);
    });

    testWidgets('selects provider and saves covered amount', (tester) async {
      final client = BillingRpcTestClient();
      await _pumpEditor(tester, client: client);
      await _addSampleItem(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('insurance_provider_selector')),
        48,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('insurance_provider_selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme Insurance').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('insurance_covered_amount')), '40');
      await tester.tap(find.byKey(const Key('insurance_apply_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog.where((name) => name == 'set_insurance_coverage').length, 1);
      expect(client.draftInsuranceProviderId, BillingRpcTestClient.insuranceProviderId);
      expect(client.draftInsuranceCoveredAmount, '40.00');
      expect(find.textContaining('Patient due: 60.00 USD'), findsWidgets);
    });

    testWidgets('clears saved insurance coverage', (tester) async {
      final client = BillingRpcTestClient();
      await _pumpEditor(tester, client: client);
      await _addSampleItem(tester);

      await _applyCoverage(tester, amount: '25');
      await tester.tap(find.byKey(const Key('insurance_clear_button')));
      await tester.pumpAndSettle();

      expect(client.draftInsuranceProviderId, isNull);
      expect(client.draftInsuranceCoveredAmount, '0');
    });
  });
}

Future<void> _applyCoverage(WidgetTester tester, {required String amount}) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('insurance_provider_selector')),
    48,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('insurance_provider_selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Acme Insurance').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('insurance_covered_amount')), amount);
  await tester.tap(find.byKey(const Key('insurance_apply_button')));
  await tester.pumpAndSettle();
}

Future<void> _pumpEditor(WidgetTester tester, {required BillingRpcTestClient client}) async {
  await tester.binding.setSurfaceSize(const Size(1100, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(
          () => _PresetAuth(
            AuthSessionState(
              status: AuthSessionStatus.authenticated,
              context: sampleAuthSessionContext(
                permissions: {PermissionKeys.invoicesView, PermissionKeys.invoicesCreate},
                activeBranchId: '44444444-4444-4444-8444-444444444444',
                branchIds: ['44444444-4444-4444-8444-444444444444'],
              ),
            ),
          ),
        ),
        invoiceRepositoryProvider.overrideWith((ref) => InvoiceRepository(client)),
        insuranceProviderRepositoryProvider.overrideWith((ref) => InsuranceProviderRepository(client)),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const InvoiceEditorPage(invoiceId: BillingRpcTestClient.draftInvoiceId),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _addSampleItem(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('invoice_item_description')), 'Consultation');
  await tester.enterText(find.byKey(const Key('invoice_item_unit_price')), '100');
  await tester.tap(find.byKey(const Key('invoice_item_add_button')));
  await tester.pumpAndSettle();
}

class _PresetAuth extends TestAuthSessionNotifier {
  _PresetAuth(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
