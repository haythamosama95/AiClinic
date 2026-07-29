import 'dart:async';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_data_table.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_controls.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_filters.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_sort_key.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_list_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import '../../support/billing_rpc_test_client.dart';

void main() {
  group('InvoiceListNotifier access control', () {
    test('unauthenticated user gets empty state without issuing RPC', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(const AuthSessionState(status: AuthSessionStatus.unauthenticated)),
          ),
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(invoiceListProvider.future);

      expect(state.items, isEmpty);
      expect(state.hasInvoices, isFalse);
      expect(state.isNoInvoicesYet, isTrue);
      expect(state.isNoMatch, isFalse);
      expect(client.rpcLog, isEmpty);
    });

    test('user without invoices.view gets empty state without issuing RPC', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.doctor,
                  permissions: {PermissionKeys.patientsView},
                ),
              ),
            ),
          ),
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(invoiceListProvider.future);

      expect(state.items, isEmpty);
      expect(state.hasInvoices, isFalse);
      expect(client.rpcLog, isEmpty);
    });
  });

  group('InvoiceListNotifier loading', () {
    late BillingRpcTestClient client;

    ProviderContainer authorizedContainer({BillingRpcTestClient? rpcClient, AuthSessionNotifier? auth}) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => auth ?? _PresetAuthSessionNotifier(_authorizedSession()),
          ),
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(rpcClient ?? client)),
        ],
      );
    }

    setUp(() {
      client = BillingRpcTestClient();
    });

    test('forwards filters, limit, and offset to list_invoices', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final container = authorizedContainer(
        auth: _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(
              permissions: RolePermissionSeed.receptionist,
              branchIds: [branchId],
            ),
          ),
        ),
      );
      addTearDown(container.dispose);

      await container.read(invoiceListProvider.notifier).applyFilters(
            const InvoiceListFilters(
              patientSearch: 'patient',
              statuses: ['issued'],
              page: 2,
              pageSize: 5,
            ),
          );

      final params = client.lastParams;
      final filters = params?['p_filters'] as Map?;
      expect(params?['p_limit'], 5);
      expect(params?['p_offset'], 5);
      expect(filters?['patient_search'], 'patient');
      expect(filters?['statuses'], ['issued']);
      expect(filters?['branch_ids'], [branchId]);
    });

    test('applyFilters exposes new filters while keeping previous items during fetch', () async {
      final slowClient = _SlowBillingRpcTestClient(delay: const Duration(milliseconds: 100));
      final container = authorizedContainer(rpcClient: slowClient);
      addTearDown(container.dispose);

      await container.read(invoiceListProvider.future);
      final initialItems = container.read(invoiceListProvider).requireValue.items;
      expect(initialItems, isNotEmpty);

      final applyFuture = container.read(invoiceListProvider.notifier).applyFilters(
            const InvoiceListFilters(patientSearch: 'slow-filter', pageSize: 10),
          );

      final interim = container.read(invoiceListProvider).requireValue;
      expect(interim.filters.patientSearch, 'slow-filter');
      expect(interim.items, initialItems);

      await applyFuture;
    });

    test('applyControls delegates through toBackendFilters', () async {
      const branchId = '77777777-7777-4777-8777-777777777777';
      final container = authorizedContainer();
      addTearDown(container.dispose);

      await container.read(invoiceListProvider.notifier).applyControls(
            const InvoiceListControls(
              search: 'Other Patient',
              status: InvoiceStatus.paid,
              branch: branchId,
              sort: InvoiceSortKey.dateAsc,
              page: 1,
              pageSize: 10,
            ),
            multiBranch: true,
          );

      final filters = client.lastParams?['p_filters'] as Map?;
      expect(filters?['patient_search'], 'Other Patient');
      expect(filters?['statuses'], ['paid']);
      expect(filters?['branch_ids'], [branchId]);
      expect(filters?['sort_field'], 'created_at');
      expect(filters?['sort_direction'], 'asc');
    });

    test('reload preserves the current filters', () async {
      final container = authorizedContainer();
      addTearDown(container.dispose);

      const filters = InvoiceListFilters(
        patientSearch: 'needle',
        page: 3,
        pageSize: 4,
      );
      await container.read(invoiceListProvider.notifier).applyFilters(filters);
      client.rpcLog.clear();

      await container.read(invoiceListProvider.notifier).reload();

      expect(client.lastParams?['p_limit'], 4);
      expect(client.lastParams?['p_offset'], 8);
      expect((client.lastParams?['p_filters'] as Map?)?['patient_search'], 'needle');
    });

    test('active branch change re-triggers build and reloads', () async {
      const branchA = '00000000-0000-4000-8000-000000000001';
      const branchB = '00000000-0000-4000-8000-000000000002';
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            permissions: RolePermissionSeed.receptionist,
            branchIds: [branchA, branchB],
            activeBranchId: branchA,
          ),
        ),
      );
      final container = authorizedContainer(auth: auth);
      addTearDown(container.dispose);

      await container.read(invoiceListProvider.future);
      expect(client.rpcLog.where((fn) => fn == 'list_invoices'), hasLength(1));

      auth.replace(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            permissions: RolePermissionSeed.receptionist,
            branchIds: [branchA, branchB],
            activeBranchId: branchB,
          ),
        ),
      );
      await container.read(invoiceListProvider.future);

      expect(client.rpcLog.where((fn) => fn == 'list_invoices'), hasLength(2));
    });
  });

  group('InvoiceListNotifier empty states', () {
    test('pristine probe sets hasInvoices and stays sticky across filtered-empty loads', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(_authorizedSession())),
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      final loaded = await container.read(invoiceListProvider.future);
      expect(loaded.hasInvoices, isTrue);
      expect(loaded.isEmpty, isFalse);
      expect(loaded.isNoInvoicesYet, isFalse);
      expect(loaded.isNoMatch, isFalse);

      await container.read(invoiceListProvider.notifier).applyFilters(
            const InvoiceListFilters(statuses: ['voided']),
          );
      final filtered = container.read(invoiceListProvider).requireValue;

      expect(filtered.items, isEmpty);
      expect(filtered.hasInvoices, isTrue);
      expect(filtered.isNoInvoicesYet, isFalse);
      expect(filtered.isNoMatch, isTrue);
    });

    test('empty clinic yields isNoInvoicesYet until invoices exist', () async {
      final client = BillingRpcTestClient();
      client.catalogInvoices.clear();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(_authorizedSession())),
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(invoiceListProvider.future);

      expect(state.items, isEmpty);
      expect(state.hasInvoices, isFalse);
      expect(state.isEmpty, isTrue);
      expect(state.isNoInvoicesYet, isTrue);
      expect(state.isNoMatch, isFalse);
    });

    test('computed getters cover loaded, empty-clinic, and no-match combinations', () {
      final loadedItem = InvoiceListItem.fromRow(BillingRpcTestClient().catalogInvoices.first)!;

      final loaded = InvoiceListUiState(
        items: [loadedItem],
        hasMore: false,
        filters: const InvoiceListFilters(),
        estimatedTotal: 1,
        hasInvoices: true,
      );
      const emptyClinic = InvoiceListUiState(
        items: [],
        hasMore: false,
        filters: InvoiceListFilters(),
        estimatedTotal: 0,
        hasInvoices: false,
      );
      const noMatch = InvoiceListUiState(
        items: [],
        hasMore: false,
        filters: InvoiceListFilters(statuses: ['voided']),
        estimatedTotal: 0,
        hasInvoices: true,
      );

      expect(loaded.isEmpty, isFalse);
      expect(loaded.isNoInvoicesYet, isFalse);
      expect(loaded.isNoMatch, isFalse);

      expect(emptyClinic.isEmpty, isTrue);
      expect(emptyClinic.isNoInvoicesYet, isTrue);
      expect(emptyClinic.isNoMatch, isFalse);

      expect(noMatch.isEmpty, isTrue);
      expect(noMatch.isNoInvoicesYet, isFalse);
      expect(noMatch.isNoMatch, isTrue);
    });
  });

  group('InvoiceListNotifier pagination and sorting', () {
    test('estimatedTotal equals offset + item count + hasMore hint', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(_authorizedSession())),
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(invoiceListProvider.notifier).applyFilters(
            const InvoiceListFilters(pageSize: 1),
          );
      final state = container.read(invoiceListProvider).requireValue;

      expect(state.items, hasLength(1));
      expect(state.hasMore, isTrue);
      expect(state.estimatedTotal, state.filters.offset + state.items.length + 1);
    });

    test('applies client-side sorting to loaded items', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(_authorizedSession())),
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(invoiceListProvider.notifier).applyFilters(
            const InvoiceListFilters(
              sortField: InvoiceSortField.createdAt,
              sortDirection: SortDirection.asc,
              pageSize: 10,
            ),
          );
      final items = container.read(invoiceListProvider).requireValue.items;

      expect(items.first.invoiceNumber, 'INV-MAIN-000002');
      expect(items.last.invoiceNumber, 'INV-SIDE-000001');
    });
  });

  group('InvoiceListNotifier errors', () {
    test('repository failure surfaces as AsyncError', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(_authorizedSession())),
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(invoiceListProvider.future);

      client.rpcResults['list_invoices'] = {
        'success': false,
        'error_code': 'NETWORK',
        'error_message': 'offline',
      };
      await container.read(invoiceListProvider.notifier).reload();

      final state = container.read(invoiceListProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isNotNull);
    });
  });
}

AuthSessionState _authorizedSession() {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(permissions: RolePermissionSeed.receptionist),
  );
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _SlowBillingRpcTestClient extends BillingRpcTestClient {
  _SlowBillingRpcTestClient({required this.delay});

  final Duration delay;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'list_invoices') {
      final inner = super.rpc<T>(fn, params: params, get: get);
      return _DelayedPostgrestRpcWrapper(inner, delay) as PostgrestFilterBuilder<T>;
    }
    return super.rpc<T>(fn, params: params, get: get);
  }
}

class _DelayedPostgrestRpcWrapper extends Fake implements PostgrestFilterBuilder<dynamic> {
  _DelayedPostgrestRpcWrapper(this._inner, this.delay);

  final PostgrestFilterBuilder<dynamic> _inner;
  final Duration delay;

  @override
  Future<U> then<U>(FutureOr<U> Function(dynamic value) onValue, {Function? onError}) {
    return Future<void>.delayed(delay).then((_) => _inner.then(onValue, onError: onError));
  }
}
