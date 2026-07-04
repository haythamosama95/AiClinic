import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/service_catalog/application/service_catalog_rpc_messages.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_catalog_list_notifier.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';

/// Setup method for populating a new branch's service catalog (FR-031).
enum NewBranchServiceSetupMethod {
  select('select', 'Select services', 'Assign specific catalog services with default pricing.'),
  copyAll('copy_all', 'Copy entire branch', 'Copy all configured services from another branch.'),
  copyModify('copy_modify', 'Copy then modify', 'Copy from a source branch, then open the catalog to adjust settings.');

  const NewBranchServiceSetupMethod(this.wireValue, this.label, this.description);

  final String wireValue;
  final String label;
  final String description;
}

/// Post-creation step to assign services to a new branch (015 US7 / FR-031).
class NewBranchServiceSetup extends ConsumerStatefulWidget {
  const NewBranchServiceSetup({
    super.key,
    required this.targetBranchId,
    required this.targetBranchName,
    required this.branches,
  });

  final String targetBranchId;
  final String targetBranchName;
  final List<BranchListItem> branches;

  static Future<bool?> show(
    BuildContext context, {
    required String targetBranchId,
    required String targetBranchName,
    required List<BranchListItem> branches,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          NewBranchServiceSetup(targetBranchId: targetBranchId, targetBranchName: targetBranchName, branches: branches),
    );
  }

  @override
  ConsumerState<NewBranchServiceSetup> createState() => _NewBranchServiceSetupState();
}

class _NewBranchServiceSetupState extends ConsumerState<NewBranchServiceSetup> {
  NewBranchServiceSetupMethod _method = NewBranchServiceSetupMethod.select;
  String? _sourceBranchId;
  final Set<String> _selectedServiceIds = {};
  var _isSaving = false;
  String? _errorMessage;

  List<BranchListItem> get _sourceBranchOptions =>
      widget.branches.where((branch) => branch.isActive && branch.id != widget.targetBranchId).toList(growable: false);

  bool get _canSubmit {
    if (_isSaving) {
      return false;
    }
    return switch (_method) {
      NewBranchServiceSetupMethod.select => _selectedServiceIds.isNotEmpty,
      NewBranchServiceSetupMethod.copyAll || NewBranchServiceSetupMethod.copyModify => _sourceBranchId != null,
    };
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final result = await ref
          .read(serviceCatalogRepositoryProvider)
          .setupNewBranchServices(
            targetBranchId: widget.targetBranchId,
            method: _method.wireValue,
            serviceIds: _selectedServiceIds.toList(growable: false),
            sourceBranchId: _sourceBranchId,
          );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);

      if (_method == NewBranchServiceSetupMethod.copyModify && result.assignedServiceIds.isNotEmpty) {
        AppToast.success(context, message: 'Services copied. Open the service catalog to adjust branch settings.');
        context.push(AppRoutes.settingsServices);
      } else {
        AppToast.success(context, message: 'Branch services configured.');
      }
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
        _errorMessage = 'Unable to configure branch services. Check connectivity and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(serviceCatalogListProvider);
    final sourceOptions = [
      for (final branch in _sourceBranchOptions) AppSelectOption<String?>(value: branch.id, label: branch.name),
    ];

    return AlertDialog(
      title: Text('Set up services for ${widget.targetBranchName}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'New branches start with no assigned services. Choose how to populate this branch catalog.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: SpacingTokens.md),
                AppAlert(variant: AppAlertVariant.destructive, title: _errorMessage!),
              ],
              const SizedBox(height: SpacingTokens.md),
              AppSelectTileGroup<NewBranchServiceSetupMethod>(
                label: 'Setup method',
                mode: AppSelectGroupMode.radio,
                options: [
                  for (final method in NewBranchServiceSetupMethod.values)
                    AppSelectOption(value: method, label: method.label, description: method.description),
                ],
                values: {_method},
                onChanged: (values) {
                  if (values.isEmpty) {
                    return;
                  }
                  setState(() => _method = values.first);
                },
              ),
              const SizedBox(height: SpacingTokens.md),
              if (_method == NewBranchServiceSetupMethod.select) ...[
                catalogAsync.when(
                  loading: () => const Center(child: AppCircularProgress()),
                  error: (error, _) => Text('Unable to load services: $error'),
                  data: (state) {
                    if (state.items.isEmpty) {
                      return const Text(
                        'No catalog services are available yet. Create services first or skip for now.',
                      );
                    }
                    return _ServiceSelectionList(
                      items: state.items,
                      selectedServiceIds: _selectedServiceIds,
                      onToggle: (serviceId, selected) {
                        setState(() {
                          if (selected) {
                            _selectedServiceIds.add(serviceId);
                          } else {
                            _selectedServiceIds.remove(serviceId);
                          }
                        });
                      },
                    );
                  },
                ),
              ] else ...[
                AppSelectTileGroup<String?>(
                  label: 'Copy from branch',
                  mode: AppSelectGroupMode.radio,
                  options: sourceOptions,
                  values: {_sourceBranchId},
                  onChanged: (values) => setState(() => _sourceBranchId = values.isEmpty ? null : values.first),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: 'Skip for now',
          variant: AppButtonVariant.ghost,
          expand: false,
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(label: 'Apply setup', expand: false, isLoading: _isSaving, onPressed: _canSubmit ? _submit : null),
      ],
    );
  }
}

class _ServiceSelectionList extends StatelessWidget {
  const _ServiceSelectionList({required this.items, required this.selectedServiceIds, required this.onToggle});

  final List<ServiceListItem> items;
  final Set<String> selectedServiceIds;
  final void Function(String serviceId, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Select services', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: SpacingTokens.sm),
        for (final item in items)
          CheckboxListTile(
            value: selectedServiceIds.contains(item.serviceId),
            onChanged: (selected) => onToggle(item.serviceId, selected ?? false),
            title: Text(item.name),
            subtitle: Text('Default ${item.defaultPrice.wireValue}'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
      ],
    );
  }
}
