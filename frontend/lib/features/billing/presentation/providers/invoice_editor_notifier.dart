import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/billing_rpc_messages.dart';

enum InvoiceEditorStatus { idle, loading, saving, stale, error }

@immutable
class InvoiceEditorState {
  const InvoiceEditorState({
    required this.detail,
    this.editorStatus = InvoiceEditorStatus.idle,
    this.errorMessage,
    this.issueErrorMessage,
  });

  final InvoiceDetail detail;
  final InvoiceEditorStatus editorStatus;
  final String? errorMessage;
  final String? issueErrorMessage;

  bool get isDraft => detail.status == InvoiceStatus.draft;

  bool get isBusy => editorStatus == InvoiceEditorStatus.loading || editorStatus == InvoiceEditorStatus.saving;

  InvoiceEditorState copyWith({
    InvoiceDetail? detail,
    InvoiceEditorStatus? editorStatus,
    String? errorMessage,
    String? issueErrorMessage,
    bool clearError = false,
    bool clearIssueError = false,
  }) {
    return InvoiceEditorState(
      detail: detail ?? this.detail,
      editorStatus: editorStatus ?? this.editorStatus,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      issueErrorMessage: clearIssueError ? null : (issueErrorMessage ?? this.issueErrorMessage),
    );
  }
}

final invoiceEditorProvider = AsyncNotifierProvider.autoDispose
    .family<InvoiceEditorNotifier, InvoiceEditorState, String>(InvoiceEditorNotifier.new);

class InvoiceEditorNotifier extends AsyncNotifier<InvoiceEditorState> {
  InvoiceEditorNotifier(this._invoiceId);

  final String _invoiceId;

  @override
  Future<InvoiceEditorState> build() async {
    return _load();
  }

  Future<InvoiceEditorState> _load() async {
    final invoiceId = _invoiceId.trim();
    if (invoiceId.isEmpty) {
      throw StateError('Invoice id is required.');
    }

    final canCreate = ref.read(permissionServiceProvider).canCreateInvoices();
    if (!canCreate) {
      throw StateError('You do not have permission to edit invoices.');
    }

    final detail = await ref.read(invoiceRepositoryProvider).getDetail(invoiceId: invoiceId);
    if (!detail.status.isDraft) {
      throw StateError('Only draft invoices can be edited.');
    }

    return InvoiceEditorState(detail: detail);
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = AsyncData(await _load());
  }

  Future<bool> addItem({required String description, required String quantity, required String unitPrice}) async {
    return _mutate((detail, repo) async {
      await repo.addItem(
        invoiceId: detail.id,
        expectedUpdatedAt: detail.updatedAt,
        description: description,
        quantity: quantity,
        unitPrice: unitPrice,
      );
    });
  }

  Future<bool> updateItem({
    required String itemId,
    required String description,
    required String quantity,
    required String unitPrice,
  }) async {
    return _mutate((detail, repo) async {
      await repo.updateItem(
        itemId: itemId,
        expectedUpdatedAt: detail.updatedAt,
        description: description,
        quantity: quantity,
        unitPrice: unitPrice,
      );
    });
  }

  Future<bool> removeItem({required String itemId}) async {
    return _mutate((detail, repo) async {
      await repo.removeItem(itemId: itemId, expectedUpdatedAt: detail.updatedAt);
    });
  }

  Future<bool> applyLineDiscount({required String itemId, required DiscountKind kind, required String value}) async {
    return _mutate((detail, repo) async {
      await repo.applyLineDiscount(itemId: itemId, expectedUpdatedAt: detail.updatedAt, kind: kind, value: value);
    });
  }

  Future<bool> clearLineDiscount({required String itemId}) async {
    return _mutate((detail, repo) async {
      await repo.applyLineDiscount(itemId: itemId, expectedUpdatedAt: detail.updatedAt);
    });
  }

