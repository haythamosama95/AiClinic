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
import 'package:ai_clinic/features/visits/presentation/widgets/save_to_catalog_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/health_profile_card_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
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
              style: context.visitTheme.caption(color: context.visitTheme.danger),
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: borderRadius,
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(decoration: BoxDecoration(gradient: cardTheme.pulseCardGradient)),
            ),
            Column(
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
                      Icon(Icons.health_and_safety_outlined, size: 20, color: theme.pulse),
                      const SizedBox(width: SpacingTokens.sm),
                      Expanded(child: Text('Health profile', style: theme.title())),
                      Text('Tracked across all visits', style: theme.caption(size: 13)),
                    ],
                  ),
                ),
                if (expandBody) Expanded(child: body) else body,
              ],
            ),
          ],
        ),
      ),
    );
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
        kind: VisitPanelKind.allergy,
        title: 'Allergies',
        accent: context.visitTheme.danger,
        items: [
          for (final allergy in widget.safetyContext.allergies)
            _HealthItem(
              id: allergy.id,
              title: allergy.substance,
              subtitle: allergy.reaction,
              onArchive: widget.canEdit ? () => _archiveAllergy(allergy) : null,
            ),
        ],
        canEdit: widget.canEdit,
        emptyMessage: 'No allergies recorded',
        addLabel: 'Add allergy',
        addFormBuilder: (onDone) => _AllergyAddForm(patientId: widget.patientId, onDone: onDone),
      ),
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
              onArchive: widget.canEdit ? () => _archiveCondition(condition) : null,
            ),
        ],
        canEdit: widget.canEdit,
        emptyMessage: 'No chronic conditions',
        addLabel: 'Add condition',
        addFormBuilder: (onDone) => _ConditionAddForm(patientId: widget.patientId, onDone: onDone),
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
              onArchive: widget.canEdit ? () => _archiveMedication(med) : null,
            ),
        ],
        canEdit: widget.canEdit,
        emptyMessage: 'No home medications',
        addLabel: 'Add medication',
        addFormBuilder: (onDone) => _MedicationAddForm(patientId: widget.patientId, onDone: onDone),
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
  const _HealthItem({required this.id, required this.title, this.subtitle, this.onArchive});

  final String id;
  final String title;
  final String? subtitle;
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
    final count = config.items.length;
    final hasItems = count > 0;
    final isEmpty = !hasItems;

    final addIconButton = config.canEdit && hasItems
        ? AppIconButton(
            icon: Icon(Icons.add_rounded, size: 20, color: config.accent),
            tooltip: config.addLabel,
            onPressed: () => _showAddDialog(context),
          )
        : null;

    final header = Row(
      children: [
        Icon(config.kind.icon, size: 18, color: config.accent),
        const SizedBox(width: SpacingTokens.xs),
        Expanded(
          child: Text(config.title, style: theme.bodyStrong(size: 13, color: config.accent)),
        ),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: config.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$count', style: theme.caption(size: 11, color: config.accent)),
          ),
        ?addIconButton,
      ],
    );

    final centeredAddButton = config.canEdit && isEmpty
        ? AppButton(
            label: config.addLabel,
            size: AppFieldSize.sm,
            variant: AppButtonVariant.ghost,
            icon: Icon(Icons.add, size: 16, color: config.accent),
            onPressed: () => _showAddDialog(context),
          )
        : null;

    final itemsBody = hasItems
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...config.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
                  child: _HealthItemTile(item: item, accent: config.accent),
                ),
              ),
            ],
          )
        : Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(config.emptyMessage, style: theme.caption()),
                if (centeredAddButton != null) ...[const SizedBox(height: SpacingTokens.sm), centeredAddButton],
              ],
            ),
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(theme.tileRadius),
        border: Border.all(color: config.accent.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: expandBody ? MainAxisSize.max : MainAxisSize.min,
          children: [
            header,
            const SizedBox(height: SpacingTokens.sm),
            if (expandBody)
              Expanded(child: hasItems ? SingleChildScrollView(child: itemsBody) : itemsBody)
            else
              itemsBody,
          ],
        ),
      ),
    );
  }
}

