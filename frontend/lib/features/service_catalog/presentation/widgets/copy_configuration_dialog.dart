import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/service_catalog/application/service_catalog_rpc_messages.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';

/// Copy modes supported by `copy_service_branch_configuration` (015 US7).
enum CopyConfigurationMode {
  merge('merge'),
  replace('replace');

  const CopyConfigurationMode(this.wireValue);

  final String wireValue;
}

/// Opens the cross-branch configuration copy dialog (E4 replace confirmation).
Future<bool> showCopyConfigurationDialog(
  BuildContext context,
  WidgetRef ref, {
  String? serviceId,
}) async {
  final result = await showAppDialog<bool>(
    context,
    size: AppDialogSize.md,
    semanticLabel: 'Copy branch configuration',
    builder: (dialogContext, close) {
      return _CopyConfigurationDialog(
        serviceId: serviceId,
        onClose: () => close(false),
        onCopied: () => close(true),
      );
    },
  );
  return result ?? false;
}

class _CopyConfigurationDialog extends ConsumerStatefulWidget {
  const _CopyConfigurationDialog({
    required this.onClose,
    required this.onCopied,
    this.serviceId,
  });

  final String? serviceId;
  final VoidCallback onClose;
  final VoidCallback onCopied;

  @override
  ConsumerState<_CopyConfigurationDialog> createState() => _CopyConfigurationDialogState();
}

class _CopyConfigurationDialogState extends ConsumerState<_CopyConfigurationDialog> {
  String? _sourceBranchId;
  String? _targetBranchId;
  CopyConfigurationMode _mode = CopyConfigurationMode.merge;
  var _isCopying = false;
  String? _summaryError;

  Future<void> _submit() async {
    final sourceId = _sourceBranchId;
    final targetId = _targetBranchId;
    if (sourceId == null || sourceId.isEmpty || targetId == null || targetId.isEmpty) {
      setState(() => _summaryError = 'Select both a source and a target branch.');
      return;
    }
    if (sourceId == targetId) {
      setState(() => _summaryError = 'Source and target branches must differ.');
      return;
    }

    if (_mode == CopyConfigurationMode.replace) {
      final confirmed = await showAppConfirmationDialog(
        context,
        title: 'Replace target configuration?',
        message:
            'This will overwrite existing service configuration at the target branch. '
            'Assignments, activation, price overrides, and promotions will be replaced.',
        confirmLabel: 'Replace configuration',
        destructive: true,
      );
      if (!confirmed || !mounted) {
        return;
      }
    }

    setState(() {
      _isCopying = true;
      _summaryError = null;
    });

    try {
      await ref.read(serviceCatalogRepositoryProvider).copyConfiguration(
            sourceBranchId: sourceId,
            targetBranchId: targetId,
            mode: _mode.wireValue,
            serviceIds: widget.serviceId == null ? const [] : [widget.serviceId!],
          );
      if (!mounted) {
        return;
      }
      widget.onCopied();
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCopying = false;
        _summaryError = serviceCatalogMessageForRpc(error);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCopying = false;
        _summaryError = error.toString();
      });
    }
  }

  List<AppSelectOption<String>> _branchOptions(List<BranchListItem> branches) {
    return [
      for (final branch in branches)
        if (branch.isActive) AppSelectOption(value: branch.id, label: branch.name),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(clinicSetupBranchesProvider);
    final branches = branchesAsync.maybeWhen(data: (value) => value, orElse: () => const <BranchListItem>[]);

    return AppDialog(
      title: 'Copy branch configuration',
      size: AppDialogSize.md,
      onClose: _isCopying ? null : widget.onClose,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.serviceId == null
                ? 'Copy service assignments and branch settings from one branch to another.'
                : 'Copy this service\'s branch settings from one branch to another.',
            style: context.typography.body.copyWith(color: context.colors.textSecondary),
          ),
          if (_summaryError != null) ...[
            const SizedBox(height: AppSpacing.s4),
            AppAlert(
              variant: AppAlertVariant.danger,
              title: _summaryError!,
            ),
          ],
          const SizedBox(height: AppSpacing.s4),
          AppFormField(
            label: 'Source branch',
            requiredMark: true,
            child: AppSelect<String>(
              options: _branchOptions(branches),
              value: _sourceBranchId,
              disabled: _isCopying || branchesAsync.isLoading,
              placeholder: 'Select source branch',
              onChanged: (value) => setState(() => _sourceBranchId = value),
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          AppFormField(
            label: 'Target branch',
            requiredMark: true,
            child: AppSelect<String>(
              options: _branchOptions(branches),
              value: _targetBranchId,
              disabled: _isCopying || branchesAsync.isLoading,
              placeholder: 'Select target branch',
              onChanged: (value) => setState(() => _targetBranchId = value),
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          AppFormField(
            label: 'Copy mode',
            helperText: 'Merge only creates missing entries. Replace overwrites the target branch.',
            child: AppRadioGroup<CopyConfigurationMode>(
              value: _mode,
              disabled: _isCopying,
              options: const [
                AppRadioOption(
                  value: CopyConfigurationMode.merge,
                  label: 'Merge missing only',
                ),
                AppRadioOption(
                  value: CopyConfigurationMode.replace,
                  label: 'Replace existing',
                ),
              ],
              onChanged: (value) => setState(() => _mode = value),
            ),
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            disabled: _isCopying,
            onPressed: widget.onClose,
          ),
          const SizedBox(width: AppSpacing.s3),
          AppButton(
            label: 'Copy configuration',
            loading: _isCopying,
            onPressed: _isCopying ? null : _submit,
          ),
        ],
      ),
    );
  }
}
