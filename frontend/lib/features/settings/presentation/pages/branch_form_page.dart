import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/settings/presentation/providers/branch_form_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/branch_form_fields.dart';

/// Create or edit a branch (US2).
class BranchFormPage extends ConsumerStatefulWidget {
  const BranchFormPage({this.branchId, super.key});

  final String? branchId;

  @override
  ConsumerState<BranchFormPage> createState() => _BranchFormPageState();
}

class _BranchFormPageState extends ConsumerState<BranchFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _mapsUrlController = TextEditingController();
  bool _controllersInitialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _mapsUrlController.dispose();
    super.dispose();
  }

  void _syncControllers(BranchFormUiState ui) {
    final existing = ui.existing;
    if (existing == null || _controllersInitialized) {
      return;
    }
    _nameController.text = existing.name;
    _codeController.text = existing.code ?? '';
    _addressController.text = existing.address ?? '';
    _phoneController.text = existing.phone ?? '';
    _mapsUrlController.text = existing.mapsUrl ?? '';
    _controllersInitialized = true;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final savedId = await ref
        .read(branchFormProvider(widget.branchId).notifier)
        .save(
          name: _nameController.text,
          code: _codeController.text,
          address: _addressController.text,
          phone: _phoneController.text,
          mapsUrl: _mapsUrlController.text,
        );

    if (savedId != null && mounted) {
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        context.go(AppRoutes.settingsBranches);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formAsync = ref.watch(branchFormProvider(widget.branchId));
    final isEdit = widget.branchId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit branch' : 'New branch'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.settingsBranches),
        ),
      ),
      body: formAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load branch: $error')),
        data: (ui) {
          if (ui.errorMessage != null && ui.existing == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(ui.errorMessage!, textAlign: TextAlign.center),
              ),
            );
          }

          if (ui.permissionDenied) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('You do not have permission to manage branches.', textAlign: TextAlign.center),
              ),
            );
          }

          _syncControllers(ui);
          final existing = ui.existing;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (ui.errorMessage != null) ...[
                    Text(ui.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 16),
                  ],
                  BranchFormFields(
                    mode: isEdit ? BranchFormFieldsMode.edit : BranchFormFieldsMode.create,
                    nameController: _nameController,
                    codeController: _codeController,
                    addressController: _addressController,
                    phoneController: _phoneController,
                    mapsUrlController: _mapsUrlController,
                    existing: existing == null
                        ? null
                        : BranchFormExistingData(
                            name: existing.name,
                            code: existing.code,
                            address: existing.address,
                            phone: existing.phone,
                            mapsUrl: existing.mapsUrl,
                          ),
                    enabled: !ui.isSaving,
                    fieldErrors: ui.fieldErrors,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: ui.isSaving ? null : _save,
                    child: ui.isSaving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(isEdit ? 'Save changes' : 'Create branch'),
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
