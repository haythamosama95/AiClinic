import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_detail_page.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/billing_rpc_test_client.dart';

void main() {
  group('Billing access denied views', () {
    testWidgets('invoice list shows denial without invoices.view', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuth(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}),
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: InvoiceListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Invoices'), findsOneWidget);
      expect(find.text('You do not have permission to view invoices.'), findsOneWidget);
      expect(find.text('Invoice list will appear here.'), findsNothing);
    });

    testWidgets('invoice detail shows denial without invoices.view', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuth(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(permissions: {PermissionKeys.paymentsRecord}),
                ),
              ),
            ),
            invoiceRepositoryProvider.overrideWith((ref) => InvoiceRepository(BillingRpcTestClient())),
          ],
          child: MaterialApp(home: InvoiceDetailPage(invoiceId: BillingRpcTestClient.issuedInvoiceId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You do not have permission to view invoices.'), findsOneWidget);
      expect(find.byKey(const Key('payment_form_card')), findsNothing);
    });
  });
}

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}
