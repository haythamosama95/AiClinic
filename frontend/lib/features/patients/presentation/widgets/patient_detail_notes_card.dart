import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';

/// Editable patient notes panel for the detail page.
class PatientDetailNotesCard extends ConsumerStatefulWidget {
  const PatientDetailNotesCard({required this.detail, super.key});

  final PatientDetail detail;

  @override
  ConsumerState<PatientDetailNotesCard> createState() => _PatientDetailNotesCardState();
}

class _PatientDetailNotesCardState extends ConsumerState<PatientDetailNotesCard> {
  late final TextEditingController _controller;
  var _isSaving = false;
  var _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.detail.notes ?? '');
  }

  @override
  void didUpdateWidget(covariant PatientDetailNotesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.id != widget.detail.id) {
      _controller.text = widget.detail.notes ?? '';
      _dirty = false;
      return;
    }
    if (!_dirty && oldWidget.detail.notes != widget.detail.notes) {
      _controller.text = widget.detail.notes ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canEdit => AuthRouteGuard.canAccessPatientEdit(ref.read(authSessionProvider));

  Future<void> _saveNotes() async {
    if (_isSaving || !_canEdit) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final notes = _controller.text.trim();
      await ref.read(updatePatientUseCaseProvider)(
        UpdatePatientInput(
          patientId: widget.detail.id,
          fullName: widget.detail.fullName,
          expectedUpdatedAt: widget.detail.updatedAt,
          notes: notes.isEmpty ? null : notes,
        ),
      );
      if (!mounted) {
        return;
      }
      ref.invalidate(patientDetailProvider(widget.detail.id));
      setState(() => _dirty = false);
      AppToast.success(context, message: 'Notes saved.');
    } catch (error) {
      if (mounted) {
        AppToast.error(context, message: 'Unable to save notes. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final fillHeight = constraints.hasBoundedHeight;

        return SizedBox(
          width: double.infinity,
          height: fillHeight ? constraints.maxHeight : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(context.shapeTokens.lg),
              border: Border.all(color: colors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.lg),
              child: _buildContent(context, theme, colors, fillHeight),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, ThemeData theme, SemanticColors colors, bool fillHeight) {
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text('Notes', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        if (widget.detail.updatedAt != widget.detail.createdAt) ...[
          Flexible(
            child: Text(
              'Updated ${PatientPresentationFormatting.dateTime.format(widget.detail.updatedAt)}',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.mutedForeground),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: SpacingTokens.sm),
        ],
        if (_canEdit)
          AppButton(
            label: 'Save note',
            variant: AppButtonVariant.ghost,
            expand: false,
            isLoading: _isSaving,
            onPressed: _dirty && !_isSaving ? _saveNotes : null,
          ),
      ],
    );

    final notesInput = AppTextInput(
      controller: _controller,
      hintText: _canEdit ? 'Add clinical or reception notes…' : 'No notes recorded.',
      minLines: fillHeight ? null : 1,
      maxLines: fillHeight ? null : 6,
      expands: fillHeight,
      fillColor: colors.muted,
      textAlignVertical: TextAlignVertical.top,
      enabled: _canEdit && !_isSaving,
      onChanged: (_) => setState(() => _dirty = true),
    );

    final createdByFooter = widget.detail.createdByDisplay == null
        ? null
        : Row(
            children: [
              Icon(Icons.person_outline, size: 12, color: colors.mutedForeground),
              const SizedBox(width: SpacingTokens.xs),
              Expanded(
                child: Text(
                  'Created by ${PatientPresentationFormatting.orDash(widget.detail.createdByDisplay)}',
                  style: theme.textTheme.labelSmall?.copyWith(color: colors.mutedForeground, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          );

    if (!fillHeight) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: SpacingTokens.md),
          notesInput,
          if (createdByFooter != null) ...[const SizedBox(height: SpacingTokens.md), createdByFooter],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: SpacingTokens.sm),
        Expanded(
          child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 0), child: notesInput),
        ),
        if (createdByFooter != null) ...[const SizedBox(height: SpacingTokens.sm), createdByFooter],
      ],
    );
  }
}
