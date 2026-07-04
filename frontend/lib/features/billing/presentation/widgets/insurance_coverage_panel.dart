import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/insurance_provider.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/providers/insurance_providers_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_editor_notifier.dart';

/// Insurance provider selector and covered amount for draft invoices (V1-6 US4).
class InsuranceCoveragePanel extends ConsumerStatefulWidget {
  const InsuranceCoveragePanel({
    required this.invoiceId,
    required this.invoice,
    required this.isMutating,
    super.key,
  });

  final String invoiceId;
  final InvoiceDetail invoice;
  final bool isMutating;

  @override
  ConsumerState<InsuranceCoveragePanel> createState() => _InsuranceCoveragePanelState();
}

class _InsuranceCoveragePanelState extends ConsumerState<InsuranceCoveragePanel> {
  String? _selectedProviderId;
  Decimal? _coveredAmount;

  InvoiceEditorNotifier get _notifier => ref.read(invoiceEditorProvider(widget.invoiceId).notifier);

  Money get _netTotal => widget.invoice.subtotal - widget.invoice.discountAmount;

  @override
  void initState() {
    super.initState();
    _syncFromInvoice();
  }

  @override
  void didUpdateWidget(covariant InsuranceCoveragePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invoice.updatedAt != widget.invoice.updatedAt) {
      _syncFromInvoice();
    }
  }

  void _syncFromInvoice() {
    _selectedProviderId = widget.invoice.insuranceProviderId;
    _coveredAmount = widget.invoice.insuranceCoveredAmount.isZero
        ? null
        : Decimal.parse(widget.invoice.insuranceCoveredAmount.wireValue);
  }

  Future<void> _save() async {
    final providerId = _selectedProviderId;
    if (providerId == null || providerId.isEmpty) {
      ref.showAppToast(message: 'Select an insurance provider.', variant: AppToastVariant.danger);
      return;
    }
    final amount = _coveredAmount;
    if (amount == null) {
      ref.showAppToast(message: 'Covered amount is required.', variant: AppToastVariant.danger);
      return;
    }
    if (amount < Decimal.zero) {
      ref.showAppToast(message: 'Enter a valid non-negative amount.', variant: AppToastVariant.danger);
      return;
    }
    if (amount > Decimal.parse(_netTotal.wireValue)) {
      ref.showAppToast(
        message: 'Covered amount cannot exceed the invoice total after discounts.',
        variant: AppToastVariant.danger,
      );
      return;
    }

    try {
      await _notifier.setInsuranceCoverage(providerId: providerId, coveredAmount: amount.toStringAsFixed(2));
    } on RpcFailure catch (error) {
      ref.showAppToast(message: billingMessageForRpc(error), variant: AppToastVariant.danger);
    }
  }

  Future<void> _clear() async {
    try {
      await _notifier.setInsuranceCoverage(providerId: null, coveredAmount: '0');
    } on RpcFailure catch (error) {
      ref.showAppToast(message: billingMessageForRpc(error), variant: AppToastVariant.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(activeInsuranceProvidersProvider);
    final hasCoverage = widget.invoice.insuranceProviderId != null || !widget.invoice.insuranceCoveredAmount.isZero;
    final patientDue = _netTotal - widget.invoice.insuranceCoveredAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Insurance coverage', style: context.typography.title),
        const SizedBox(height: AppSpacing.s3),
        providersAsync.when(
          loading: () => const Center(child: AppSpinner()),
          error: (error, _) => AppErrorState(message: error.toString()),
          data: (providers) => _buildForm(context, providers),
        ),
        if (hasCoverage) ...[
          const SizedBox(height: AppSpacing.s3),
          AppAlert(
            variant: AppAlertVariant.info,
            title:
                'Insurance covered: ${widget.invoice.insuranceCoveredAmount.wireValue} ${widget.invoice.currency}'
                '${widget.invoice.insuranceProviderName != null ? ' (${widget.invoice.insuranceProviderName})' : ''}',
            body: 'Patient due: ${patientDue.wireValue} ${widget.invoice.currency}',
          ),
        ],
      ],
    );
  }

  Widget _buildForm(BuildContext context, List<InsuranceProvider> providers) {
    if (providers.isEmpty) {
      return AppEmptyState(
        variant: AppEmptyStateVariant.noResults,
        title: 'No insurance providers configured',
        description:
            'You can issue this invoice without insurance or add providers in settings.',
        actionLabel: 'Manage insurance providers',
        onAction: widget.isMutating ? null : () => context.push(AppRoutes.billingInsuranceProviders),
      );
    }

    final options = providers
        .map((provider) => AppSelectOption(value: provider.id, label: provider.name))
        .toList(growable: false);

    return AppCard(
      variant: AppCardVariant.flat,
      padding: AppCardPadding.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFormField(
            label: 'Insurance provider',
            child: AppSelect<String>(
              value: options.any((option) => option.value == _selectedProviderId) ? _selectedProviderId : null,
              options: options,
              disabled: widget.isMutating,
              onChanged: widget.isMutating
                  ? null
                  : (value) => setState(() => _selectedProviderId = value),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
            label: 'Covered amount (max ${_netTotal.wireValue})',
            child: AppMoneyField(
              currency: widget.invoice.currency,
              value: _coveredAmount,
              disabled: widget.isMutating,
              onValueChange: widget.isMutating ? null : (value) => setState(() => _coveredAmount = value),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          Row(
            children: [
              AppButton(
                label: 'Save insurance coverage',
                size: AppButtonSize.sm,
                loading: widget.isMutating,
                onPressed: widget.isMutating ? null : _save,
              ),
              if (hasCoverage) ...[
                const SizedBox(width: AppSpacing.s2),
                AppButton(
                  label: 'Clear',
                  size: AppButtonSize.sm,
                  variant: AppButtonVariant.ghost,
                  disabled: widget.isMutating,
                  onPressed: widget.isMutating ? null : _clear,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  bool get hasCoverage =>
      widget.invoice.insuranceProviderId != null || !widget.invoice.insuranceCoveredAmount.isZero;
}
