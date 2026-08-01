import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_list_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import '../../support/billing_rpc_test_client.dart';
import '../../support/fake_postgrest_rpc.dart';

void main() {
  const patientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  const issuedInvoiceId = BillingRpcTestClient.issuedInvoiceId;

  group('invoiceDetailViewProvider', () {
    late BillingRpcTestClient client;

    setUp(() {
      client = BillingRpcTestClient();
    });

    ProviderContainer createContainer(AuthSessionState authState) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(authState)),
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
      );
    }

    test('empty or whitespace invoice id throws StateError without RPC', () async {
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(permissions: RolePermissionSeed.administrator),
        ),
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(invoiceDetailViewProvider('').future),
        throwsA(
          isA<StateError>().having((error) => error.message, 'message', 'Invoice id is required.'),
        ),
      );
      await expectLater(
        container.read(invoiceDetailViewProvider('   ').future),
        throwsA(
          isA<StateError>().having((error) => error.message, 'message', 'Invoice id is required.'),
        ),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('successful fetch populates invoice and administrator permission flags', () async {
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            role: StaffRole.administrator,
            permissions: RolePermissionSeed.administrator,
          ),
        ),
      );
      addTearDown(container.dispose);

      final view = await container.read(invoiceDetailViewProvider(issuedInvoiceId).future);

      expect(view.invoice.id, issuedInvoiceId);
      expect(view.canCreate, isTrue);
      expect(view.canApplyDiscount, isTrue);
      expect(view.canVoid, isTrue);
      expect(view.canRecordPayment, isTrue);
      expect(view.canRefund, isTrue);
      expect(client.lastFunction, 'get_invoice_detail');
    });

    test('successful fetch populates doctor permission flags as false', () async {
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            role: StaffRole.doctor,
            permissions: RolePermissionSeed.doctor,
          ),
        ),
      );
      addTearDown(container.dispose);

      final view = await container.read(invoiceDetailViewProvider(issuedInvoiceId).future);

      expect(view.invoice.id, issuedInvoiceId);
      expect(view.canCreate, isFalse);
      expect(view.canApplyDiscount, isFalse);
      expect(view.canVoid, isFalse);
      expect(view.canRecordPayment, isFalse);
      expect(view.canRefund, isFalse);
    });

    test('receptionist permission flags reflect partial billing grants', () async {
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            role: StaffRole.receptionist,
            permissions: RolePermissionSeed.receptionist,
          ),
        ),
      );
      addTearDown(container.dispose);

      final view = await container.read(invoiceDetailViewProvider(issuedInvoiceId).future);

      expect(view.canCreate, isTrue);
      expect(view.canRecordPayment, isTrue);
      expect(view.canApplyDiscount, isFalse);
      expect(view.canVoid, isFalse);
      expect(view.canRefund, isFalse);
    });

    test('repository failure surfaces as an error', () async {
      client.rpcResults['get_invoice_detail'] = {
        'success': false,
        'error_code': 'NOT_FOUND',
        'error_message': 'Invoice not found.',
      };
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(permissions: {PermissionKeys.invoicesView}),
        ),
      );
      addTearDown(container.dispose);

<<<<<<< HEAD
      await expectLater(
        container.read(invoiceDetailViewProvider(issuedInvoiceId).future),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'NOT_FOUND')),
