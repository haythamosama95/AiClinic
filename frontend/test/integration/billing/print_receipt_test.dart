import 'dart:typed_data';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_detail_page.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/receipt_print_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/billing_rpc_test_client.dart';

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

void main() {
  testWidgets('print action on invoice detail invokes receipt layout', (tester) async {
    final client = BillingRpcTestClient();
    Uint8List? captured;

    final defaultHandler = ReceiptPrintPreview.printHandler;
    ReceiptPrintPreview.printHandler = (layout) async {
      captured = await layout(PdfPageFormat.letter);
    };
    addTearDown(() {
      ReceiptPrintPreview.printHandler = defaultHandler;
    });

    await tester.binding.setSurfaceSize(const Size(1100, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuth(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  permissions: {PermissionKeys.invoicesView},
                  activeBranchId: '44444444-4444-4444-8444-444444444444',
                  branchIds: ['44444444-4444-4444-8444-444444444444'],
                ),
              ),
            ),
          ),
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
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('invoice_print_button')));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.length, greaterThan(500));
  });
}
