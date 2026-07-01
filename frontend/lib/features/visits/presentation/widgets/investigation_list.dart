import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/catalog_name_normalizer.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/catalog_autocomplete_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_field_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/health_profile_card_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/save_to_catalog_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_text_field.dart';

/// Opens the add-investigation dialog used by [InvestigationList].
Future<void> showInvestigationAddDialog({
  required BuildContext context,
  required String visitId,
  required VoidCallback onRefresh,
}) {
  return AppDialog.show<void>(
    context: context,
    title: 'Add investigation',
    bodyBuilder: (dialogContext) => _InvestigationAddDialogBody(
      visitId: visitId,
      hostContext: context,
      onCancel: () => Navigator.of(dialogContext).pop(),
      onRefresh: onRefresh,
      onSaved: () {
        Navigator.of(dialogContext).pop();
        onRefresh();
      },
    ),
  );
}

/// Editable investigation list for visit documentation (013 US4).
class InvestigationList extends ConsumerStatefulWidget {
  const InvestigationList({
    required this.visitId,
    required this.investigations,
    required this.canEdit,
    required this.onChanged,
    required this.sectionTitle,
    required this.sectionKind,
    this.encounterShell = false,
    this.expandBody = false,
    super.key,
  });

  final String visitId;
  final List<VisitInvestigation> investigations;
  final bool canEdit;
  final VoidCallback onChanged;
  final String sectionTitle;
  final VisitPanelKind sectionKind;
  final bool encounterShell;
  final bool expandBody;

  @override
  ConsumerState<InvestigationList> createState() => _InvestigationListState();
}

class _InvestigationListState extends ConsumerState<InvestigationList> {
  String? _editingInvestigationId;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _hasItems => widget.investigations.isNotEmpty;

  Future<void> _openAddDialog() async {
    if (_isSubmitting) return;

    await showInvestigationAddDialog(context: context, visitId: widget.visitId, onRefresh: widget.onChanged);
  }

  List<Widget>? _shelfActions() {
    if (!widget.canEdit || widget.encounterShell || !_hasItems) return null;

    return [
      AppNotchedCardAction(
        providesOwnBackground: true,
        action: AppButton(
          key: const Key('investigation_add_button'),
          label: 'Add investigation',
          size: AppFieldSize.sm,
          icon: const Icon(Icons.add, size: 18),
          onPressed: _isSubmitting ? null : _openAddDialog,
        ),
      ),
    ];
  }

