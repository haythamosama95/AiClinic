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
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/catalog_autocomplete_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/save_to_catalog_dialog.dart';

/// Editable investigation list for visit documentation (013 US4).
class InvestigationList extends ConsumerStatefulWidget {
  const InvestigationList({
    required this.visitId,
    required this.investigations,
    required this.canEdit,
    required this.onChanged,
    super.key,
  });

  final String visitId;
  final List<VisitInvestigation> investigations;
  final bool canEdit;
  final VoidCallback onChanged;

  @override
  ConsumerState<InvestigationList> createState() => _InvestigationListState();
}

class _InvestigationListState extends ConsumerState<InvestigationList> {
  bool _showAddForm = false;
  String? _editingInvestigationId;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final investigations = widget.investigations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canEdit && !_showAddForm)
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: const Key('investigation_add_button'),
              label: 'Add investigation',
              variant: AppButtonVariant.outline,
              icon: const Icon(Icons.add, size: 18),
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() {
                      _showAddForm = true;
                      _editingInvestigationId = null;
                    }),
            ),
          ),
        if (_errorMessage != null) ...[
          const SizedBox(height: SpacingTokens.sm),
          Text(
            _errorMessage!,
            key: const Key('investigation_error'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.destructive),
          ),
        ],
        if (investigations.isEmpty && !_showAddForm)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
            child: Text(
              'No investigations ordered yet.',
              key: const Key('investigation_empty'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
            ),
          ),
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
                    onEdit: () => setState(() {
                      _editingInvestigationId = investigation.id;
                      _showAddForm = false;
                    }),
                    onArchive: () => _archiveInvestigation(investigation),
                  ),
          ),
        ),
        if (_showAddForm)
          Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.sm),
            child: InvestigationFormView(
              key: const Key('investigation_add_form'),
              isSubmitting: _isSubmitting,
              onSubmit: _addInvestigation,
              onCancel: () => setState(() => _showAddForm = false),
            ),
          ),
      ],
    );
  }

  Future<void> _addInvestigation(InvestigationFormData data) async {
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

      setState(() {
        _showAddForm = false;
        _isSubmitting = false;
      });
      widget.onChanged();

      if (isCustom && mounted) {
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

  String? _nullableTrim(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Read-only investigation card.
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
    final colors = context.semanticColors;

    return DecoratedBox(
      key: Key('investigation_card_${investigation.id}'),
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(context.shapeTokens.md),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined, size: 20, color: colors.primary),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    investigation.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (investigation.note != null && investigation.note!.isNotEmpty) ...[
                    const SizedBox(height: SpacingTokens.xs),
                    Text(
                      investigation.note!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                    ),
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
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit',
                    onPressed: onEdit,
                  ),
                  AppIconButton(
                    key: Key('investigation_archive_${investigation.id}'),
                    icon: const Icon(Icons.delete_outline, size: 18),
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
    super.key,
  });

  final VisitInvestigation? initialInvestigation;
  final bool isSubmitting;
  final void Function(InvestigationFormData data) onSubmit;
  final VoidCallback onCancel;

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
    final isEdit = widget.initialInvestigation != null;
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.md),
        border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? 'Edit investigation' : 'New investigation',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: SpacingTokens.md),
              CatalogAutocompleteField(
                key: _investigationFieldKey,
                label: 'Investigation *',
                initialName: widget.initialInvestigation?.name,
                initialCatalogId: widget.initialInvestigation?.investigationId,
                enabled: !widget.isSubmitting,
                hintText: 'Search investigations or enter a custom name',
                onSearch: (query) => ref.read(visitRepositoryProvider).searchInvestigations(query: query),
                onSelectionChanged: (selection) => setState(() => _investigationSelection = selection),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTextField(
                key: const Key('investigation_note_field'),
                label: 'Note (optional)',
                controller: _note,
                maxLines: 3,
                enabled: !widget.isSubmitting,
              ),
              const SizedBox(height: SpacingTokens.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    key: const Key('investigation_cancel_button'),
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: widget.isSubmitting ? null : widget.onCancel,
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  AppButton(
                    key: const Key('investigation_save_button'),
                    label: isEdit ? 'Update' : 'Add',
                    isLoading: widget.isSubmitting,
                    onPressed: widget.isSubmitting ? null : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _investigationFieldKey.currentState?.currentSelection.name ?? _investigationSelection.name;
    final investigationId =
        _investigationFieldKey.currentState?.currentSelection.catalogId ?? _investigationSelection.catalogId;
    final isEdit = widget.initialInvestigation != null;
    final trimmedNote = _note.text.trim();

    widget.onSubmit(
      InvestigationFormData(
        name: name.trim(),
        investigationId: investigationId,
        note: trimmedNote.isEmpty ? (isEdit ? '' : null) : trimmedNote,
      ),
    );
  }
}
