import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_editor_notifier.dart'
    show InvoiceEditorStatus, invoiceEditorProvider;
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

void main() {
  const invoiceId = BillingRpcTestClient.draftInvoiceId;
  const branchId = '44444444-4444-4444-8444-444444444444';

  late BillingRpcTestClient client;
  late ProviderContainer container;

  setUp(() {
    client = BillingRpcTestClient();
    container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(
          () => _PresetAuth(
            AuthSessionState(
              status: AuthSessionStatus.authenticated,
              context: sampleAuthSessionContext(
                permissions: {PermissionKeys.invoicesView, PermissionKeys.invoicesCreate},
                activeBranchId: branchId,
                branchIds: [branchId],
              ),
            ),
          ),
        ),
        invoiceRepositoryProvider.overrideWith((ref) => InvoiceRepository(client)),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('issue with STALE_INVOICE sets stale status and reloads detail', () async {
    client.rpcResults['issue_invoice'] = {'success': false, 'error_code': 'STALE_INVOICE', 'error_message': 'Stale'};

    final notifier = container.read(invoiceEditorProvider(invoiceId).notifier);
    await container.read(invoiceEditorProvider(invoiceId).future);

    final callsBefore = client.rpcLog.where((name) => name == 'get_invoice_detail').length;
    final invoiceNumber = await notifier.issue();

    expect(invoiceNumber, isNull);
    expect(client.rpcLog, contains('issue_invoice'));
    expect(client.rpcLog.where((name) => name == 'get_invoice_detail').length, greaterThan(callsBefore));
  });

  test('loads issued invoice in read-only state without throwing', () async {
    final state = await container.read(invoiceEditorProvider(BillingRpcTestClient.issuedInvoiceId).future);

    expect(state.detail.status.name, 'issued');
    expect(state.isDraft, isFalse);
    expect(state.editorStatus, InvoiceEditorStatus.idle);
  });

  test('addItem with STALE_INVOICE reloads detail and returns false', () async {
    client.rpcResults['add_invoice_item'] = {'success': false, 'error_code': 'STALE_INVOICE', 'error_message': 'Stale'};

    final notifier = container.read(invoiceEditorProvider(invoiceId).notifier);
    await container.read(invoiceEditorProvider(invoiceId).future);

    final callsBefore = client.rpcLog.where((name) => name == 'get_invoice_detail').length;
    final success = await notifier.addItem(description: 'Test', quantity: '1', unitPrice: '10');

    expect(success, isFalse);
    expect(client.rpcLog, contains('add_invoice_item'));
    expect(client.rpcLog.where((name) => name == 'get_invoice_detail').length, greaterThan(callsBefore));
  });
}
