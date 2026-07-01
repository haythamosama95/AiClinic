import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/catalog_name_normalizer.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/catalog_autocomplete_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/save_to_catalog_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_text_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Context-phase editors for patient-level safety records (014 US6).
class PatientSafetyEditors extends ConsumerStatefulWidget {
  const PatientSafetyEditors({
    required this.patientId,
    required this.canEdit,
    this.axis = Axis.horizontal,
    this.expandSections = false,
    super.key,
  });

  final String patientId;
  final bool canEdit;
  final Axis axis;
  final bool expandSections;

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
    final conditions = _SafetySection(
      key: const Key('patient_safety_conditions_editor'),
      kind: VisitPanelKind.chronicCondition,
      title: 'Chronic conditions',
      canEdit: widget.canEdit,
      showAddForm: _showConditionForm,
      onAdd: () => setState(() => _showConditionForm = true),
      isSubmitting: _isSubmitting,
      expandBody: widget.expandSections,
      items: safety.chronicConditions
          .map(
            (condition) => _SafetyListTile(
              label: condition.name,
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
    );

    final medications = _SafetySection(
      key: const Key('patient_safety_medications_editor'),
      kind: VisitPanelKind.currentMedication,
      title: 'Current medications',
      canEdit: widget.canEdit,
      showAddForm: _showMedicationForm,
      onAdd: () => setState(() => _showMedicationForm = true),
      isSubmitting: _isSubmitting,
      expandBody: widget.expandSections,
      items: safety.currentMedications
          .map(
            (med) =>
                _SafetyListTile(label: med.name, canEdit: widget.canEdit, onArchive: () => _archiveMedication(med.id)),
          )
          .toList(),
      addForm: _MedicationForm(
        isSubmitting: _isSubmitting,
        onSubmit: _createMedication,
        onCancel: () => setState(() => _showMedicationForm = false),
      ),
    );

    final allergies = _SafetySection(
      key: const Key('patient_safety_allergies_editor'),
      kind: VisitPanelKind.allergy,
      title: 'Allergies',
      canEdit: widget.canEdit,
      showAddForm: _showAllergyForm,
      onAdd: () => setState(() => _showAllergyForm = true),
      isSubmitting: _isSubmitting,
      expandBody: widget.expandSections,
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
    );

    final sections = widget.axis == Axis.vertical
        ? [
            if (widget.expandSections) Expanded(child: conditions) else conditions,
            const SizedBox(height: VisitPageTokens.sectionGap),
            if (widget.expandSections) Expanded(child: medications) else medications,
            const SizedBox(height: VisitPageTokens.sectionGap),
            if (widget.expandSections) Expanded(child: allergies) else allergies,
          ]
        : [
            Expanded(child: conditions),
            const SizedBox(width: VisitPageTokens.sectionGap),
            Expanded(child: medications),
            const SizedBox(width: VisitPageTokens.sectionGap),
            Expanded(child: allergies),
          ];

    final sectionLayout = widget.axis == Axis.vertical
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sections)
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: sections);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.expandSections) Expanded(child: sectionLayout) else sectionLayout,
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

  Future<void> _createMedication(CatalogFieldSelection selection) async {
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
          .createPatientMedication(patientId: widget.patientId, name: normalized, medicationId: selection.catalogId);
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

  Future<void> _createCondition({required String name}) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final normalized = CatalogNameNormalizer.normalize(name);
      if (normalized.isEmpty) {
        setState(() => _errorMessage = 'Condition name is required.');
        return;
      }

      await ref
          .read(visitRepositoryProvider)
          .createPatientChronicCondition(patientId: widget.patientId, name: normalized);
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
    required this.kind,
    required this.title,
    required this.canEdit,
    required this.showAddForm,
    required this.onAdd,
    required this.isSubmitting,
    required this.items,
    required this.addForm,
    this.expandBody = false,
    super.key,
  });

  final VisitPanelKind kind;
  final String title;
  final bool canEdit;
  final bool showAddForm;
  final VoidCallback onAdd;
  final bool isSubmitting;
  final List<Widget> items;
  final Widget addForm;
  final bool expandBody;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isEmpty && !showAddForm)
          VisitEmptyHint(message: 'No $title recorded yet.', icon: Icons.health_and_safety_outlined),
        ...items,
        if (showAddForm) ...[const SizedBox(height: SpacingTokens.sm), addForm],
      ],
    );

    final card = VisitSectionCard(
      kind: kind,
      title: title,
      headerActions: canEdit && !showAddForm
          ? [
              AppNotchedCardAction(
                providesOwnBackground: true,
                action: _PrimaryAddButton(onPressed: isSubmitting ? null : onAdd),
              ),
            ]
          : null,
      child: expandBody ? SingleChildScrollView(child: content) : content,
    );

    if (!expandBody) return card;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Expanded(child: card)],
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
        VisitTextField(label: 'Substance', controller: _substanceController, enabled: !widget.isSubmitting),
        const SizedBox(height: SpacingTokens.sm),
        VisitTextField(label: 'Reaction (optional)', controller: _reactionController, enabled: !widget.isSubmitting),
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
  final Future<void> Function(CatalogFieldSelection selection) onSubmit;
  final VoidCallback onCancel;

  @override
  ConsumerState<_MedicationForm> createState() => _MedicationFormState();
}

class _MedicationFormState extends ConsumerState<_MedicationForm> {
  CatalogFieldSelection _selection = const CatalogFieldSelection(name: '');

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
              onPressed: widget.isSubmitting ? null : () => widget.onSubmit(_selection),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConditionForm extends StatefulWidget {
  const _ConditionForm({required this.isSubmitting, required this.onSubmit, required this.onCancel});

  final bool isSubmitting;
  final Future<void> Function({required String name}) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_ConditionForm> createState() => _ConditionFormState();
}

class _ConditionFormState extends State<_ConditionForm> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VisitTextField(label: 'Condition', controller: _nameController, enabled: !widget.isSubmitting),
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
              onPressed: widget.isSubmitting ? null : () => widget.onSubmit(name: _nameController.text),
            ),
          ],
        ),
      ],
    );
  }
}

class _PrimaryAddButton extends StatelessWidget {
  const _PrimaryAddButton({required this.onPressed});

  final VoidCallback? onPressed;

  static const _size = 32.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final enabled = onPressed != null;

    return Tooltip(
      message: 'Add',
      child: Material(
        color: enabled ? colors.primary : colors.muted,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: _size,
            height: _size,
            child: Center(
              child: Icon(Icons.add, size: 18, color: enabled ? colors.primaryForeground : colors.mutedForeground),
            ),
          ),
        ),
      ),
    );
  }
}
