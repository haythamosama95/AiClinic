import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/catalog_name_normalizer.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/catalog_autocomplete_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/health_profile_card_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_text_field.dart';

/// Patient-level chronic conditions, medications, and allergies for the Intake step (014 US6).
class PatientHealthTrackingCard extends ConsumerWidget {
  const PatientHealthTrackingCard({required this.patientId, required this.canEdit, this.expandBody = false, super.key});

  final String patientId;
  final bool canEdit;
  final bool expandBody;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safetyAsync = ref.watch(patientSafetyProvider(patientId));

    return KeyedSubtree(
      key: const Key('patient_health_tracking_card'),
      child: safetyAsync.when(
        loading: () => _HealthProfileShell(
          expandBody: expandBody,
          child: const Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => _HealthProfileShell(
          expandBody: expandBody,
          child: Padding(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Text(
              'Unable to load health profile.',
              style: context.healthProfileCardTheme.errorMessage(context.visitTheme.danger),
            ),
          ),
        ),
        data: (safetyContext) => _HealthProfileShell(
          expandBody: expandBody,
          child: _HealthProfileBody(
            patientId: patientId,
            canEdit: canEdit,
            safetyContext: safetyContext,
            expandBody: expandBody,
          ),
        ),
      ),
    );
  }
}

class _HealthProfileShell extends StatelessWidget {
  const _HealthProfileShell({required this.child, required this.expandBody});

  final Widget child;
  final bool expandBody;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final cardTheme = context.healthProfileCardTheme;
    final colors = context.semanticColors;
    final borderRadius = BorderRadius.circular(context.shapeTokens.lg);

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(SpacingTokens.md, 0, SpacingTokens.md, SpacingTokens.md),
      child: child,
    );

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: borderRadius,
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: expandBody ? StackFit.expand : StackFit.loose,
          children: [
            Positioned.fill(
              child: DecoratedBox(decoration: BoxDecoration(gradient: cardTheme.pulseCardGradient)),
            ),
            SizedBox(
              width: double.infinity,
              height: expandBody ? double.infinity : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: expandBody ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      SpacingTokens.md,
                      SpacingTokens.md,
                      SpacingTokens.md,
                      SpacingTokens.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.health_and_safety_outlined,
                          size: HealthProfileCardTokens.shellIconSize,
                          color: theme.pulse,
                        ),
                        const SizedBox(width: SpacingTokens.sm),
                        Expanded(child: Text('Health profile', style: cardTheme.shellTitle)),
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Tracked across all visits',
                              style: cardTheme.shellSubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (expandBody) Expanded(child: body) else body,
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (expandBody) {
      return SizedBox(width: double.infinity, height: double.infinity, child: card);
    }

    return card;
  }
}

class _HealthProfileBody extends ConsumerStatefulWidget {
  const _HealthProfileBody({
    required this.patientId,
    required this.canEdit,
    required this.safetyContext,
    required this.expandBody,
  });

  final String patientId;
  final bool canEdit;
  final PatientSafetyContext safetyContext;
  final bool expandBody;

  @override
  ConsumerState<_HealthProfileBody> createState() => _HealthProfileBodyState();
}

