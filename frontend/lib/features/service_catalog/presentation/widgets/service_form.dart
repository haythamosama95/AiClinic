import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/application/service_catalog_rpc_messages.dart';
import 'package:ai_clinic/features/service_catalog/application/service_form_validation.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/pending_branch_configuration.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_branch_config.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_detail.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_form_draft_snapshot.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_editor_notifier.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/branch_configuration_matrix.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';

/// Shared create/edit service form composed inside [EditorFormPattern].
class ServiceForm extends ConsumerStatefulWidget {
  const ServiceForm({this.serviceId, super.key});

  /// `null` means create mode (`/settings/services/new`).
  final String? serviceId;

  @override
  ConsumerState<ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends ConsumerState<ServiceForm> {
  final _nameController = TextEditingController();

  Decimal? _defaultPrice;
  GlobalStatus _globalStatus = GlobalStatus.active;
  var _assignAllBranches = true;
  final Set<String> _selectedBranchIds = {};
  final Map<String, PendingBranchConfiguration> _pendingByBranchId = {};

  var _submitted = false;
  String? _summaryError;
  String? _staleEditError;
  String? _nameError;
  String? _defaultPriceError;
  String? _branchSelectionError;
  String? _hydratedForServiceId;

  bool get _isCreateMode => widget.serviceId == null;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _maybeHydrate(ServiceDetail detail, Map<String, String> branchNames) {
    final key = detail.service.id;
    if (_hydratedForServiceId == key) {
      return;
    }
    _hydratedForServiceId = key;
    _hydrateFromDetail(detail, branchNames);
  }

  void _hydrateFromDetail(ServiceDetail detail, Map<String, String> branchNames) {
    _nameController.text = detail.service.name;
    _defaultPrice = Decimal.parse(detail.service.defaultPrice.wireValue);
    _globalStatus = detail.service.globalStatus;
    final assignedIds = detail.branches.map((row) => row.branchId).toSet();
    final allBranchIds = branchNames.keys.toSet();
    _assignAllBranches = assignedIds.length == allBranchIds.length && allBranchIds.isNotEmpty;
    _selectedBranchIds
      ..clear()
      ..addAll(assignedIds);
  }

  List<ServiceBranchConfig> _branchRows(List<BranchListItem> branches, ServiceDetail? detail) {
    final names = {for (final branch in branches) branch.id: branch.name};
    if (!_isCreateMode && detail != null) {
      return detail.branches
          .map((row) => ServiceBranchConfig.fromRow(row, branchName: names[row.branchId]))
          .toList(growable: false);
    }

    return [
      for (final branch in branches.where((item) => item.isActive))
        ServiceBranchConfig.fromPending(
          _pendingByBranchId[branch.id] ??
              PendingBranchConfiguration(branchId: branch.id, branchName: branch.name),
        ),
    ];
  }

  ServiceFormDraftSnapshot get _draftSnapshot => ServiceFormDraftSnapshot(
        defaultPrice: _defaultPriceWire,
        assignAllBranches: _assignAllBranches,
        selectedBranchIds: Set<String>.from(_selectedBranchIds),
      );

  String get _defaultPriceWire {
    if (_defaultPrice == null) {
      return '';
    }
    return Money.parse(_defaultPrice!.toStringAsFixed(2)).wireValue;
  }

  bool _validate() {
    final nameError = ServiceFormValidation.validateName(_nameController.text);
    final priceError = ServiceFormValidation.validateDefaultPrice(_defaultPriceWire);
    final branchError = ServiceFormValidation.validateBranchSelection(
      assignAllBranches: _assignAllBranches,
      selectedBranchIds: _selectedBranchIds,
    );
    setState(() {
      _nameError = nameError;
      _defaultPriceError = priceError;
      _branchSelectionError = branchError;
    });
    return nameError == null && priceError == null && branchError == null;
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _summaryError = null;
      _staleEditError = null;
    });
    if (!_validate()) {
      return;
    }

    final branches = await ref.read(clinicSetupBranchesProvider.future);
    final allBranchIds = branches.where((branch) => branch.isActive).map((branch) => branch.id).toList(growable: false);
    final selected = _assignAllBranches ? allBranchIds.toSet() : Set<String>.from(_selectedBranchIds);
    final pendingConfigs = _pendingByBranchId.values.where((pending) => pending.hasBranchSettingsChange || pending.hasPromotion).toList(growable: false);

