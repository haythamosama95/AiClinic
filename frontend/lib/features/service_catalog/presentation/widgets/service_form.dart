import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/service_catalog/application/service_form_validation.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';

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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
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
          AppTextField(
            controller: _nameController,
            label: 'Service name',
            hintText: 'e.g. Consultation',
            enabled: !widget.isSaving,
            validator: ServiceFormValidation.validateName,
          ),
          const SizedBox(height: SpacingTokens.md),
          AppTextField(
            controller: _priceController,
            label: 'Default price',
            hintText: '0.00',
            enabled: !widget.isSaving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: ServiceFormValidation.validateDefaultPrice,
          ),
          const SizedBox(height: SpacingTokens.md),
          AppSelectTileGroup<GlobalStatus>(
            label: 'Global status',
            mode: AppSelectGroupMode.radio,
            enabled: !widget.isSaving,
            options: const [
              AppSelectOption(value: GlobalStatus.active, label: 'Active'),
              AppSelectOption(value: GlobalStatus.inactive, label: 'Inactive'),
            ],
            values: {_globalStatus},
            onChanged: (values) {
              if (values.isNotEmpty) {
                setState(() => _globalStatus = values.first);
              }
            },
          ),
          const SizedBox(height: SpacingTokens.lg),
          Text('Branch assignment', style: Theme.of(context).textTheme.titleSmall),
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
            },
          ),
          if (!_assignAllBranches) ...[
            const SizedBox(height: SpacingTokens.md),
            if (branchOptions.isEmpty)
              Text(
                'No active branches are available. Create or reactivate a branch first.',
                style: Theme.of(context).textTheme.bodySmall,
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
                  final theme = Theme.of(context);
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
          const SizedBox(height: SpacingTokens.lg),
          AppButton(
            label: widget.saveButtonLabel,
            expand: false,
            isLoading: widget.isSaving,
            onPressed: widget.isSaving ? null : submit,
          ),
        ],
      ),
    );
  }
}
