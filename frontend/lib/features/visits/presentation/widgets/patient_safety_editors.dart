import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/catalog_name_normalizer.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/catalog_autocomplete_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/diagnosis_autocomplete_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/save_to_catalog_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Context-phase editors for patient-level safety records (014 US6).
class PatientSafetyEditors extends ConsumerStatefulWidget {
  const PatientSafetyEditors({required this.patientId, required this.canEdit, super.key});

  final String patientId;
  final bool canEdit;

  @override
  ConsumerState<PatientSafetyEditors> createState() => _PatientSafetyEditorsState();
}

class _PatientSafetyEditorsState extends ConsumerState<PatientSafetyEditors> {
  bool _showAllergyForm = false;
  bool _showMedicationForm = false;
  bool _showConditionForm = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final safetyAsync = ref.watch(patientSafetyProvider(widget.patientId));

    return safetyAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: SpacingTokens.md),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.only(top: SpacingTokens.md),
        child: Text(
          error is RpcFailure ? visitMessageForRpc(error) : 'Could not load patient safety records.',
          style: context.visitTheme.caption(color: context.visitTheme.danger),
        ),
      ),
      data: (safety) => _buildEditors(safety),
    );
  }

  Widget _buildEditors(PatientSafetyContext safety) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: VisitPageTokens.sectionGap),
        _SafetySection(
          key: const Key('patient_safety_allergies_editor'),
          title: 'Allergies',
          description: 'Substance and reaction — no severity field',
          canEdit: widget.canEdit,
          showAddForm: _showAllergyForm,
          onAdd: () => setState(() => _showAllergyForm = true),
          isSubmitting: _isSubmitting,
          items: safety.allergies
              .map(
                (allergy) => _SafetyListTile(
                  label: allergy.substance,
                  detail: allergy.reaction,
                  canEdit: widget.canEdit,
                  onArchive: () => _archiveAllergy(allergy.id),
                ),
              )
              .toList(),
          addForm: _AllergyForm(
            isSubmitting: _isSubmitting,
            onSubmit: _createAllergy,
            onCancel: () => setState(() => _showAllergyForm = false),
          ),
        ),
        const SizedBox(height: VisitPageTokens.sectionGap),
        _SafetySection(
          key: const Key('patient_safety_medications_editor'),
          title: 'Current medications',
          description: 'Home or ongoing medications for this patient',
          canEdit: widget.canEdit,
          showAddForm: _showMedicationForm,
          onAdd: () => setState(() => _showMedicationForm = true),
          isSubmitting: _isSubmitting,
          items: safety.currentMedications
              .map(
                (med) => _SafetyListTile(
                  label: med.name,
                  detail: med.note,
                  canEdit: widget.canEdit,
                  onArchive: () => _archiveMedication(med.id),
                ),
              )
              .toList(),
          addForm: _MedicationForm(
            isSubmitting: _isSubmitting,
            onSubmit: _createMedication,
            onCancel: () => setState(() => _showMedicationForm = false),
          ),
        ),
        const SizedBox(height: VisitPageTokens.sectionGap),
        _SafetySection(
          key: const Key('patient_safety_conditions_editor'),
          title: 'Chronic conditions',
          description: 'Problem list entries linked to diagnosis catalog when available',
          canEdit: widget.canEdit,
          showAddForm: _showConditionForm,
          onAdd: () => setState(() => _showConditionForm = true),
          isSubmitting: _isSubmitting,
          items: safety.chronicConditions
              .map(
                (condition) => _SafetyListTile(
                  label: condition.name,
                  detail: condition.note,
                  canEdit: widget.canEdit,
                  onArchive: () => _archiveCondition(condition.id),
                ),
              )
              .toList(),
          addForm: _ConditionForm(
            isSubmitting: _isSubmitting,
            onSubmit: _createCondition,
            onCancel: () => setState(() => _showConditionForm = false),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: SpacingTokens.sm),
          Text(_errorMessage!, style: context.visitTheme.caption(color: context.visitTheme.danger)),
        ],
      ],
    );
  }

  Future<void> _refreshSafety() async {
    await ref.read(patientSafetyProvider(widget.patientId).notifier).refresh();
  }

  Future<void> _createAllergy({required String substance, String? reaction}) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(visitRepositoryProvider)
          .createPatientAllergy(
            patientId: widget.patientId,
            substance: CatalogNameNormalizer.normalize(substance),
            reaction: reaction?.trim().isEmpty == true ? null : reaction?.trim(),
          );
      setState(() => _showAllergyForm = false);
      await _refreshSafety();
    } on RpcFailure catch (error) {
      setState(() => _errorMessage = visitMessageForRpc(error));
    } catch (error) {
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _archiveAllergy(String id) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(visitRepositoryProvider).archivePatientAllergy(allergyId: id);
      await _refreshSafety();
    } on RpcFailure catch (error) {
      setState(() => _errorMessage = visitMessageForRpc(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _createMedication(CatalogFieldSelection selection, String? note) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final normalized = CatalogNameNormalizer.normalize(selection.name);
      if (normalized.isEmpty) {
        setState(() => _errorMessage = 'Medication name is required.');
        return;
      }

      if (selection.isCustom) {
        final save = await SaveToCatalogDialog.show(context, normalizedName: normalized, itemTypeLabel: 'medication');
        if (save == true) {
          await ref.read(visitRepositoryProvider).createCatalogMedication(name: normalized);
        }
      }

      await ref
          .read(visitRepositoryProvider)
          .createPatientMedication(
            patientId: widget.patientId,
            name: normalized,
            medicationId: selection.catalogId,
            note: note?.trim().isEmpty == true ? null : note?.trim(),
          );
      setState(() => _showMedicationForm = false);
      await _refreshSafety();
    } on RpcFailure catch (error) {
      setState(() => _errorMessage = visitMessageForRpc(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _archiveMedication(String id) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(visitRepositoryProvider).archivePatientMedication(medicationRecordId: id);
      await _refreshSafety();
    } on RpcFailure catch (error) {
      setState(() => _errorMessage = visitMessageForRpc(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _createCondition(CatalogFieldSelection selection, String? note) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final normalized = CatalogNameNormalizer.normalize(selection.name);
      if (normalized.isEmpty) {
        setState(() => _errorMessage = 'Condition name is required.');
        return;
      }

      String? diagnosisCodeId = selection.catalogId;
      if (selection.isCustom) {
        final save = await SaveToCatalogDialog.show(context, normalizedName: normalized, itemTypeLabel: 'diagnosis');
        if (save == true) {
          final created = await ref.read(visitRepositoryProvider).createCatalogDiagnosisCode(name: normalized);
          diagnosisCodeId = created.id;
        }
      }

      await ref
          .read(visitRepositoryProvider)
          .createPatientChronicCondition(
            patientId: widget.patientId,
            name: normalized,
            diagnosisCodeId: diagnosisCodeId,
            note: note?.trim().isEmpty == true ? null : note?.trim(),
          );
      setState(() => _showConditionForm = false);
      await _refreshSafety();
    } on RpcFailure catch (error) {
      setState(() => _errorMessage = visitMessageForRpc(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _archiveCondition(String id) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(visitRepositoryProvider).archivePatientChronicCondition(conditionId: id);
      await _refreshSafety();
    } on RpcFailure catch (error) {
      setState(() => _errorMessage = visitMessageForRpc(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class _SafetySection extends StatelessWidget {
  const _SafetySection({
    required this.title,
    required this.description,
    required this.canEdit,
    required this.showAddForm,
    required this.onAdd,
    required this.isSubmitting,
    required this.items,
    required this.addForm,
    super.key,
  });

  final String title;
  final String description;
  final bool canEdit;
  final bool showAddForm;
  final VoidCallback onAdd;
  final bool isSubmitting;
  final List<Widget> items;
  final Widget addForm;

  @override
  Widget build(BuildContext context) {
    return VisitSectionCard(
      kind: VisitPanelKind.clinicalNote,
      title: title,
      description: description,
      headerActions: canEdit && !showAddForm
          ? [
              AppNotchedCardAction(
                providesOwnBackground: true,
                action: AppButton(
                  label: 'Add',
                  size: AppFieldSize.sm,
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: isSubmitting ? null : onAdd,
                ),
              ),
            ]
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isEmpty && !showAddForm)
            VisitEmptyHint(message: 'No $title recorded yet.', icon: Icons.health_and_safety_outlined),
          ...items,
          if (showAddForm) ...[const SizedBox(height: SpacingTokens.sm), addForm],
        ],
      ),
    );
  }
}

class _SafetyListTile extends StatelessWidget {
  const _SafetyListTile({required this.label, required this.canEdit, required this.onArchive, this.detail});

  final String label;
  final String? detail;
  final bool canEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    return Padding(
      padding: const EdgeInsets.only(top: SpacingTokens.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.bodyStrong()),
                if (detail != null && detail!.trim().isNotEmpty)
                  Text(detail!, style: theme.caption(color: theme.mutedInk)),
              ],
            ),
          ),
          if (canEdit)
            AppIconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, size: 18), onPressed: onArchive),
        ],
      ),
    );
  }
}