    try {
      if (_isCreateMode) {
        final serviceId = await ref.read(serviceEditorProvider(null).notifier).createService(
              name: _nameController.text.trim(),
              defaultPrice: _defaultPriceWire,
              globalStatus: _globalStatus,
              assignAllBranches: _assignAllBranches,
              selectedBranchIds: selected,
              pendingBranchConfigs: pendingConfigs,
            );
        if (!mounted) {
          return;
        }
        context.go(AppRoutes.settingsServiceEdit(serviceId));
        return;
      }

      await ref.read(serviceEditorProvider(widget.serviceId).notifier).updateService(
            name: _nameController.text.trim(),
            defaultPrice: _defaultPriceWire,
            globalStatus: _globalStatus,
            assignAllBranches: _assignAllBranches,
            selectedBranchIds: selected,
            allBranchIds: allBranchIds,
          );
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (error.code == 'STALE_SERVICE' || error.code == 'STALE_SERVICE_BRANCH') {
          _staleEditError = serviceCatalogMessageForRpc(error);
        } else {
          _summaryError = serviceCatalogMessageForRpc(error);
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _summaryError = error.toString());
    }
  }

  Future<void> _confirmDelete(ServiceDetail detail) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Delete service?',
      message:
          'This soft-deletes "${detail.service.name}" from the catalog. '
          'Existing invoice line snapshots are preserved.',
      confirmLabel: 'Delete service',
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    try {
      await ref.read(serviceEditorProvider(widget.serviceId).notifier).softDeleteService();
      if (!mounted) {
        return;
      }
      context.go(AppRoutes.settingsServices);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _summaryError = serviceCatalogMessageForRpc(error));
    }
  }

  void _handleCancel() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.settingsServices);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final canManage = AuthRouteGuard.canAccessServiceEditor(auth);
    if (!canManage) {
      return AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: _isCreateMode ? 'Create service' : 'Edit service',
        description: 'You do not have permission to manage the service catalog.',
      );
    }

    final editorAsync = ref.watch(serviceEditorProvider(widget.serviceId));
    final assignableAsync = ref.watch(staffAssignableBranchesProvider);
    final clinicBranchesAsync = ref.watch(clinicSetupBranchesProvider);

    return editorAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: AppSpinner()),
      error: (error, _) => AppErrorState(
        message: error.toString(),
        onRetry: () => ref.invalidate(serviceEditorProvider(widget.serviceId)),
      ),
      data: (editorState) {
        final detail = editorState.detail;
        if (!_isCreateMode && detail == null) {
          return const AppEmptyState(
            variant: AppEmptyStateVariant.noResults,
            title: 'Service not found',
            description: 'The requested service could not be loaded.',
          );
        }

        final clinicBranches = clinicBranchesAsync.maybeWhen(data: (value) => value, orElse: () => const <BranchListItem>[]);
        final assignableBranches = assignableAsync.maybeWhen(
          data: (value) => value,
          orElse: () => const <BranchSummary>[],
        );
        final branchNames = <String, String>{
          for (final branch in clinicBranches) branch.id: branch.name,
          for (final branch in assignableBranches) branch.id: branch.name,
        };

        if (!_isCreateMode && detail != null) {
          _maybeHydrate(detail, branchNames);
        }

        final selectableBranches = clinicBranches.where((branch) => branch.isActive).toList(growable: false);
        final isSaving = editorState.isSaving;
        final branchRows = _branchRows(selectableBranches, detail);

        return EditorFormPattern(
          title: _isCreateMode ? 'Create service' : 'Edit service',
          description: _isCreateMode
              ? 'Add a governed catalog service with default pricing and per-branch configuration.'
              : 'Update catalog details and branch-specific pricing for ${detail!.service.name}.',
          staleEditAlert: _staleEditError == null
              ? null
              : AppAlert(
                  variant: AppAlertVariant.warning,
                  title: _staleEditError!,
                  body: 'Reload the service and try again.',
                  actions: [
                    AppButton(
                      label: 'Reload',
                      size: AppButtonSize.sm,
                      onPressed: () => ref.read(serviceEditorProvider(widget.serviceId).notifier).reloadDetail(),
                    ),
                  ],
                ),
          summaryAlert: _summaryError == null
              ? null
              : AppAlert(variant: AppAlertVariant.danger, title: _summaryError!),
          headerActions: !_isCreateMode && detail != null
              ? AppButton(
                  label: 'Delete service',
                  variant: AppButtonVariant.danger,
                  size: AppButtonSize.sm,
                  disabled: isSaving,
                  onPressed: isSaving ? null : () => _confirmDelete(detail),
                )
              : null,
          sections: [
            EditorFormSection(
              title: 'Service details',
              description: 'Organization-wide name, default price, and global availability.',
              twoColumn: true,
              fields: [
                AppFormField(
                  label: 'Service name',
                  requiredMark: true,
                  error: _submitted ? _nameError : null,
                  child: AppTextField(
                    controller: _nameController,
                    hintText: 'e.g. General consultation',
                    disabled: isSaving,
                    invalid: _submitted && _nameError != null,
                    onChanged: (_) {
                      if (_submitted) {
                        setState(() => _nameError = null);
                      }
                    },
                  ),
                ),
                AppFormField(
                  label: 'Default price',
                  requiredMark: true,
                  error: _submitted ? _defaultPriceError : null,
                  child: AppMoneyField(
                    value: _defaultPrice,
                    disabled: isSaving,
                    invalid: _submitted && _defaultPriceError != null,
                    hintText: '0.00',
                    onValueChange: (value) => setState(() {
                      _defaultPrice = value;
                      if (_submitted) {
                        _defaultPriceError = null;
                      }
                    }),
                  ),
                ),
                AppFormField(
                  label: 'Global status',
                  helperText: 'Globally inactive services cannot be selected on invoices.',
                  child: AppSelect<GlobalStatus>(
                    options: const [
                      AppSelectOption(value: GlobalStatus.active, label: 'Active'),
                      AppSelectOption(value: GlobalStatus.inactive, label: 'Inactive'),
                    ],
                    value: _globalStatus,
                    disabled: isSaving,
                    onChanged: (value) => setState(() => _globalStatus = value),
                  ),
                ),
              ],
            ),
            EditorFormSection(
              title: 'Branch assignment',
              description: 'Choose which branches can offer this service.',
              fields: [
                AppCheckbox(
                  value: _assignAllBranches,
                  label: 'Assign to all branches',
                  disabled: isSaving,
                  onChanged: (value) => setState(() {
                    _assignAllBranches = value == true;
                    if (value == true) {
                      _selectedBranchIds
                        ..clear()
                        ..addAll(selectableBranches.map((branch) => branch.id));
                    }
                    _branchSelectionError = null;
                  }),
                ),
                if (!_assignAllBranches) ...[
                  const SizedBox(height: AppSpacing.s3),
                  Wrap(
                    spacing: AppSpacing.s3,
                    runSpacing: AppSpacing.s2,
                    children: [
                      for (final branch in selectableBranches)
                        AppCheckbox(
                          value: _selectedBranchIds.contains(branch.id),
                          label: branch.name,
                          disabled: isSaving,
                          onChanged: (checked) => setState(() {
                            if (checked == true) {
                              _selectedBranchIds.add(branch.id);
                            } else {
                              _selectedBranchIds.remove(branch.id);
                            }
                            _branchSelectionError = null;
                          }),
                        ),
                    ],
                  ),
                ],
                if (_submitted && _branchSelectionError != null) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    _branchSelectionError!,
                    style: context.typography.caption.copyWith(color: context.colors.statusDangerFg),
                  ),
                ],
              ],
            ),
          ],
          trailingContent: BranchConfigurationMatrix(
            serviceId: widget.serviceId,
            defaultPriceWire: _defaultPriceWire.isEmpty ? '0.00' : _defaultPriceWire,
            canManage: canManage,
            isCreateMode: _isCreateMode,
            branches: branchRows,
            draftSnapshot: _draftSnapshot,
            pendingByBranchId: _pendingByBranchId,
            onPendingChanged: (next) => setState(() {
              _pendingByBranchId
                ..clear()
                ..addAll(next);
            }),
          ),
          footer: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.secondary,
                disabled: isSaving,
                onPressed: _handleCancel,
              ),
              AppButton(
                label: _isCreateMode ? 'Create service' : 'Save changes',
                loading: isSaving,
                onPressed: isSaving ? null : _submit,
              ),
            ],
          ),
        );
      },
    );
  }
}