=======
      final provider = invoiceDetailViewProvider(issuedInvoiceId);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      container.read(provider);
      await pumpEventQueue();

      final asyncValue = container.read(provider);
      expect(asyncValue.hasError, isTrue);
      expect(
        asyncValue.error,
        isA<RpcFailure>().having((error) => error.code, 'code', 'NOT_FOUND'),
>>>>>>> master
      );
    });
  });

  group('patientInvoicesProvider', () {
    const enrichInvoiceId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const draftInvoiceId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    const zeroPaidInvoiceId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
    const paidWithPaymentsId = BillingRpcTestClient.issuedInvoiceId;

    late _EnrichmentBillingClient client;

    setUp(() {
      client = _EnrichmentBillingClient();
      client.catalogInvoices
        ..clear()
        ..addAll([
          {
            'id': paidWithPaymentsId,
            'invoice_number': 'INV-MAIN-000001',
            'status': 'issued',
            'patient_display_name': 'Test Patient',
            'branch_code': 'MAIN',
            'branch_id': '44444444-4444-4444-8444-444444444444',
            'patient_id': patientId,
            'subtotal': '100',
            'discount_amount': '0',
            'insurance_covered_amount': '0',
            'paid_amount': '50.00',
            'balance': '50.00',
            'currency': 'USD',
            'created_at': '2026-06-02T10:00:00.000Z',
            'issued_at': '2026-06-02T11:00:00.000Z',
            'payments': [
              {
                'id': 'pay-existing',
                'method': 'cash',
                'amount': '50.00',
                'note': null,
                'recorded_by': {'id': 'staff-1', 'display_name': 'Reception'},
                'recorded_at': '2026-06-02T12:00:00.000Z',
              },
            ],
          },
          {
            'id': draftInvoiceId,
            'invoice_number': null,
            'status': 'draft',
            'patient_display_name': 'Test Patient',
            'branch_code': 'MAIN',
            'branch_id': '44444444-4444-4444-8444-444444444444',
            'patient_id': patientId,
            'subtotal': '0',
            'discount_amount': '0',
            'insurance_covered_amount': '0',
            'paid_amount': '25.00',
            'balance': '25.00',
            'currency': 'USD',
            'created_at': '2026-06-01T10:00:00.000Z',
            'issued_at': null,
            'payments': [],
          },
          {
            'id': zeroPaidInvoiceId,
            'invoice_number': 'INV-MAIN-000003',
            'status': 'issued',
            'patient_display_name': 'Test Patient',
            'branch_code': 'MAIN',
            'branch_id': '44444444-4444-4444-8444-444444444444',
            'patient_id': patientId,
            'subtotal': '30',
            'discount_amount': '0',
            'insurance_covered_amount': '0',
            'paid_amount': '0',
            'balance': '30.00',
            'currency': 'USD',
            'created_at': '2026-05-31T10:00:00.000Z',
            'issued_at': '2026-05-31T11:00:00.000Z',
            'payments': [],
          },
          {
            'id': enrichInvoiceId,
            'invoice_number': 'INV-MAIN-000004',
            'status': 'issued',
            'patient_display_name': 'Test Patient',
            'branch_code': 'MAIN',
            'branch_id': '44444444-4444-4444-8444-444444444444',
            'patient_id': patientId,
            'subtotal': '60',
            'discount_amount': '0',
            'insurance_covered_amount': '0',
            'paid_amount': '60.00',
            'balance': '0.00',
            'currency': 'USD',
            'created_at': '2026-05-30T10:00:00.000Z',
            'issued_at': '2026-05-30T11:00:00.000Z',
            'payments': [],
          },
        ]);
    });

    ProviderContainer createContainer(AuthSessionState authState) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(authState)),
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
      );
    }

    test('unauthorized session returns empty result without RPC', () async {
      final container = createContainer(const AuthSessionState(status: AuthSessionStatus.authenticated));
      addTearDown(container.dispose);

      final page = await container.read(patientInvoicesProvider(patientId).future);

      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
      expect(client.rpcLog, isEmpty);
    });

    test('authorized session returns patient invoices', () async {
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(permissions: {PermissionKeys.invoicesView}),
        ),
      );
      addTearDown(container.dispose);

      final page = await container.read(patientInvoicesProvider(patientId).future);

      expect(page.items, hasLength(4));
      expect(page.hasMore, isFalse);
      expect(client.rpcLog, contains('list_patient_invoices'));
    });

    test('enrichment skips items that already have payments, drafts, and zero-paid rows', () async {
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(permissions: {PermissionKeys.invoicesView}),
        ),
      );
      addTearDown(container.dispose);

      final page = await container.read(patientInvoicesProvider(patientId).future);

      final paidWithPayments = page.items.firstWhere((item) => item.id == paidWithPaymentsId);
      expect(paidWithPayments.payments, hasLength(1));
      expect(paidWithPayments.payments.first.id, 'pay-existing');

      final draft = page.items.firstWhere((item) => item.id == draftInvoiceId);
      expect(draft.status, InvoiceStatus.draft);
      expect(draft.payments, isEmpty);

      final zeroPaid = page.items.firstWhere((item) => item.id == zeroPaidInvoiceId);
      expect(zeroPaid.paidAmount.isZero, isTrue);
      expect(zeroPaid.insuranceCoveredAmount.isZero, isTrue);
      expect(zeroPaid.payments, isEmpty);

      expect(client.detailFetchIds, [enrichInvoiceId]);
    });

    test('enrichment loads payments for qualifying invoices', () async {
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(permissions: {PermissionKeys.invoicesView}),
        ),
      );
      addTearDown(container.dispose);

      final page = await container.read(patientInvoicesProvider(patientId).future);
      final enriched = page.items.firstWhere((item) => item.id == enrichInvoiceId);

      expect(enriched.payments, hasLength(1));
      expect(enriched.payments.first.id, 'pay-enriched');
      expect(enriched.payments.first.amount.wireValue, '60.00');
    });

    test('enrichment returns the original item when getDetail fails', () async {
      client.failDetailForInvoiceId = enrichInvoiceId;
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(permissions: {PermissionKeys.invoicesView}),
        ),
      );
      addTearDown(container.dispose);

      final page = await container.read(patientInvoicesProvider(patientId).future);
      final original = page.items.firstWhere((item) => item.id == enrichInvoiceId);

      expect(original.payments, isEmpty);
      expect(original.paidAmount.wireValue, '60.00');
    });
  });

  group('refreshInvoiceBillingSurfaces', () {
    testWidgets('invalidates detail, patient invoices, and list surfaces', (tester) async {
      late WidgetRef widgetRef;
      final client = BillingRpcTestClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuthSessionNotifier(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(permissions: RolePermissionSeed.administrator),
                ),
              ),
            ),
            invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              widgetRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await widgetRef.read(invoiceDetailViewProvider(issuedInvoiceId).future);
      await widgetRef.read(patientInvoicesProvider(patientId).future);
      await widgetRef.read(invoiceListProvider.future);
      client.rpcLog.clear();

      await refreshInvoiceBillingSurfaces(
        widgetRef,
        invoiceId: issuedInvoiceId,
        patientId: patientId,
      );

      expect(client.rpcLog, containsAll(['get_invoice_detail', 'list_patient_invoices', 'list_invoices']));
    });
  });
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _EnrichmentBillingClient extends BillingRpcTestClient {
  final List<String> detailFetchIds = <String>[];
  String? failDetailForInvoiceId;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'get_invoice_detail') {
      final invoiceId = params?['p_invoice_id']?.toString();
      if (invoiceId != null) {
        detailFetchIds.add(invoiceId);
      }
      if (invoiceId == failDetailForInvoiceId) {
        return FakePostgrestRpc({
          'success': false,
          'error_code': 'RPC_ERROR',
          'error_message': 'Detail unavailable.',
        }) as PostgrestFilterBuilder<T>;
      }
      if (invoiceId == 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') {
        return FakePostgrestRpc({
          'success': true,
          'data': {
            'invoice': {
              'id': invoiceId,
              'invoice_number': 'INV-MAIN-000004',
              'status': 'issued',
              'branch_id': '44444444-4444-4444-8444-444444444444',
              'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
              'visit_id': BillingRpcTestClient.visitId,
              'subtotal': '60.00',
              'discount_amount': '0',
              'insurance_covered_amount': '0',
              'balance': '0.00',
              'currency': 'USD',
              'created_at': '2026-05-30T10:00:00.000Z',
              'updated_at': '2026-05-30T11:00:00.000Z',
              'issued_at': '2026-05-30T11:00:00.000Z',
            },
            'items': [],
            'payments': [
              {
                'id': 'pay-enriched',
                'method': 'cash',
                'amount': '60.00',
                'note': null,
                'recorded_by': {'id': 'staff-1', 'display_name': 'Reception'},
                'recorded_at': '2026-05-30T12:00:00.000Z',
              },
            ],
            'patient': {
              'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
              'display_name': 'Test Patient',
              'mrn': 'MRN-000001',
            },
            'branch': {
              'id': '44444444-4444-4444-8444-444444444444',
              'code': 'MAIN',
              'name': 'Main',
            },
          },
        }) as PostgrestFilterBuilder<T>;
      }
    }

    return super.rpc<T>(fn, params: params, get: get);
  }
}
