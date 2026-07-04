import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/service_catalog/application/service_form_validation.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_form_draft_snapshot.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_section_card.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_form_grid.dart';

/// Service create/edit form: name, default price, global status, branch assignment (US1).
class ServiceForm extends StatefulWidget {
  const ServiceForm({
    super.key,
    required this.branches,
    required this.onSubmit,
    this.initialName = '',
    this.initialDefaultPrice = '',
    this.initialGlobalStatus = GlobalStatus.active,
    this.initialAssignAllBranches = true,
    this.initialSelectedBranchIds = const {},
    this.isSaving = false,
    this.isEditMode = false,
    this.saveButtonLabel = 'Save service',
    this.showSubmitButton = true,
    this.onDraftChanged,
  });

  final List<BranchListItem> branches;
  final Future<void> Function({
    required String name,
    required String defaultPrice,
    required GlobalStatus globalStatus,
    required bool assignAllBranches,
    required Set<String> selectedBranchIds,
  })
  onSubmit;

  final String initialName;
  final String initialDefaultPrice;
  final GlobalStatus initialGlobalStatus;
  final bool initialAssignAllBranches;
  final Set<String> initialSelectedBranchIds;
  final bool isSaving;
  final bool isEditMode;
  final String saveButtonLabel;
  final bool showSubmitButton;
  final ValueChanged<ServiceFormDraftSnapshot>? onDraftChanged;

  @override
  State<ServiceForm> createState() => ServiceFormState();
}

class ServiceFormState extends State<ServiceForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late GlobalStatus _globalStatus;
  late bool _assignAllBranches;
  late Set<String> _selectedBranchIds;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _priceController = TextEditingController(text: widget.initialDefaultPrice);
    _globalStatus = widget.initialGlobalStatus;
    _assignAllBranches = widget.initialAssignAllBranches;
    _selectedBranchIds = Set<String>.from(widget.initialSelectedBranchIds);
    _priceController.addListener(_notifyDraftChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyDraftChanged());
  }

  @override
  void dispose() {
    _priceController.removeListener(_notifyDraftChanged);
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _notifyDraftChanged() {
    widget.onDraftChanged?.call(
      ServiceFormDraftSnapshot(
        defaultPrice: _priceController.text.trim(),
        assignAllBranches: _assignAllBranches,
        selectedBranchIds: Set<String>.from(_selectedBranchIds),
      ),
    );
  }

  Future<void> submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    await widget.onSubmit(
      name: _nameController.text.trim(),
      defaultPrice: _priceController.text.trim(),
      globalStatus: _globalStatus,
      assignAllBranches: _assignAllBranches,
      selectedBranchIds: _selectedBranchIds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeBranches = widget.branches.where((branch) => branch.isActive).toList(growable: false);
    final branchOptions = [
      for (final branch in activeBranches)
        AppSelectOption(value: branch.id, label: '${branch.name}${branch.code == null ? '' : ' (${branch.code})'}'),
    ];

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSectionCard(
            title: 'Service info',
            child: SetupFormGrid(
              columns: 3,
              children: [
                AppTextField(
                  controller: _nameController,
                  label: 'Service name',
                  hintText: 'e.g. Consultation',
                  enabled: !widget.isSaving,
                  validator: ServiceFormValidation.validateName,
                ),
                AppTextField(
                  controller: _priceController,
                  label: 'Price',
                  hintText: '0.00',
                  enabled: !widget.isSaving,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: ServiceFormValidation.validateDefaultPrice,
                ),
                AppSwitch(
                  label: 'Global status',
                  description: _globalStatus == GlobalStatus.active ? 'Active' : 'Inactive',
                  value: _globalStatus == GlobalStatus.active,
                  enabled: !widget.isSaving,
                  onChanged: (active) {
                    setState(() => _globalStatus = active ? GlobalStatus.active : GlobalStatus.inactive);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          SettingsSectionCard(
            title: 'Branch configuration',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Apply this service to', style: theme.textTheme.labelMedium),
                const SizedBox(height: SpacingTokens.sm),
                AppCheckbox(
                  label: 'Assign to all branches',
                  value: _assignAllBranches,
                  enabled: !widget.isSaving,
                  onChanged: (value) {
                    setState(() {
                      _assignAllBranches = value;
                      if (_assignAllBranches) {
                        _selectedBranchIds = {};
                      }
                    });
                    _notifyDraftChanged();
                  },
                ),
                if (!_assignAllBranches) ...[
                  const SizedBox(height: SpacingTokens.md),
                  if (branchOptions.isEmpty)
                    Text(
                      'No active branches are available. Create or reactivate a branch first.',
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    FormField<Set<String>>(
                      initialValue: _selectedBranchIds,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (_) => ServiceFormValidation.validateBranchSelection(
                        assignAllBranches: _assignAllBranches,
                        selectedBranchIds: _selectedBranchIds,
                      ),
                      builder: (field) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppSelectTileGroup<String>(
                              label: 'Assigned branches',
                              mode: AppSelectGroupMode.checkbox,
                              enabled: !widget.isSaving,
                              options: branchOptions,
                              values: _selectedBranchIds,
                              onChanged: (values) {
                                setState(() => _selectedBranchIds = values);
                                field.didChange(values);
                                _notifyDraftChanged();
                              },
                            ),
                            if (field.hasError)
                              Padding(
                                padding: const EdgeInsets.only(top: SpacingTokens.xs),
                                child: Text(
                                  field.errorText!,
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ],
            ),
          ),
          if (widget.showSubmitButton) ...[
            const SizedBox(height: SpacingTokens.lg),
            AppButton(
              label: widget.saveButtonLabel,
              expand: false,
              isLoading: widget.isSaving,
              onPressed: widget.isSaving ? null : submit,
            ),
          ],
        ],
      ),
    );
  }
}