  Widget? _encounterHeaderTrailing() {
    if (!widget.encounterShell || !widget.canEdit || !_hasItems) return null;

    final theme = context.visitTheme;
    return AppIconButton(
      key: const Key('investigation_add_button'),
      icon: Icon(Icons.add_rounded, size: HealthProfileCardTokens.addIconSize, color: theme.pulse),
      tooltip: 'Add investigation',
      onPressed: _isSubmitting ? null : _openAddDialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = encounterExpandedSectionBody(
      expandBody: widget.expandBody,
      centerWhenEmpty: widget.encounterShell && _shouldCenterEmptyState(),
      child: _buildBody(),
    );

    if (widget.encounterShell) {
      return EncounterFieldCard(
        title: widget.sectionTitle,
        titleIcon: widget.sectionKind.icon,
        expandBody: widget.expandBody,
        headerTrailing: _encounterHeaderTrailing(),
        child: body,
      );
    }

    return VisitSectionCard(
      kind: widget.sectionKind,
      title: widget.sectionTitle,
      headerActions: _shelfActions(),
      child: body,
    );
  }

  bool _shouldCenterEmptyState() {
    return !_hasItems && _errorMessage == null;
  }

  Widget _buildEmptyState() {
    return VisitEmptyHint(
      key: const Key('investigation_empty'),
      message: 'No investigations ordered yet.',
      icon: Icons.biotech_outlined,
      actionLabel: widget.canEdit ? 'Add investigation' : null,
      onAction: widget.canEdit ? _openAddDialog : null,
      actionKey: widget.canEdit ? const Key('investigation_add_button') : null,
    );
  }

  Widget _buildBody() {
    final investigations = widget.investigations;

    if (widget.encounterShell && widget.expandBody && _shouldCenterEmptyState()) {
      return _buildEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errorMessage != null) ...[
          const SizedBox(height: SpacingTokens.sm),
          Text(
            _errorMessage!,
            key: const Key('investigation_error'),
            style: context.visitTheme.caption(color: context.visitTheme.danger),
          ),
        ],
        if (investigations.isEmpty) _buildEmptyState(),
        ...investigations.map(
          (investigation) => Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.sm),
            child: _editingInvestigationId == investigation.id
                ? InvestigationFormView(
                    key: Key('investigation_edit_form_${investigation.id}'),
                    initialInvestigation: investigation,
                    isSubmitting: _isSubmitting,
                    onSubmit: (data) => _updateInvestigation(investigation, data),
                    onCancel: () => setState(() => _editingInvestigationId = null),
                  )
                : InvestigationCardView(
                    investigation: investigation,
                    canEdit: widget.canEdit,
                    onEdit: () => setState(() => _editingInvestigationId = investigation.id),
                    onArchive: () => _archiveInvestigation(investigation),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _updateInvestigation(VisitInvestigation existing, InvestigationFormData data) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final normalizedName = CatalogNameNormalizer.normalize(data.name);
      if (normalizedName.isEmpty) {
        throw RpcFailure(
          RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Investigation name is required.'),
        );
      }

      final normalizedData = InvestigationFormData(
        name: normalizedName,
        investigationId: data.investigationId,
        note: data.note,
      );
      final updateParams = normalizedData.updateParamsFor(existing);

      final hasChanges = updateParams.name != null || updateParams.investigationId != null || updateParams.note != null;

      if (hasChanges) {
        await ref
            .read(visitRepositoryProvider)
            .updateVisitInvestigation(
              investigationLineId: existing.id,
              name: updateParams.name,
              investigationId: updateParams.investigationId,
              note: updateParams.note,
            );
      }

      if (!mounted) return;

      final becameCustom = data.isCustomInvestigation && existing.investigationId != null;
      final wasCustom = existing.investigationId == null;
      final nameChanged = normalizedName != existing.name;

      setState(() {
        _editingInvestigationId = null;
        _isSubmitting = false;
      });
      widget.onChanged();

      if (mounted && (becameCustom || (wasCustom && nameChanged))) {
        await _maybeSaveCustomToCatalog(normalizedName: normalizedName);
      }
    } on RpcFailure catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = visitMessageForRpc(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _archiveInvestigation(VisitInvestigation investigation) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove investigation?'),
        content: Text('Remove "${investigation.name}" from this visit?'),
        actions: [
          AppButton(label: 'Cancel', variant: AppButtonVariant.secondary, onPressed: () => Navigator.pop(ctx, false)),
          AppButton(label: 'Remove', variant: AppButtonVariant.destructive, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (remove != true || !mounted) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(visitRepositoryProvider).archiveVisitInvestigation(investigationLineId: investigation.id);
      if (mounted) {
        setState(() => _isSubmitting = false);
        widget.onChanged();
      }
    } on RpcFailure catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = visitMessageForRpc(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _maybeSaveCustomToCatalog({required String normalizedName}) async {
    if (!mounted) return;

    final save = await SaveToCatalogDialog.show(
      context,
      normalizedName: normalizedName,
      itemTypeLabel: 'investigation',
    );
    if (save != true || !mounted) return;

    try {
      await ref.read(visitRepositoryProvider).createCatalogInvestigation(name: normalizedName);
      if (!mounted) return;
      AppToast.success(context, message: 'Saved "$normalizedName" to your investigation catalog.');
    } on RpcFailure catch (e) {
      if (!mounted) return;
      AppToast.error(context, message: visitMessageForRpc(e));
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, message: e.toString());
    }
  }
}

/// Read-only investigation card — lab order style.
class InvestigationCardView extends StatelessWidget {
  const InvestigationCardView({
    required this.investigation,
    this.canEdit = false,
    this.onEdit,
    this.onArchive,
    super.key,
  });

  final VisitInvestigation investigation;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return DecoratedBox(
      key: Key('investigation_card_${investigation.id}'),
      decoration: BoxDecoration(
        color: theme.tile,
        borderRadius: BorderRadius.circular(theme.tileRadius),
        border: Border.all(color: theme.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SpacingTokens.md, SpacingTokens.md, SpacingTokens.sm, SpacingTokens.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: theme.pulse.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(theme.tileRadius - 2),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.biotech_outlined, size: 16, color: theme.pulseDeep),
            ),
            const SizedBox(width: SpacingTokens.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(investigation.name, style: theme.title(size: 15)),
                  if (investigation.note != null && investigation.note!.isNotEmpty) ...[
                    const SizedBox(height: SpacingTokens.sm),
                    Text('Note', style: theme.eyebrow(size: 10)),
                    const SizedBox(height: SpacingTokens.xs),
                    Text(investigation.note!, style: theme.body()),
                  ],
                  if (investigation.hasResult) ...[
                    const SizedBox(height: SpacingTokens.sm),
                    Text('Result', style: theme.eyebrow(size: 10)),
                    const SizedBox(height: SpacingTokens.xs),
                    Text(investigation.result!, style: theme.body()),
                    if (investigation.resultRecordedAt != null) ...[
                      const SizedBox(height: SpacingTokens.xs),
                      Text(
                        'Recorded ${DateFormat.yMMMd().add_jm().format(investigation.resultRecordedAt!.toLocal())}',
                        style: theme.caption(color: theme.mutedInk),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            if (canEdit)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIconButton(
                    key: Key('investigation_edit_${investigation.id}'),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    tooltip: 'Edit',
                    onPressed: onEdit,
                  ),
                  AppIconButton(
                    key: Key('investigation_archive_${investigation.id}'),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    tooltip: 'Remove',
                    onPressed: onArchive,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Form data for creating or updating an investigation line.
class InvestigationFormData {
  const InvestigationFormData({required this.name, this.investigationId, this.note});

  final String name;
  final String? investigationId;
  final String? note;

  bool get isCustomInvestigation => investigationId == null;

  ({String? name, String? investigationId, String? note}) updateParamsFor(VisitInvestigation existing) {
    final trimmedName = name.trim();
    return (
      name: trimmedName != existing.name ? trimmedName : null,
      investigationId: investigationId != existing.investigationId ? investigationId : null,
      note: _optionalUpdateParam(existing.note, note),
    );
  }

  static String? _optionalUpdateParam(String? existing, String? submitted) {
    if (submitted == null) {
      return null;
    }
    if (_normalizeOptional(existing) == _normalizeOptional(submitted)) {
      return null;
    }
    return submitted;
  }

  static String? _normalizeOptional(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }
}

/// Add/edit form for an investigation line.
class InvestigationFormView extends ConsumerStatefulWidget {
  const InvestigationFormView({
    this.initialInvestigation,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onCancel,
    this.inDialog = false,
    super.key,
  });

  final VisitInvestigation? initialInvestigation;
  final bool isSubmitting;
  final void Function(InvestigationFormData data) onSubmit;
  final VoidCallback onCancel;
  final bool inDialog;

  @override
  ConsumerState<InvestigationFormView> createState() => _InvestigationFormViewState();
}

class _InvestigationFormViewState extends ConsumerState<InvestigationFormView> {
  final _formKey = GlobalKey<FormState>();
  final _investigationFieldKey = GlobalKey<CatalogAutocompleteFieldState>();
  late final TextEditingController _note;
  CatalogFieldSelection _investigationSelection = const CatalogFieldSelection(name: '');

  @override
  void initState() {
    super.initState();
    final investigation = widget.initialInvestigation;
    _investigationSelection = CatalogFieldSelection(
      name: investigation?.name ?? '',
      catalogId: investigation?.investigationId,
    );
    _note = TextEditingController(text: investigation?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final isEdit = widget.initialInvestigation != null;

    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.inDialog) ...[
            Text(isEdit ? 'Edit investigation' : 'New investigation', style: theme.title(size: 15)),
            const SizedBox(height: SpacingTokens.md),
          ],
          CatalogAutocompleteField(
            key: _investigationFieldKey,
            label: 'Investigation *',
            initialName: widget.initialInvestigation?.name,
            initialCatalogId: widget.initialInvestigation?.investigationId,
            enabled: !widget.isSubmitting,
            onSearch: (query) => ref.read(visitRepositoryProvider).searchInvestigations(query: query),
            onSelectionChanged: (selection) => setState(() => _investigationSelection = selection),
            validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: SpacingTokens.sm),
          VisitTextField(
            key: const Key('investigation_note_field'),
            label: 'Note',
            controller: _note,
            enabled: !widget.isSubmitting,
            maxLines: 3,
          ),
          const SizedBox(height: SpacingTokens.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                key: const Key('investigation_cancel_button'),
                label: 'Cancel',
                variant: AppButtonVariant.secondary,
                expand: false,
                onPressed: widget.isSubmitting ? null : widget.onCancel,
              ),
              const SizedBox(width: SpacingTokens.sm),
              AppButton(
                key: const Key('investigation_save_button'),
                label: isEdit ? 'Update' : 'Add',
                isLoading: widget.isSubmitting,
                expand: false,
                onPressed: widget.isSubmitting ? null : _submit,
              ),
            ],
          ),
        ],
      ),
    );

    if (widget.inDialog) {
      return form;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.tile,
        borderRadius: BorderRadius.circular(theme.tileRadius),
        border: Border.all(color: theme.pulse.withValues(alpha: 0.35)),
      ),
      child: Padding(padding: const EdgeInsets.all(SpacingTokens.lg), child: form),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _investigationFieldKey.currentState?.currentSelection.name ?? _investigationSelection.name;
    final investigationId =
        _investigationFieldKey.currentState?.currentSelection.catalogId ?? _investigationSelection.catalogId;
    final note = _note.text.trim();
    widget.onSubmit(
      InvestigationFormData(name: name.trim(), investigationId: investigationId, note: note.isEmpty ? '' : note),
    );
  }
}

class _InvestigationAddDialogBody extends ConsumerStatefulWidget {
  const _InvestigationAddDialogBody({
    required this.visitId,
    required this.hostContext,
    required this.onCancel,
    required this.onRefresh,
    required this.onSaved,
  });

  final String visitId;
  final BuildContext hostContext;
  final VoidCallback onCancel;
  final VoidCallback onRefresh;
  final VoidCallback onSaved;

  @override
  ConsumerState<_InvestigationAddDialogBody> createState() => _InvestigationAddDialogBodyState();
}

class _InvestigationAddDialogBodyState extends ConsumerState<_InvestigationAddDialogBody> {
  bool _isSubmitting = false;

  Future<void> _submit(InvestigationFormData data) async {
    setState(() => _isSubmitting = true);

    try {
      final normalizedName = CatalogNameNormalizer.normalize(data.name);
      if (normalizedName.isEmpty) {
        throw RpcFailure(
          RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Investigation name is required.'),
        );
      }

      final isCustom = data.isCustomInvestigation;
      await ref
          .read(visitRepositoryProvider)
          .createVisitInvestigation(
            visitId: widget.visitId,
            name: normalizedName,
            note: _nullableTrim(data.note),
            investigationId: data.investigationId,
          );

      if (!mounted) return;

      if (isCustom) {
        await _maybeSaveCustomToCatalog(normalizedName: normalizedName);
      }

      widget.onSaved();
    } on RpcFailure catch (e) {
      if (mounted) AppToast.error(context, message: visitMessageForRpc(e));
    } catch (e) {
      if (mounted) AppToast.error(context, message: e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _maybeSaveCustomToCatalog({required String normalizedName}) async {
    final save = await SaveToCatalogDialog.show(
      widget.hostContext,
      normalizedName: normalizedName,
      itemTypeLabel: 'investigation',
    );
    if (save != true || !widget.hostContext.mounted) return;

    try {
      await ref.read(visitRepositoryProvider).createCatalogInvestigation(name: normalizedName);
      if (!widget.hostContext.mounted) return;
      AppToast.success(widget.hostContext, message: 'Saved "$normalizedName" to your investigation catalog.');
      widget.onRefresh();
    } on RpcFailure catch (e) {
      if (!widget.hostContext.mounted) return;
      AppToast.error(widget.hostContext, message: visitMessageForRpc(e));
    } catch (e) {
      if (!widget.hostContext.mounted) return;
      AppToast.error(widget.hostContext, message: e.toString());
    }
  }

  String? _nullableTrim(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return InvestigationFormView(
      key: const Key('investigation_add_form'),
      isSubmitting: _isSubmitting,
      inDialog: true,
      onSubmit: _submit,
      onCancel: widget.onCancel,
    );
  }
}