  Future<bool> applyInvoiceDiscount({required DiscountKind kind, required String value}) async {
    return _mutate((detail, repo) async {
      await repo.applyInvoiceDiscount(
        invoiceId: detail.id,
        expectedUpdatedAt: detail.updatedAt,
        kind: kind,
        value: value,
      );
    });
  }

  Future<bool> clearInvoiceDiscount() async {
    return _mutate((detail, repo) async {
      await repo.applyInvoiceDiscount(invoiceId: detail.id, expectedUpdatedAt: detail.updatedAt);
    });
  }

  Future<bool> setInsuranceCoverage({required String providerId, required String coveredAmount}) async {
    return _mutate((detail, repo) async {
      await repo.setInsuranceCoverage(
        invoiceId: detail.id,
        expectedUpdatedAt: detail.updatedAt,
        providerId: providerId,
        coveredAmount: coveredAmount,
      );
    });
  }

  Future<bool> clearInsuranceCoverage() async {
    return _mutate((detail, repo) async {
      await repo.setInsuranceCoverage(
        invoiceId: detail.id,
        expectedUpdatedAt: detail.updatedAt,
        providerId: null,
        coveredAmount: '0',
      );
    });
  }

  Future<bool> clearAllLineDiscounts() async {
    final current = state.value;
    if (current == null) {
      return false;
    }

    final discountedItems = current.detail.items.where(
      (item) => item.lineDiscountKind != null || (double.tryParse(item.lineDiscountAmount) ?? 0) > 0,
    );
    if (discountedItems.isEmpty) {
      return true;
    }

    for (final item in discountedItems) {
      final cleared = await clearLineDiscount(itemId: item.id);
      if (!cleared) {
        return false;
      }
    }
    return true;
  }

  void setIssueValidationError(String message) {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(current.copyWith(editorStatus: InvoiceEditorStatus.error, issueErrorMessage: message));
  }

  Future<String?> issue() async {
    final current = state.value;
    if (current == null) {
      return null;
    }

    state = AsyncData(current.copyWith(editorStatus: InvoiceEditorStatus.saving, clearIssueError: true));

    try {
      final invoiceNumber = await ref
          .read(invoiceRepositoryProvider)
          .issue(invoiceId: current.detail.id, expectedUpdatedAt: current.detail.updatedAt);
      return invoiceNumber;
    } on RpcFailure catch (error) {
      final message = billingMessageForRpc(error);
      final isStale = error.code == 'STALE_INVOICE';
      state = AsyncData(
        current.copyWith(
          editorStatus: isStale ? InvoiceEditorStatus.stale : InvoiceEditorStatus.error,
          issueErrorMessage: message,
          errorMessage: isStale ? message : current.errorMessage,
        ),
      );
      if (isStale) {
        await reload();
      }
      return null;
    } catch (error) {
      state = AsyncData(current.copyWith(editorStatus: InvoiceEditorStatus.error, issueErrorMessage: error.toString()));
      return null;
    }
  }

  Future<bool> _mutate(Future<void> Function(InvoiceDetail detail, InvoiceRepository repo) action) async {
    final current = state.value;
    if (current == null) {
      return false;
    }

    state = AsyncData(current.copyWith(editorStatus: InvoiceEditorStatus.saving, clearError: true));

    try {
      final repo = ref.read(invoiceRepositoryProvider);
      await action(current.detail, repo);
      final detail = await repo.getDetail(invoiceId: current.detail.id);
      state = AsyncData(InvoiceEditorState(detail: detail, editorStatus: InvoiceEditorStatus.idle));
      return true;
    } on RpcFailure catch (error) {
      final message = billingMessageForRpc(error);
      final isStale = error.code == 'STALE_INVOICE';
      state = AsyncData(
        current.copyWith(
          editorStatus: isStale ? InvoiceEditorStatus.stale : InvoiceEditorStatus.error,
          errorMessage: message,
        ),
      );
      if (isStale) {
        await reload();
      }
      return false;
    } catch (error) {
      state = AsyncData(current.copyWith(editorStatus: InvoiceEditorStatus.error, errorMessage: error.toString()));
      return false;
    }
  }
}