class _HealthItemTile extends StatelessWidget {
  const _HealthItemTile({required this.item, required this.accent});

  final _HealthItem item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final subtitle = item.subtitle?.trim();

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: theme.bodyStrong(size: 13)),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.caption(size: 13)),
                  ],
                ],
              ),
            ),
            if (item.onArchive != null)
              AppIconButton(
                icon: Icon(Icons.close_rounded, size: 18, color: theme.mutedInk),
                tooltip: 'Remove',
                onPressed: item.onArchive,
              ),
          ],
        ),
      ),
    );
  }
}

class _AllergyAddForm extends ConsumerStatefulWidget {
  const _AllergyAddForm({required this.patientId, required this.onDone});

  final String patientId;
  final VoidCallback onDone;

  @override
  ConsumerState<_AllergyAddForm> createState() => _AllergyAddFormState();
}

class _AllergyAddFormState extends ConsumerState<_AllergyAddForm> {
  final _substanceController = TextEditingController();
  final _reactionController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _substanceController.dispose();
    _reactionController.dispose();
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
        VisitTextInput(label: 'Reaction', controller: _reactionController, enabled: !_submitting),
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
      await ref
          .read(visitRepositoryProvider)
          .createPatientAllergy(
            patientId: widget.patientId,
            substance: substance,
            reaction: _reactionController.text.trim().isEmpty ? null : _reactionController.text.trim(),
          );
      await ref.read(patientSafetyProvider(widget.patientId).notifier).refresh();
      if (mounted) widget.onDone();
    } on RpcFailure catch (e) {
      if (mounted) AppToast.error(context, message: visitMessageForRpc(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _ConditionAddForm extends ConsumerStatefulWidget {
  const _ConditionAddForm({required this.patientId, required this.onDone});

  final String patientId;
  final VoidCallback onDone;

  @override
  ConsumerState<_ConditionAddForm> createState() => _ConditionAddFormState();
}

class _ConditionAddFormState extends ConsumerState<_ConditionAddForm> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  bool _submitting = false;

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
      await ref
          .read(visitRepositoryProvider)
          .createPatientChronicCondition(
            patientId: widget.patientId,
            name: name,
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          );
      await ref.read(patientSafetyProvider(widget.patientId).notifier).refresh();
      if (mounted) widget.onDone();
    } on RpcFailure catch (e) {
      if (mounted) AppToast.error(context, message: visitMessageForRpc(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _MedicationAddForm extends ConsumerStatefulWidget {
  const _MedicationAddForm({required this.patientId, required this.onDone});

  final String patientId;
  final VoidCallback onDone;

  @override
  ConsumerState<_MedicationAddForm> createState() => _MedicationAddFormState();
}

class _MedicationAddFormState extends ConsumerState<_MedicationAddForm> {
  final _medicationFieldKey = GlobalKey<CatalogAutocompleteFieldState>();
  final _noteController = TextEditingController();
  CatalogFieldSelection _selection = const CatalogFieldSelection(name: '');
  bool _submitting = false;

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
      await ref
          .read(visitRepositoryProvider)
          .createPatientMedication(
            patientId: widget.patientId,
            name: name,
            medicationId: selection.catalogId,
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          );
      await ref.read(patientSafetyProvider(widget.patientId).notifier).refresh();
      if (mounted) widget.onDone();

      if (mounted && selection.isCustom) {
        await _maybeSaveToCatalog(name);
      }
    } on RpcFailure catch (e) {
      if (mounted) AppToast.error(context, message: visitMessageForRpc(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _maybeSaveToCatalog(String normalizedName) async {
    final save = await SaveToCatalogDialog.show(context, normalizedName: normalizedName, itemTypeLabel: 'medication');
    if (save != true || !mounted) return;
    try {
      await ref.read(visitRepositoryProvider).createCatalogMedication(name: normalizedName);
      if (mounted) AppToast.success(context, message: 'Saved "$normalizedName" to your medication catalog.');
    } on RpcFailure catch (e) {
      if (mounted) AppToast.error(context, message: visitMessageForRpc(e));
    }
  }
}