class _HealthProfileBodyState extends ConsumerState<_HealthProfileBody> {
  @override
  Widget build(BuildContext context) {
    final sections = [
      _HealthSectionConfig(
        kind: VisitPanelKind.chronicCondition,
        title: 'Chronic conditions',
        accent: context.visitTheme.pulse,
        items: [
          for (final condition in widget.safetyContext.chronicConditions)
            _HealthItem(
              id: condition.id,
              title: condition.name,
              subtitle: condition.note,
              onEdit: widget.canEdit ? () => _editCondition(condition) : null,
              onArchive: widget.canEdit ? () => _archiveCondition(condition) : null,
            ),
        ],
        canEdit: widget.canEdit,
        emptyMessage: 'No chronic conditions recorded.',
        addLabel: 'Add condition',
        addFormBuilder: (onDone) => _ConditionForm(patientId: widget.patientId, onDone: onDone),
      ),
      _HealthSectionConfig(
        kind: VisitPanelKind.currentMedication,
        title: 'Current medications',
        accent: context.visitTheme.pulse,
        items: [
          for (final med in widget.safetyContext.currentMedications)
            _HealthItem(
              id: med.id,
              title: med.name,
              subtitle: med.note,
              onEdit: widget.canEdit ? () => _editMedication(med) : null,
              onArchive: widget.canEdit ? () => _archiveMedication(med) : null,
            ),
        ],
        canEdit: widget.canEdit,
        emptyMessage: 'No current medications recorded.',
        addLabel: 'Add medication',
        addFormBuilder: (onDone) => _MedicationForm(patientId: widget.patientId, onDone: onDone),
      ),
      _HealthSectionConfig(
        kind: VisitPanelKind.allergy,
        title: 'Allergies',
        accent: context.visitTheme.pulse,
        items: [
          for (final allergy in widget.safetyContext.allergies)
            _HealthItem(
              id: allergy.id,
              title: allergy.substance,
              subtitle: allergy.reaction,
              onEdit: widget.canEdit ? () => _editAllergy(allergy) : null,
              onArchive: widget.canEdit ? () => _archiveAllergy(allergy) : null,
            ),
        ],
        canEdit: widget.canEdit,
        emptyMessage: 'No allergies recorded.',
        addLabel: 'Add allergy',
        addFormBuilder: (onDone) => _AllergyForm(patientId: widget.patientId, onDone: onDone),
      ),
    ];

    if (widget.expandBody) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: SpacingTokens.md),
            Expanded(child: _HealthSection(config: sections[i], expandBody: true)),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: SpacingTokens.md),
          _HealthSection(config: sections[i]),
        ],
      ],
    );
  }

  Future<void> _refreshSafety() {
    return ref.read(patientSafetyProvider(widget.patientId).notifier).refresh();
  }

  Future<void> _editAllergy(PatientAllergy allergy) async {
    await AppDialog.show<void>(
      context: context,
      title: 'Edit allergy',
      bodyBuilder: (dialogContext) =>
          _AllergyForm(patientId: widget.patientId, allergy: allergy, onDone: () => Navigator.of(dialogContext).pop()),
    );
  }

  Future<void> _editCondition(PatientChronicCondition condition) async {
    await AppDialog.show<void>(
      context: context,
      title: 'Edit condition',
      bodyBuilder: (dialogContext) => _ConditionForm(
        patientId: widget.patientId,
        condition: condition,
        onDone: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  Future<void> _editMedication(PatientMedication medication) async {
    await AppDialog.show<void>(
      context: context,
      title: 'Edit medication',
      bodyBuilder: (dialogContext) => _MedicationForm(
        patientId: widget.patientId,
        medication: medication,
        onDone: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  Future<void> _archiveAllergy(PatientAllergy allergy) async {
    final confirmed = await _confirmRemove(context, title: allergy.substance, label: 'allergy');
    if (!confirmed || !mounted) return;
    try {
      await ref.read(visitRepositoryProvider).archivePatientAllergy(allergyId: allergy.id);
      await _refreshSafety();
    } on RpcFailure catch (e) {
      if (mounted) AppToast.error(context, message: visitMessageForRpc(e));
    }
  }

  Future<void> _archiveMedication(PatientMedication med) async {
    final confirmed = await _confirmRemove(context, title: med.name, label: 'medication');
    if (!confirmed || !mounted) return;
    try {
      await ref.read(visitRepositoryProvider).archivePatientMedication(medicationRecordId: med.id);
      await _refreshSafety();
    } on RpcFailure catch (e) {
      if (mounted) AppToast.error(context, message: visitMessageForRpc(e));
    }
  }

  Future<void> _archiveCondition(PatientChronicCondition condition) async {
    final confirmed = await _confirmRemove(context, title: condition.name, label: 'condition');
    if (!confirmed || !mounted) return;
    try {
      await ref.read(visitRepositoryProvider).archivePatientChronicCondition(conditionId: condition.id);
      await _refreshSafety();
    } on RpcFailure catch (e) {
      if (mounted) AppToast.error(context, message: visitMessageForRpc(e));
    }
  }

  Future<bool> _confirmRemove(BuildContext context, {required String title, required String label}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $label?'),
        content: Text('Remove "$title" from this patient\'s health profile?'),
        actions: [
          AppButton(label: 'Cancel', variant: AppButtonVariant.secondary, onPressed: () => Navigator.pop(ctx, false)),
          AppButton(label: 'Remove', variant: AppButtonVariant.destructive, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    return result == true;
  }
}

@immutable
class _HealthSectionConfig {
  const _HealthSectionConfig({
    required this.kind,
    required this.title,
    required this.accent,
    required this.items,
    required this.canEdit,
    required this.emptyMessage,
    required this.addLabel,
    required this.addFormBuilder,
  });

  final VisitPanelKind kind;
  final String title;
  final Color accent;
  final List<_HealthItem> items;
  final bool canEdit;
  final String emptyMessage;
  final String addLabel;
  final Widget Function(VoidCallback onDone) addFormBuilder;
}

@immutable
class _HealthItem {
  const _HealthItem({required this.id, required this.title, this.subtitle, this.onEdit, this.onArchive});

  final String id;
  final String title;
  final String? subtitle;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;
}

class _HealthSection extends StatelessWidget {
  const _HealthSection({required this.config, this.expandBody = false});

  final _HealthSectionConfig config;
  final bool expandBody;

  void _showAddDialog(BuildContext context) {
    AppDialog.show<void>(
      context: context,
      title: config.addLabel,
      bodyBuilder: (dialogContext) => config.addFormBuilder(() => Navigator.of(dialogContext).pop()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final cardTheme = context.healthProfileCardTheme;
    final count = config.items.length;
    final hasItems = count > 0;

    final addIconButton = config.canEdit && hasItems
        ? AppIconButton(
            icon: Icon(Icons.add_rounded, size: HealthProfileCardTokens.addIconSize, color: config.accent),
            tooltip: config.addLabel,
            onPressed: () => _showAddDialog(context),
          )
        : null;

    final header = Row(
      children: [
        Icon(config.kind.icon, size: HealthProfileCardTokens.sectionIconSize, color: config.accent),
        const SizedBox(width: SpacingTokens.xs),
        Expanded(child: Text(config.title, style: cardTheme.sectionTitle(config.accent))),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: config.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$count', style: cardTheme.countBadge(config.accent)),
          ),
        ?addIconButton,
      ],
    );

    final itemsBody = hasItems
        ? GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: SpacingTokens.xs,
              mainAxisSpacing: SpacingTokens.xs,
              mainAxisExtent: HealthProfileCardTokens.gridTileExtent,
            ),
            itemCount: config.items.length,
            itemBuilder: (context, index) => _HealthGridTile(item: config.items[index], accent: config.accent),
          )
        : VisitEmptyHint(
            message: config.emptyMessage,
            showIcon: false,
            actionLabel: config.canEdit ? config.addLabel : null,
            onAction: config.canEdit ? () => _showAddDialog(context) : null,
          );

    final sectionBody = Padding(
      padding: const EdgeInsets.all(SpacingTokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expandBody ? MainAxisSize.max : MainAxisSize.min,
        children: [
          header,
          const SizedBox(height: SpacingTokens.sm),
          if (expandBody)
            Expanded(
              child: encounterExpandedSectionBody(expandBody: true, centerWhenEmpty: !hasItems, child: itemsBody),
            )
          else
            itemsBody,
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(theme.tileRadius),
        border: Border.all(color: config.accent.withValues(alpha: 0.18)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(theme.tileRadius),
        child: TiltedBackgroundIconStack(
          icon: config.kind.icon,
          iconSize: HealthProfileCardTokens.sectionWatermarkIconSize,
          iconColor: cardTheme.sectionWatermark(config.accent),
          fillChild: expandBody,
          child: sectionBody,
        ),
      ),
    );
  }
}

class _HealthGridTile extends StatelessWidget {
  const _HealthGridTile({required this.item, required this.accent});

  final _HealthItem item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final cardTheme = context.healthProfileCardTheme;
    final subtitle = item.subtitle?.trim();
    final label = subtitle != null && subtitle.isNotEmpty ? '${item.title} - $subtitle' : item.title;
    final hasActions = item.onEdit != null || item.onArchive != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.semanticColors.card,
        borderRadius: BorderRadius.circular(theme.tileRadius - 2),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs + 2),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: cardTheme.itemLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (hasActions) ...[
              if (item.onEdit != null)
                AppIconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    size: HealthProfileCardTokens.tileActionIconSize,
                    color: theme.mutedInk,
                  ),
                  tooltip: 'Edit',
                  onPressed: item.onEdit,
                ),
              if (item.onArchive != null)
                AppIconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: HealthProfileCardTokens.tileActionIconSize,
                    color: theme.mutedInk,
                  ),
                  tooltip: 'Remove',
                  onPressed: item.onArchive,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AllergyForm extends ConsumerStatefulWidget {
  const _AllergyForm({required this.patientId, required this.onDone, this.allergy});

  final String patientId;
  final VoidCallback onDone;
  final PatientAllergy? allergy;

  @override
  ConsumerState<_AllergyForm> createState() => _AllergyFormState();
}

class _AllergyFormState extends ConsumerState<_AllergyForm> {
  late final TextEditingController _substanceController;
  String? _severity;
  bool _submitting = false;

  bool get _isEditing => widget.allergy != null;

  @override
  void initState() {
    super.initState();
    final allergy = widget.allergy;
    _substanceController = TextEditingController(text: allergy?.substance ?? '');
    final reaction = allergy?.reaction?.trim();
    if (reaction != null && AllergySeverityOptions.items.containsValue(reaction)) {
      _severity = reaction;
    }
  }

  @override
  void dispose() {
    _substanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VisitTextInput(label: 'Substance *', controller: _substanceController, enabled: !_submitting),
        const SizedBox(height: SpacingTokens.sm),
        AppSelect<String>(
          label: 'Severity',
          hintText: 'Optional',
          items: AllergySeverityOptions.items,
          value: _severity,
          enabled: !_submitting,
          size: AppFieldSize.sm,
          onChanged: (value) => setState(() => _severity = value),
        ),
        const SizedBox(height: SpacingTokens.sm),
        Row(
          children: [
            AppButton(
              label: 'Cancel',
              size: AppFieldSize.sm,
              variant: AppButtonVariant.outline,
              expand: false,
              onPressed: _submitting ? null : widget.onDone,
            ),
            const SizedBox(width: SpacingTokens.sm),
            AppButton(label: 'Save', size: AppFieldSize.sm, expand: false, onPressed: _submitting ? null : _submit),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final substance = CatalogNameNormalizer.normalize(_substanceController.text);
    if (substance.isEmpty) {
      AppToast.error(context, message: 'Substance is required.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final repository = ref.read(visitRepositoryProvider);
      if (_isEditing) {
        await repository.updatePatientAllergy(allergyId: widget.allergy!.id, substance: substance, reaction: _severity);
      } else {
        await repository.createPatientAllergy(patientId: widget.patientId, substance: substance, reaction: _severity);
      }
      await ref.read(patientSafetyProvider(widget.patientId).notifier).refresh();
      if (mounted) widget.onDone();
    } on RpcFailure catch (e) {
      if (mounted) AppToast.error(context, message: visitMessageForRpc(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _ConditionForm extends ConsumerStatefulWidget {
  const _ConditionForm({required this.patientId, required this.onDone, this.condition});

  final String patientId;
  final VoidCallback onDone;
  final PatientChronicCondition? condition;

  @override
  ConsumerState<_ConditionForm> createState() => _ConditionFormState();
}

class _ConditionFormState extends ConsumerState<_ConditionForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _noteController;
  bool _submitting = false;

  bool get _isEditing => widget.condition != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.condition?.name ?? '');
    _noteController = TextEditingController(text: widget.condition?.note ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VisitTextInput(label: 'Condition *', controller: _nameController, enabled: !_submitting),
        const SizedBox(height: SpacingTokens.sm),
        VisitTextInput(label: 'Note', controller: _noteController, enabled: !_submitting),
        const SizedBox(height: SpacingTokens.sm),
        Row(
          children: [
            AppButton(
              label: 'Cancel',
              size: AppFieldSize.sm,
              variant: AppButtonVariant.outline,
              expand: false,
              onPressed: _submitting ? null : widget.onDone,
            ),
            const SizedBox(width: SpacingTokens.sm),
            AppButton(label: 'Save', size: AppFieldSize.sm, expand: false, onPressed: _submitting ? null : _submit),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final name = CatalogNameNormalizer.normalize(_nameController.text);
    if (name.isEmpty) {
      AppToast.error(context, message: 'Condition name is required.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final repository = ref.read(visitRepositoryProvider);
      final note = _noteController.text.trim().isEmpty ? null : _noteController.text.trim();
      if (_isEditing) {
        await repository.updatePatientChronicCondition(conditionId: widget.condition!.id, name: name, note: note);
      } else {
        await repository.createPatientChronicCondition(patientId: widget.patientId, name: name, note: note);
      }
      await ref.read(patientSafetyProvider(widget.patientId).notifier).refresh();
      if (mounted) widget.onDone();
    } on RpcFailure catch (e) {
      if (mounted) AppToast.error(context, message: visitMessageForRpc(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _MedicationForm extends ConsumerStatefulWidget {
  const _MedicationForm({required this.patientId, required this.onDone, this.medication});

  final String patientId;
  final VoidCallback onDone;
  final PatientMedication? medication;

  @override
  ConsumerState<_MedicationForm> createState() => _MedicationFormState();
}

class _MedicationFormState extends ConsumerState<_MedicationForm> {
  final _medicationFieldKey = GlobalKey<CatalogAutocompleteFieldState>();
  late final TextEditingController _noteController;
  CatalogFieldSelection _selection = const CatalogFieldSelection(name: '');
  bool _submitting = false;

  bool get _isEditing => widget.medication != null;

  @override
  void initState() {
    super.initState();
    final medication = widget.medication;
    _noteController = TextEditingController(text: medication?.note ?? '');
    if (medication != null) {
      _selection = CatalogFieldSelection(name: medication.name, catalogId: medication.medicationId);
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogAutocompleteField(
          key: _medicationFieldKey,
          label: 'Medication *',
          enabled: !_submitting,
          initialName: widget.medication?.name,
          initialCatalogId: widget.medication?.medicationId,
          onSearch: (query) => ref.read(visitRepositoryProvider).searchMedications(query: query),
          onSelectionChanged: (selection) => setState(() => _selection = selection),
        ),
        const SizedBox(height: SpacingTokens.sm),
        VisitTextInput(label: 'Note', controller: _noteController, enabled: !_submitting),
        const SizedBox(height: SpacingTokens.sm),
        Row(
          children: [
            AppButton(
              label: 'Cancel',
              size: AppFieldSize.sm,
              variant: AppButtonVariant.outline,
              expand: false,
              onPressed: _submitting ? null : widget.onDone,
            ),
            const SizedBox(width: SpacingTokens.sm),
            AppButton(label: 'Save', size: AppFieldSize.sm, expand: false, onPressed: _submitting ? null : _submit),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final selection = _medicationFieldKey.currentState?.currentSelection ?? _selection;
    final name = CatalogNameNormalizer.normalize(selection.name);
    if (name.isEmpty) {
      AppToast.error(context, message: 'Medication name is required.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final repository = ref.read(visitRepositoryProvider);
      final note = _noteController.text.trim().isEmpty ? null : _noteController.text.trim();
      if (_isEditing) {
        await repository.updatePatientMedication(
          medicationRecordId: widget.medication!.id,
          name: name,
          medicationId: selection.catalogId,
          note: note,
        );
      } else {
        await repository.createPatientMedication(
          patientId: widget.patientId,
          name: name,
          medicationId: selection.catalogId,
          note: note,
        );
      }
      await ref.read(patientSafetyProvider(widget.patientId).notifier).refresh();
      if (mounted) widget.onDone();
    } on RpcFailure catch (e) {
      if (mounted) AppToast.error(context, message: visitMessageForRpc(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