class _AllergyForm extends StatefulWidget {
  const _AllergyForm({required this.isSubmitting, required this.onSubmit, required this.onCancel});

  final bool isSubmitting;
  final Future<void> Function({required String substance, String? reaction}) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_AllergyForm> createState() => _AllergyFormState();
}

class _AllergyFormState extends State<_AllergyForm> {
  final _substanceController = TextEditingController();
  final _reactionController = TextEditingController();

  @override
  void dispose() {
    _substanceController.dispose();
    _reactionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(label: 'Substance', controller: _substanceController, enabled: !widget.isSubmitting),
        const SizedBox(height: SpacingTokens.sm),
        AppTextField(label: 'Reaction (optional)', controller: _reactionController, enabled: !widget.isSubmitting),
        const SizedBox(height: SpacingTokens.sm),
        Row(
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.outline,
              expand: false,
              onPressed: widget.isSubmitting ? null : widget.onCancel,
            ),
            const SizedBox(width: SpacingTokens.sm),
            AppButton(
              label: 'Save allergy',
              expand: false,
              isLoading: widget.isSubmitting,
              onPressed: widget.isSubmitting
                  ? null
                  : () => widget.onSubmit(substance: _substanceController.text, reaction: _reactionController.text),
            ),
          ],
        ),
      ],
    );
  }
}

