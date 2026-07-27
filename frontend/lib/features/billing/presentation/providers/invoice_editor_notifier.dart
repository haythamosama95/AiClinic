import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/invoice_item_repository.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/discount_scope.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_stale_exception.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';

@immutable
class InvoiceEditorState {
  const InvoiceEditorState({required this.invoice, this.isMutating = false});

  final InvoiceDetail invoice;
  final bool isMutating;

  bool get hasLineDiscounts => invoice.items.any((item) => !item.lineDiscountAmount.isZero);

  bool get hasInvoiceDiscount => !invoice.discountAmount.isZero;

  DiscountScope? get activeDiscountScope {
    if (hasLineDiscounts) {
      return DiscountScope.line;
    }
    if (hasInvoiceDiscount) {
      return DiscountScope.invoice;
    }
    return null;
  }

  InvoiceEditorState copyWith({InvoiceDetail? invoice, bool? isMutating}) {
    return InvoiceEditorState(invoice: invoice ?? this.invoice, isMutating: isMutating ?? this.isMutating);
  }
}

/// Mutations on a draft invoice with optimistic-concurrency handling (V1-6 US1/US3/US4).
final invoiceEditorProvider = AsyncNotifierProvider.autoDispose
    .family<InvoiceEditorNotifier, InvoiceEditorState, String>(InvoiceEditorNotifier.new);

/// Family arg is injected by [invoiceEditorProvider] via `NotifierT Function(String)`.
class InvoiceEditorNotifier extends AsyncNotifier<InvoiceEditorState> {
  InvoiceEditorNotifier(this._invoiceId);

  final String _invoiceId;

  @override
  Future<InvoiceEditorState> build() async {
    final invoice = await ref.read(invoiceRepositoryProvider).getDetail(invoiceId: _invoiceId);
    return InvoiceEditorState(invoice: invoice);
  }

  InvoiceRepository get _repo => ref.read(invoiceRepositoryProvider);

  InvoiceItemRepository get _itemRepo => ref.read(invoiceItemRepositoryProvider);

  Future<void> reload() async {
    state = await AsyncValue.guard(() async {
      final invoice = await _repo.getDetail(invoiceId: _invoiceId);
      return InvoiceEditorState(invoice: invoice);
    });
  }

  Future<T> _mutate<T>(Future<T> Function(InvoiceDetail current) action) async {
    final current = state.value;
    if (current == null) {
      throw StateError('Invoice not loaded.');
    }

    state = AsyncData(current.copyWith(isMutating: true));
    try {
      final result = await action(current.invoice);
      final refreshed = await _repo.getDetail(invoiceId: _invoiceId);
      state = AsyncData(InvoiceEditorState(invoice: refreshed));
      return result;
    } on RpcFailure catch (error) {
      state = AsyncData(current);
      if (error.code == 'STALE_INVOICE') {
        throw const InvoiceStaleException();
      }
      rethrow;
    } catch (error) {
      state = AsyncData(current);
      rethrow;
    }
  }

  Future<String> addItemFromService(EligibleService service) {
    return _mutate((invoice) async {
      final result = await _itemRepo.addFromService(
        invoiceId: invoice.id,
        expectedUpdatedAt: invoice.updatedAt,
        serviceId: service.serviceId,
      );
      return result.itemId;
    });
  }

  Future<void> updateItemQuantity({required String itemId, required String quantity}) {
    return _mutate((invoice) async {
      final item = invoice.items.firstWhere((entry) => entry.id == itemId);
      await _repo.updateItem(
        itemId: itemId,
        expectedUpdatedAt: invoice.updatedAt,
        description: item.description,
        quantity: quantity,
        unitPrice: item.unitPrice.wireValue,
      );
    });
  }

  Future<String> addItem({required String description, required String quantity, required String unitPrice}) {
    return _mutate((invoice) async {
      return _repo.addItem(
        invoiceId: invoice.id,
        expectedUpdatedAt: invoice.updatedAt,
        description: description,
        quantity: quantity,
        unitPrice: unitPrice,
      );
    });
  }

  Future<void> updateItem({
    required String itemId,
    required String description,
    required String quantity,
    required String unitPrice,
  }) {
    return _mutate((invoice) async {
      await _repo.updateItem(
        itemId: itemId,
        expectedUpdatedAt: invoice.updatedAt,
        description: description,
        quantity: quantity,
        unitPrice: unitPrice,
      );
    });
  }

  Future<void> removeItem(String itemId) {
    return _mutate((invoice) async {
      await _repo.removeItem(itemId: itemId, expectedUpdatedAt: invoice.updatedAt);
    });
  }

  Future<String> issue() {
    return _mutate((invoice) async {
      return _repo.issue(invoiceId: invoice.id, expectedUpdatedAt: invoice.updatedAt);
    });
  }

  Future<void> discardDraft() {
    return _mutate((invoice) async {
      await _repo.discardDraft(invoiceId: invoice.id, expectedUpdatedAt: invoice.updatedAt);
    });
  }

  Future<void> applyLineDiscount({required String itemId, DiscountKind? kind, String? value}) {
    return _mutate((invoice) async {
      await _repo.applyLineDiscount(itemId: itemId, expectedUpdatedAt: invoice.updatedAt, kind: kind, value: value);
    });
  }

  Future<void> applyInvoiceDiscount({DiscountKind? kind, String? value}) {
    return _mutate((invoice) async {
      await _repo.applyInvoiceDiscount(
        invoiceId: invoice.id,
        expectedUpdatedAt: invoice.updatedAt,
        kind: kind,
        value: value,
      );
    });
  }

  Future<void> setInsuranceCoverage({String? providerId, required String coveredAmount}) {
    return _mutate((invoice) async {
      await _repo.setInsuranceCoverage(
        invoiceId: invoice.id,
        expectedUpdatedAt: invoice.updatedAt,
        providerId: providerId,
        coveredAmount: coveredAmount,
      );
    });
  }
}
