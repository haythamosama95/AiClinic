import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/service_catalog/application/service_catalog_rpc_messages.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';

/// Copy mode for branch configuration transfer.
enum CopyConfigurationMode {
  merge('merge', 'Merge', 'Add missing services only; leave existing target rows untouched.'),
  replace('replace', 'Replace', 'Overwrite target rows to match the source branch.');

  const CopyConfigurationMode(this.wireValue, this.label, this.description);

  final String wireValue;
  final String label;
  final String description;
}

/// Dialog to copy service branch configuration between branches (015 US7).
class CopyConfigurationDialog extends ConsumerStatefulWidget {
  const CopyConfigurationDialog({super.key, required this.branches});

  final List<BranchListItem> branches;

  static Future<bool?> show(BuildContext context, {required List<BranchListItem> branches}) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => CopyConfigurationDialog(branches: branches),
    );
  }

  @override
  ConsumerState<CopyConfigurationDialog> createState() => _CopyConfigurationDialogState();
}

class _CopyConfigurationDialogState extends ConsumerState<CopyConfigurationDialog> {
  String? _sourceBranchId;
  String? _targetBranchId;
  CopyConfigurationMode _mode = CopyConfigurationMode.merge;
  var _isSaving = false;
  String? _errorMessage;

  List<BranchListItem> get _activeBranches =>
      widget.branches.where((branch) => branch.isActive).toList(growable: false);

  bool get _canSubmit =>
      _sourceBranchId != null && _targetBranchId != null && _sourceBranchId != _targetBranchId && !_isSaving;

  Future<void> _submit() async {
    if (!_canSubmit) {
      return;
    }

    if (_mode == CopyConfigurationMode.replace) {
      final confirmed = await _confirmReplace();
      if (!confirmed || !mounted) {
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(serviceCatalogRepositoryProvider)
          .copyConfiguration(sourceBranchId: _sourceBranchId!, targetBranchId: _targetBranchId!, mode: _mode.wireValue);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = serviceCatalogMessageForRpc(error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to copy branch configuration. Check connectivity and try again.';
      });
    }
  }

  Future<bool> _confirmReplace() async {
    var confirmed = false;
    await AppDialog.showConfirmation(
      context: context,
      title: 'Replace target configuration?',
      message:
          'This overwrites existing service settings on the target branch to match the source. This cannot be undone automatically.',
      confirmLabel: 'Replace',
      destructive: true,
      onConfirm: () => confirmed = true,
    );
    return confirmed;
  }

  @override
  Widget build(BuildContext context) {
    final branchOptions = [
      for (final branch in _activeBranches) AppSelectOption<String?>(value: branch.id, label: branch.name),
    ];

    return AlertDialog(
      title: const Text('Copy branch configuration'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Copy assigned services with activation, price overrides, and promotions from one branch to another.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: SpacingTokens.md),
                AppAlert(variant: AppAlertVariant.destructive, title: _errorMessage!),
              ],
              const SizedBox(height: SpacingTokens.md),
              AppSelectTileGroup<String?>(
                label: 'Source branch',
                mode: AppSelectGroupMode.radio,
                options: branchOptions,
                values: {_sourceBranchId},
                onChanged: (values) => setState(() => _sourceBranchId = values.isEmpty ? null : values.first),
              ),
              const SizedBox(height: SpacingTokens.md),
              AppSelectTileGroup<String?>(
                label: 'Target branch',
                mode: AppSelectGroupMode.radio,
                options: branchOptions,
                values: {_targetBranchId},
                onChanged: (values) => setState(() => _targetBranchId = values.isEmpty ? null : values.first),
              ),
              const SizedBox(height: SpacingTokens.md),
              AppSelectTileGroup<CopyConfigurationMode>(
                label: 'Copy mode',
                mode: AppSelectGroupMode.radio,
                options: [
                  for (final mode in CopyConfigurationMode.values)
                    AppSelectOption(value: mode, label: mode.label, description: mode.description),
                ],
                values: {_mode},
                onChanged: (values) {
                  if (values.isEmpty) {
                    return;
                  }
                  setState(() => _mode = values.first);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.outline,
          expand: false,
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Copy configuration',
          expand: false,
          isLoading: _isSaving,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
    );
  }
}
