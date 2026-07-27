import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_record_card.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/domain/patient_visit_document.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/presentation/utils/visit_presentation_formatting.dart';

/// Document record card for the patient detail documents tab (web `DocumentCard`).
class PatientVisitDocumentCard extends ConsumerStatefulWidget {
  const PatientVisitDocumentCard({required this.document, super.key});

  final PatientVisitDocument document;

  @override
  ConsumerState<PatientVisitDocumentCard> createState() => _PatientVisitDocumentCardState();
}

class _PatientVisitDocumentCardState extends ConsumerState<PatientVisitDocumentCard> {
  var _downloading = false;

  Future<void> _downloadFile() async {
    if (_downloading) {
      return;
    }

    final attachment = widget.document.attachment;
    setState(() => _downloading = true);

    try {
      await ref
          .read(visitAttachmentServiceProvider)
          .downloadAndOpen(attachmentId: attachment.id, fileType: attachment.fileType, preferredName: attachment.label);
    } catch (error) {
      if (mounted) {
        appToast(context, AppToastInput(message: visitMessageForOpenError(error), variant: AppToastVariant.danger));
      }
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final attachment = widget.document.attachment;
    final fileName = attachment.label ?? attachment.id;

    return PatientRecordCard(
      useNeutralGradient: true,
      leading: _FileTypeColumn(fileType: attachment.fileType, sizeBytes: attachment.sizeBytes),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.patientFile, style: AppTypography.overline(context).copyWith(color: colors.textTertiary)),
                const SizedBox(height: AppSpacing.space1),
                Text(
                  fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.space4),
                _LinkedVisitCitation(visitDate: widget.document.visitDate),
              ],
            ),
          ),
          if (attachment.canDownload)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.borderSubtle.withValues(alpha: 0.8))),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: AppSpacing.space3),
                child: SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.md,
                    loading: _downloading,
                    leadingIcon: const Icon(Icons.download_outlined, size: 16),
                    onPressed: _downloading ? null : _downloadFile,
                    child: Text(l10n.downloadFile),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FileTypeColumn extends StatelessWidget {
  const _FileTypeColumn({required this.fileType, required this.sizeBytes});

  final VisitAttachmentFileType fileType;
  final int sizeBytes;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          fileType.label,
          style: AppTypography.mono(context).copyWith(
            fontSize: 18,
            height: 1,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.06 * 18,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          VisitPresentationFormatting.formatFileSize(sizeBytes),
          style: AppTypography.caption(
            context,
          ).copyWith(color: colors.textTertiary, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}

/// Chart-margin citation — one date read, teal spine ties to visit records.
class _LinkedVisitCitation extends StatelessWidget {
  const _LinkedVisitCitation({required this.visitDate});

  final DateTime visitDate;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final dateLine = DateFormat('EEEE, d MMMM y', locale).format(visitDate);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.borderSubtle.withValues(alpha: 0.75)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.space3, AppSpacing.space3, AppSpacing.space4, AppSpacing.space3),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceSelected,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const SizedBox(width: 3),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.linkedVisit, style: AppTypography.overline(context).copyWith(color: colors.textTertiary)),
                    const SizedBox(height: AppSpacing.space1),
                    Text(
                      dateLine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
