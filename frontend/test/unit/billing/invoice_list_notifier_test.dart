import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_list_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/billing_rpc_test_client.dart';

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

Future<void> _waitForListLoad(ProviderContainer container) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    final state = container.read(invoiceListProvider);
    if (!state.loading) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('invoice list did not finish loading');
}

void main() {
  test('uses backend has_more instead of page length heuristic', () async {
    final client = BillingRpcTestClient();
    for (var index = 0; index < 27; index++) {
      client.catalogInvoices.add({
        'id': 'aaaaaaaa-aaaa-4aaa-8aaa-${index.toString().padLeft(12, '0')}',
        'invoice_number': 'INV-MAIN-${(100 + index).toString().padLeft(6, '0')}',
        'status': 'issued',
        'patient_display_name': 'Paged Patient $index',
        'branch_code': 'MAIN',
        'branch_id': '44444444-4444-4444-8444-444444444444',
        'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'subtotal': '10',
        'discount_amount': '0',
        'insurance_covered_amount': '0',
        'paid_amount': '0',
        'balance': '10.00',
        'created_at': '2026-06-0${(index % 9) + 1}T10:00:00.000Z',
        'issued_at': '2026-06-0${(index % 9) + 1}T11:00:00.000Z',
      });
    }
    late ProviderContainer container;
    container = ProviderContainer(
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
    );

    container.read(invoiceListProvider);
    await _waitForListLoad(container);

    final initial = container.read(invoiceListProvider);
    expect(initial.items, hasLength(25));
    expect(initial.hasMore, isTrue);

    await container.read(invoiceListProvider.notifier).loadMore();
    final afterLoadMore = container.read(invoiceListProvider);
    expect(afterLoadMore.items.length, greaterThan(25));
    expect(afterLoadMore.hasMore, isFalse);
    expect(client.rpcLog.where((name) => name == 'list_invoices').length, 2);

    container.dispose();
  });
}
