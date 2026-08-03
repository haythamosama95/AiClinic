import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';

typedef VisitAttachmentStageHandler =
    void Function({
      required VisitAttachmentPickInput pick,
      required String label,
      required String uploadedBy,
      String? uploadedByName,
    });

typedef VisitAttachmentDeleteHandler = void Function(String attachmentId);

/// Visit document attachments for the treatment step.
class VisitAttachmentsEditor extends StatelessWidget {
  const VisitAttachmentsEditor({
    required this.attachments,
    required this.uploadedBy,
    required this.uploadedByName,
    required this.onStage,
    required this.onDelete,
    this.canEdit = true,
    super.key,
  });

  final List<VisitAttachmentItem> attachments;
  final String uploadedBy;
  final String? uploadedByName;
  final VisitAttachmentStageHandler onStage;
  final VisitAttachmentDeleteHandler onDelete;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final maxSizeMb = VisitAttachmentService.maxBytes ~/ (1024 * 1024);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (attachments.isNotEmpty) ...[
          Column(
            children: [
              for (var i = 0; i < attachments.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.space2),
                _AttachmentRow(
                  attachment: attachments[i],
                  canDelete: canEdit && attachments[i].canDelete,
                  onDelete: () => onDelete(attachments[i].id),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.space3),
        ],
        AppFileDropzone(
          id: 'visit-attachments',
          accept: '.pdf,.jpg,.jpeg,.png,.docx',
          disabled: !canEdit,
          maxSizeMb: maxSizeMb,
          onUpload: canEdit
              ? (file) async {
                  final bytes = file.bytes;
                  if (bytes == null) {
                    throw const VisitAttachmentValidationException(
                      'Could not read the selected file.',
                      errorCode: 'INVALID_INPUT',
                    );
                  }
                  final pick = VisitAttachmentPickInput(filename: file.name, bytes: bytes);
                  VisitAttachmentService.validatePick(pick);
                  onStage(pick: pick, label: file.name, uploadedBy: uploadedBy, uploadedByName: uploadedByName);
                }
              : null,
        ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          'PDF, DOCX, JPG, PNG up to $maxSizeMb MB each.',
          style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.attachment, required this.canDelete, required this.onDelete});

  final VisitAttachmentItem attachment;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label = attachment.label ?? attachment.id;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
        child: Row(
          children: [
            Icon(_iconFor(attachment.fileType), size: 20, color: colors.iconMuted),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.body(context).copyWith(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _formatSize(attachment.sizeBytes),
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: colors.textTertiary, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ),
            if (canDelete)
              Semantics(
                button: true,
                label: 'Remove $label',
                child: IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.close, size: 16, color: colors.iconMuted),
                  padding: const EdgeInsets.all(AppSpacing.space1),
                  constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(VisitAttachmentFileType fileType) {
    return switch (fileType) {
      VisitAttachmentFileType.pdf => Icons.picture_as_pdf_outlined,
      VisitAttachmentFileType.docx => Icons.description_outlined,
      VisitAttachmentFileType.jpeg || VisitAttachmentFileType.png => Icons.image_outlined,
    };
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
