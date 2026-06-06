import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/billing/domain/insurance_provider.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/presentation/providers/insurance_providers_notifier.dart';

typedef InsuranceCoverageSubmit = Future<bool> Function({required String providerId, required String coveredAmount});

typedef InsuranceCoverageClear = Future<bool> Function();

/// Insurance provider selector and covered amount input for draft invoices (V1-6 US4).
class InsurancePanel extends ConsumerStatefulWidget {
  const InsurancePanel({
    super.key,
    required this.detail,
    required this.enabled,
    required this.busy,
    required this.onApply,
    required this.onClear,
  });

  final InvoiceDetail detail;
  final bool enabled;
  final bool busy;
  final InsuranceCoverageSubmit onApply;
  final InsuranceCoverageClear onClear;

  @override
  ConsumerState<InsurancePanel> createState() => _InsurancePanelState();
}

class _InsurancePanelState extends ConsumerState<InsurancePanel> {
  String? _selectedProviderId;
  final _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _syncFromDetail();
  }

  @override
  void didUpdateWidget(covariant InsurancePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.updatedAt != widget.detail.updatedAt ||
        oldWidget.detail.insuranceProviderId != widget.detail.insuranceProviderId ||
        oldWidget.detail.insuranceCoveredAmount != widget.detail.insuranceCoveredAmount) {
      _syncFromDetail();
    }
  }

  void _syncFromDetail() {
    _selectedProviderId = widget.detail.insuranceProviderId;
    _amountController.text = widget.detail.insuranceCoveredAmount == '0' ? '' : widget.detail.insuranceCoveredAmount;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _netTotal {
    final subtotal = double.tryParse(widget.detail.subtotal) ?? 0;
    final discount = double.tryParse(widget.detail.discountAmount) ?? 0;
    return subtotal - discount;
  }

  String? _validateAmount(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Covered amount is required.';
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null || parsed < 0) {
      return 'Enter a valid non-negative amount.';
    }
    if (parsed > _netTotal) {
      return 'Covered amount cannot exceed the invoice total after discounts.';
    }
    return null;
  }

  Future<void> _submit() async {
    final providerId = _selectedProviderId;
    if (providerId == null || providerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select an insurance provider.')));
      return;
    }

    final error = _validateAmount(_amountController.text);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    await widget.onApply(providerId: providerId, coveredAmount: _amountController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(activeInsuranceProvidersProvider);
    final hasCoverage =
        widget.detail.insuranceProviderId != null || (double.tryParse(widget.detail.insuranceCoveredAmount) ?? 0) > 0;
    final patientDue = (_netTotal - (double.tryParse(widget.detail.insuranceCoveredAmount) ?? 0)).toStringAsFixed(2);

    return Column(
      key: const Key('insurance_panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Insurance coverage', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        providersAsync.when(
          loading: () => const LinearProgressIndicator(key: Key('insurance_panel_loading')),
          error: (error, _) => Text('Failed to load insurance providers: $error'),
          data: (providers) => _buildForm(context, providers),
        ),
        if (hasCoverage) ...[
          const SizedBox(height: 8),
          Text(
            'Insurance covered: ${widget.detail.insuranceCoveredAmount} ${widget.detail.currency}'
            '${widget.detail.insuranceProviderName != null ? ' (${widget.detail.insuranceProviderName})' : ''}',
          ),
          Text('Patient due: $patientDue ${widget.detail.currency}'),
        ],
      ],
    );
  }

  Widget _buildForm(BuildContext context, List<InsuranceProvider> providers) {
    if (providers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            key: Key('insurance_panel_empty_state'),
            'No active insurance providers are configured. You can issue this invoice without insurance or add providers in settings.',
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('insurance_panel_manage_link'),
            onPressed: widget.enabled ? () => context.go(AppRoutes.billingInsuranceProviders) : null,
            child: const Text('Manage insurance providers'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: const Key('insurance_provider_selector'),
          value: providers.any((provider) => provider.id == _selectedProviderId) ? _selectedProviderId : null,
          decoration: const InputDecoration(labelText: 'Insurance provider', border: OutlineInputBorder()),
          items: providers
              .map((provider) => DropdownMenuItem(value: provider.id, child: Text(provider.name)))
              .toList(growable: false),
          onChanged: widget.enabled && !widget.busy ? (value) => setState(() => _selectedProviderId = value) : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('insurance_covered_amount'),
          controller: _amountController,
          decoration: InputDecoration(
            labelText: 'Covered amount (max ${_netTotal.toStringAsFixed(2)})',
            border: const OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          enabled: widget.enabled && !widget.busy,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton(
              key: const Key('insurance_apply_button'),
              onPressed: widget.enabled && !widget.busy ? _submit : null,
              child: const Text('Save insurance coverage'),
            ),
            if (widget.detail.insuranceProviderId != null ||
                (double.tryParse(widget.detail.insuranceCoveredAmount) ?? 0) > 0) ...[
              const SizedBox(width: 8),
              TextButton(
                key: const Key('insurance_clear_button'),
                onPressed: widget.enabled && !widget.busy ? widget.onClear : null,
                child: const Text('Clear'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
