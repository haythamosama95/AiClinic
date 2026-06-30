import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/catalog_name_normalizer.dart';
import 'package:ai_clinic/features/visits/domain/visit_diagnosis_code.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/catalog_autocomplete_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/diagnosis_autocomplete_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/save_to_catalog_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Coded diagnosis lines for the Assessment phase (014 US7).
class VisitDiagnosisCodeList extends ConsumerStatefulWidget {
  const VisitDiagnosisCodeList({required this.visitId, required this.diagnosisCodes, required this.canEdit, super.key});

  final String visitId;
  final List<VisitDiagnosisCode> diagnosisCodes;
  final bool canEdit;

  @override
  ConsumerState<VisitDiagnosisCodeList> createState() => _VisitDiagnosisCodeListState();
}

class _VisitDiagnosisCodeListState extends ConsumerState<VisitDiagnosisCodeList> {
  bool _showAddForm = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return VisitSectionCard(
      kind: VisitPanelKind.clinicalNote,
      title: 'Coded diagnosis',
      description: 'Optional structured codes alongside free-text diagnosis',
      headerActions: widget.canEdit && !_showAddForm
          ? [
              AppNotchedCardAction(
                providesOwnBackground: true,
                action: AppButton(
                  key: const Key('visit_diagnosis_code_add_button'),
                  label: 'Add code',
                  size: AppFieldSize.sm,
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: _isSubmitting ? null : () => setState(() => _showAddForm = true),
                ),
              ),
            ]
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            Text(_errorMessage!, style: context.visitTheme.caption(color: context.visitTheme.danger)),
            const SizedBox(height: SpacingTokens.sm),
          ],
          if (widget.diagnosisCodes.isEmpty && !_showAddForm)
            const VisitEmptyHint(
              key: Key('visit_diagnosis_code_empty'),
              message: 'No coded diagnosis lines yet.',
              icon: Icons.medical_information_outlined,
            ),
          ...widget.diagnosisCodes.map(
            (code) => Padding(
              padding: const EdgeInsets.only(top: SpacingTokens.sm),
              child: Row(
                children: [
                  Expanded(child: Text(code.displayLabel, style: context.visitTheme.bodyStrong())),
                  if (widget.canEdit)
                    AppIconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: _isSubmitting ? null : () => _archive(code.id),
                    ),
                ],
              ),
            ),
          ),
          if (_showAddForm) ...[
            const SizedBox(height: SpacingTokens.sm),
            _DiagnosisCodeAddForm(
              isSubmitting: _isSubmitting,
              onCancel: () => setState(() => _showAddForm = false),
              onSubmit: _addCode,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addCode(CatalogFieldSelection selection) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final normalized = CatalogNameNormalizer.normalize(selection.name);
      if (normalized.isEmpty) {
        setState(() => _errorMessage = 'Diagnosis label is required.');
        return;
      }

      String? diagnosisCodeId = selection.catalogId;
      String? code;
      if (selection.isCustom) {
        final save = await SaveToCatalogDialog.show(context, normalizedName: normalized, itemTypeLabel: 'diagnosis');
        if (save == true) {
          final created = await ref.read(visitRepositoryProvider).createCatalogDiagnosisCode(name: normalized);
          diagnosisCodeId = created.id;
        }
      } else if (diagnosisCodeId != null) {
        final items = await ref.read(visitRepositoryProvider).searchDiagnosisCodes(query: normalized, limit: 1);
        if (items.isNotEmpty && items.first.id == diagnosisCodeId) {
          code = items.first.code;
        }
      }

      await ref
          .read(visitDocumentationProvider(widget.visitId).notifier)
          .addVisitDiagnosisCode(label: normalized, code: code, diagnosisCodeId: diagnosisCodeId);
      if (mounted) setState(() => _showAddForm = false);
    } on RpcFailure catch (error) {
      setState(() => _errorMessage = visitMessageForRpc(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _archive(String id) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(visitDocumentationProvider(widget.visitId).notifier).archiveVisitDiagnosisCode(id);
    } on RpcFailure catch (error) {
      setState(() => _errorMessage = visitMessageForRpc(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class _DiagnosisCodeAddForm extends ConsumerStatefulWidget {
  const _DiagnosisCodeAddForm({required this.isSubmitting, required this.onCancel, required this.onSubmit});

  final bool isSubmitting;
  final VoidCallback onCancel;
  final Future<void> Function(CatalogFieldSelection selection) onSubmit;

  @override
  ConsumerState<_DiagnosisCodeAddForm> createState() => _DiagnosisCodeAddFormState();
}

class _DiagnosisCodeAddFormState extends ConsumerState<_DiagnosisCodeAddForm> {
  CatalogFieldSelection _selection = const CatalogFieldSelection(name: '');

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
              label: 'Add diagnosis code',
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

/// Read-only summary of coded diagnosis lines.
class VisitDiagnosisCodeSummary extends StatelessWidget {
  const VisitDiagnosisCodeSummary({required this.diagnosisCodes, super.key});

  final List<VisitDiagnosisCode> diagnosisCodes;

  @override
  Widget build(BuildContext context) {
    if (diagnosisCodes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('CODED DIAGNOSIS', style: context.visitTheme.eyebrow(size: 10)),
        const SizedBox(height: SpacingTokens.xs),
        ...diagnosisCodes.map(
          (code) => Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
            child: Text(code.displayLabel, style: context.visitTheme.body()),
          ),
        ),
      ],
    );
  }
}