class _MedicationForm extends ConsumerStatefulWidget {
  const _MedicationForm({required this.isSubmitting, required this.onSubmit, required this.onCancel});

  final bool isSubmitting;
  final Future<void> Function(CatalogFieldSelection selection, String? note) onSubmit;
  final VoidCallback onCancel;

  @override
  ConsumerState<_MedicationForm> createState() => _MedicationFormState();
}

class _MedicationFormState extends ConsumerState<_MedicationForm> {
  CatalogFieldSelection _selection = const CatalogFieldSelection(name: '');
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogAutocompleteField(
          label: 'Medication',
          enabled: !widget.isSubmitting,
          onSearch: (query) => ref.read(visitRepositoryProvider).searchMedications(query: query),
          onSelectionChanged: (selection) => setState(() => _selection = selection),
        ),
        const SizedBox(height: SpacingTokens.sm),
        AppTextField(label: 'Note (optional)', controller: _noteController, enabled: !widget.isSubmitting),
        const SizedBox(height: SpacingTokens.sm),
        Row(
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.outline,
              expand: false,
              onPressed: widget.isSubmitting ? null : widget.onCancel,
            ),
            const SizedBox(width: SpacingTokens.sm),
            AppButton(
              label: 'Save medication',
              expand: false,
              isLoading: widget.isSubmitting,
              onPressed: widget.isSubmitting ? null : () => widget.onSubmit(_selection, _noteController.text),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConditionForm extends ConsumerStatefulWidget {
  const _ConditionForm({required this.isSubmitting, required this.onSubmit, required this.onCancel});

  final bool isSubmitting;
  final Future<void> Function(CatalogFieldSelection selection, String? note) onSubmit;
  final VoidCallback onCancel;

  @override
  ConsumerState<_ConditionForm> createState() => _ConditionFormState();
}

class _ConditionFormState extends ConsumerState<_ConditionForm> {
  CatalogFieldSelection _selection = const CatalogFieldSelection(name: '');
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DiagnosisAutocompleteField(
          enabled: !widget.isSubmitting,
          onSearchDiagnosisCodes: (query) => ref.read(visitRepositoryProvider).searchDiagnosisCodes(query: query),
          onSelectionChanged: (selection) => setState(() => _selection = selection),
        ),
        const SizedBox(height: SpacingTokens.sm),
        AppTextField(label: 'Note (optional)', controller: _noteController, enabled: !widget.isSubmitting),
        const SizedBox(height: SpacingTokens.sm),
        Row(
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.outline,
              expand: false,
              onPressed: widget.isSubmitting ? null : widget.onCancel,
            ),
            const SizedBox(width: SpacingTokens.sm),
            AppButton(
              label: 'Save condition',
              expand: false,
              isLoading: widget.isSubmitting,
              onPressed: widget.isSubmitting ? null : () => widget.onSubmit(_selection, _noteController.text),
            ),
          ],
        ),
      ],
    );
  }
}
