// US6 acceptance scenarios 1–5.
import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/billing_rpc_test_client.dart';

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

Future<void> _pumpHost(WidgetTester tester, Widget host) async {
  await tester.binding.setSurfaceSize(const Size(1100, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host);
  await tester.pump();
  await tester.pumpAndSettle();
}

AuthSessionState _auth({Set<String>? permissions}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions:
          permissions ?? {PermissionKeys.invoicesView, PermissionKeys.invoicesVoid, PermissionKeys.paymentsRecord},
      activeBranchId: '44444444-4444-4444-8444-444444444444',
      branchIds: ['44444444-4444-4444-8444-444444444444'],
    ),
  );
}

Widget _scope({required BillingRpcTestClient client, AuthSessionState? auth}) {
  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(auth ?? _auth())),
      invoiceRepositoryProvider.overrideWith((ref) => InvoiceRepository(client)),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: AppRoutes.billingInvoiceDetail(BillingRpcTestClient.issuedInvoiceId),
        routes: [
          GoRoute(
            path: AppRoutes.billingInvoiceDetail(BillingRpcTestClient.issuedInvoiceId),
            builder: (context, state) => const InvoiceDetailPage(invoiceId: BillingRpcTestClient.issuedInvoiceId),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('Void invoice US6', () {
    testWidgets('scenario 1: void issued invoice with mandatory reason', (tester) async {
      final client = BillingRpcTestClient();

      await _pumpHost(tester, _scope(client: client));

      expect(find.byKey(const Key('invoice_void_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('invoice_void_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('void_reason_field')), 'Created in error');
      await tester.tap(find.byKey(const Key('void_invoice_confirm_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('void_invoice'));
      expect(client.issuedStatus, 'voided');
      expect(find.byKey(const Key('invoice_void_reason_banner')), findsOneWidget);
      expect(find.textContaining('Created in error'), findsWidgets);
    });

    testWidgets('scenario 2: paid invoice cannot be voided from UI', (tester) async {
      final client = BillingRpcTestClient()..issuedStatus = 'paid';

      await _pumpHost(tester, _scope(client: client));

      expect(find.byKey(const Key('invoice_void_button')), findsNothing);
    });

    testWidgets('scenario 3: voided invoice rejects further payment', (tester) async {
      final client = BillingRpcTestClient()
        ..issuedStatus = 'voided'
        ..issuedVoidReason = 'Already voided';

      await _pumpHost(
        tester,
        _scope(
          client: client,
          auth: _auth(permissions: {PermissionKeys.invoicesView, PermissionKeys.paymentsRecord}),
        ),
      );

      expect(find.byKey(const Key('payment_form_card')), findsNothing);
    });

    testWidgets('scenario 4: user without void permission sees no void action', (tester) async {
      final client = BillingRpcTestClient();

      await _pumpHost(
        tester,
        _scope(
          client: client,
          auth: _auth(permissions: {PermissionKeys.invoicesView, PermissionKeys.paymentsRecord}),
        ),
      );

      expect(find.byKey(const Key('invoice_void_button')), findsNothing);
    });

    testWidgets('scenario 5: void dialog requires non-empty reason', (tester) async {
      final client = BillingRpcTestClient();

      await _pumpHost(tester, _scope(client: client));
      await tester.tap(find.byKey(const Key('invoice_void_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('void_invoice_confirm_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog.where((name) => name == 'void_invoice'), isEmpty);
      expect(find.text('Enter a reason before voiding.'), findsOneWidget);
    });
  });
}
