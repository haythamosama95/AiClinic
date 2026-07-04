import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/insurance_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/insurance_providers_notifier.dart';

/// Insurance provider selector and covered amount for draft invoices (V1-6 US4).
class InsurancePanel extends ConsumerStatefulWidget {
  const InsurancePanel({required this.invoice, required this.enabled, required this.onSave, super.key});

  final InvoiceDetail invoice;
  final bool enabled;
  final Future<void> Function(String? providerId, String coveredAmount) onSave;

  @override
  ConsumerState<InsurancePanel> createState() => _InsurancePanelState();
}

class _InsurancePanelState extends ConsumerState<InsurancePanel> {
  String? _selectedProviderId;
  final _amountController = TextEditingController();
  var _isSaving = false;

  @override
  void initState() {
    super.initState();
    _syncFromInvoice();
  }

  @override
  void didUpdateWidget(InsurancePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invoice.insuranceProviderId != widget.invoice.insuranceProviderId ||
        oldWidget.invoice.insuranceCoveredAmount != widget.invoice.insuranceCoveredAmount) {
      _syncFromInvoice();
    }
  }

  void _syncFromInvoice() {
    _selectedProviderId = widget.invoice.insuranceProviderId;
    _amountController.text = widget.invoice.insuranceCoveredAmount.isZero
        ? ''
        : widget.invoice.insuranceCoveredAmount.wireValue;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await widget.onSave(
        _selectedProviderId,
        _amountController.text.trim().isEmpty ? '0' : _amountController.text.trim(),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(activeInsuranceProvidersProvider);
    final colors = context.semanticColors;

    return AppCard(
      title: const Text('Insurance coverage'),
      description: const Text('Estimated amount covered by insurance (informational at issue).'),
      child: providersAsync.when(
        loading: () => const Center(child: AppCircularProgress()),
        error: (error, _) => Text('Unable to load insurance providers: $error'),
        data: (providers) {
          if (providers.isEmpty) {
            return Text(
              'No insurance providers configured. Add providers under Billing → Insurance providers.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
            );
          }

          return Opacity(
            opacity: widget.enabled ? 1 : 0.6,
            child: IgnorePointer(
              ignoring: !widget.enabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppLabel(
                    label: 'Provider',
                    child: _ProviderDropdown(
                      providers: providers,
                      selectedId: _selectedProviderId,
                      onChanged: (id) => setState(() => _selectedProviderId = id),
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  AppTextField(controller: _amountController, label: 'Covered amount', hintText: '0.00'),
                  const SizedBox(height: SpacingTokens.md),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(label: 'Save coverage', expand: false, isLoading: _isSaving, onPressed: _save),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProviderDropdown extends StatelessWidget {
  const _ProviderDropdown({required this.providers, required this.selectedId, required this.onChanged});

  final List<InsuranceProvider> providers;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      value: selectedId,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      hint: const Text('Select provider'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('None')),
        for (final provider in providers) DropdownMenuItem(value: provider.id, child: Text(provider.name)),
      ],
      onChanged: onChanged,
    );
  }
}
