import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_text_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Capture investigation results for lines ordered on prior visits (014 US8).
class InvestigationResultCaptureList extends ConsumerStatefulWidget {
  const InvestigationResultCaptureList({
    required this.pendingInvestigations,
    required this.canEdit,
    required this.onChanged,
    super.key,
  });

  final List<VisitInvestigation> pendingInvestigations;
  final bool canEdit;
  final VoidCallback onChanged;

  @override
  ConsumerState<InvestigationResultCaptureList> createState() => _InvestigationResultCaptureListState();
}

class _InvestigationResultCaptureListState extends ConsumerState<InvestigationResultCaptureList> {
  String? _editingInvestigationId;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    if (widget.pendingInvestigations.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = context.visitTheme;

    return VisitSectionCard(
      kind: VisitPanelKind.investigationResult,
      title: 'Investigation results',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            Text(_errorMessage!, style: theme.caption(color: theme.danger)),
            const SizedBox(height: SpacingTokens.sm),
          ],
          for (final investigation in widget.pendingInvestigations)
            Padding(
              padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
              child: _editingInvestigationId == investigation.id
                  ? _InvestigationResultForm(
                      key: Key('investigation_result_form_${investigation.id}'),
                      investigation: investigation,
                      isSubmitting: _isSubmitting,
                      onSubmit: (result) => _saveResult(investigation, result),
                      onCancel: () => setState(() => _editingInvestigationId = null),
                    )
                  : _PendingInvestigationTile(
                      investigation: investigation,
                      canEdit: widget.canEdit,
                      onRecord: widget.canEdit
                          ? () => setState(() {
                              _editingInvestigationId = investigation.id;
                              _errorMessage = null;
                            })
                          : null,
                    ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveResult(VisitInvestigation investigation, String result) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(visitRepositoryProvider)
          .recordInvestigationResult(investigationLineId: investigation.id, result: result.trim());
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _editingInvestigationId = null;
      });
      widget.onChanged();
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
}

class _PendingInvestigationTile extends StatelessWidget {
  const _PendingInvestigationTile({required this.investigation, required this.canEdit, this.onRecord});

  final VisitInvestigation investigation;
  final bool canEdit;
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final orderedDate = investigation.orderedVisitDate;

    return DecoratedBox(
      key: Key('pending_investigation_${investigation.id}'),
      decoration: BoxDecoration(
        color: theme.tile,
        borderRadius: BorderRadius.circular(theme.tileRadius),
        border: Border.all(color: theme.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(investigation.name, style: theme.title(size: 15)),
                  if (orderedDate != null) ...[
                    const SizedBox(height: SpacingTokens.xs),
                    Text(
                      'Ordered ${DateFormat.yMMMd().format(orderedDate.toLocal())}',
                      style: theme.caption(color: theme.mutedInk),
                    ),
                  ],
                ],
              ),
            ),
            if (canEdit && onRecord != null)
              AppButton(
                key: Key('investigation_result_record_${investigation.id}'),
                label: 'Record result',
                size: AppFieldSize.sm,
                variant: AppButtonVariant.secondary,
                onPressed: onRecord,
              ),
          ],
        ),
      ),
    );
  }
}

class _InvestigationResultForm extends StatefulWidget {
  const _InvestigationResultForm({
    required this.investigation,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onCancel,
    super.key,
  });

  final VisitInvestigation investigation;
  final bool isSubmitting;
  final Future<void> Function(String result) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_InvestigationResultForm> createState() => _InvestigationResultFormState();
}

class _InvestigationResultFormState extends State<_InvestigationResultForm> {
  late final TextEditingController _result;

  @override
  void initState() {
    super.initState();
    _result = TextEditingController(text: widget.investigation.result ?? '');
  }

  @override
  void dispose() {
    _result.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.tile,
        borderRadius: BorderRadius.circular(theme.tileRadius),
        border: Border.all(color: theme.pulse.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Result for ${widget.investigation.name}', style: theme.title(size: 15)),
            const SizedBox(height: SpacingTokens.sm),
            VisitTextInput(
              key: Key('investigation_result_field_${widget.investigation.id}'),
              label: 'Result',
              controller: _result,
              maxLines: 4,
              enabled: !widget.isSubmitting,
            ),
            const SizedBox(height: SpacingTokens.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.secondary,
                  onPressed: widget.isSubmitting ? null : widget.onCancel,
                ),
                const SizedBox(width: SpacingTokens.sm),
                AppButton(
                  key: Key('investigation_result_save_${widget.investigation.id}'),
                  label: widget.isSubmitting ? 'Saving…' : 'Save result',
                  isLoading: widget.isSubmitting,
                  onPressed: widget.isSubmitting || _result.text.trim().isEmpty
                      ? null
                      : () => widget.onSubmit(_result.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
