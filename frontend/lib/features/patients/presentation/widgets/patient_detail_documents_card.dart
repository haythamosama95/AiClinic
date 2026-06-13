import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/domain/patient_visit_document.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_history_provider.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';

/// Documents pulled from the patient's past visits.
class PatientDetailDocumentsCard extends ConsumerWidget {
  const PatientDetailDocumentsCard({required this.patientId, super.key});

  final String patientId;

  static final _visitDateFormat = DateFormat('d MMM \'yy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documentsAsync = ref.watch(patientVisitDocumentsProvider(patientId));

    return LayoutBuilder(
      builder: (context, constraints) {
        final fillHeight = constraints.hasBoundedHeight;

        return SizedBox(
          width: double.infinity,
          height: fillHeight ? constraints.maxHeight : null,
          child: DecoratedBox(
            decoration: _cardDecoration(context),
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  Text(
                    'Documents',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: fillHeight ? SpacingTokens.sm : SpacingTokens.lg),
                  if (fillHeight)
                    Expanded(
                      child: documentsAsync.when(
                        loading: () => const Center(child: AppCircularProgress()),
                        error: (_, _) => _DocumentsErrorState(
                          onRetry: () => ref.invalidate(patientVisitDocumentsProvider(patientId)),
                        ),
                        data: (documents) {
                          if (documents.isEmpty) {
                            return const Center(child: _DocumentsEmptyState());
                          }

                          return SingleChildScrollView(
                            child: _DocumentsList(documents: documents, visitDateFormat: _visitDateFormat),
                          );
                        },
                      ),
                    )
                  else
                    documentsAsync.when(
                      loading: () => const Center(
                        child: Padding(padding: EdgeInsets.all(SpacingTokens.lg), child: AppCircularProgress()),
                      ),
                      error: (_, _) =>
                          _DocumentsErrorState(onRetry: () => ref.invalidate(patientVisitDocumentsProvider(patientId))),
                      data: (documents) => _DocumentsList(documents: documents, visitDateFormat: _visitDateFormat),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static BoxDecoration _cardDecoration(BuildContext context) {
    final colors = context.semanticColors;
    return BoxDecoration(
      color: colors.card,
      borderRadius: BorderRadius.circular(context.shapeTokens.lg),
      border: Border.all(color: colors.border),
    );
  }
}

class _DocumentsList extends StatelessWidget {
  const _DocumentsList({required this.documents, required this.visitDateFormat});

  final List<PatientVisitDocument> documents;
  final DateFormat visitDateFormat;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return const _DocumentsEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < documents.length; index++) ...[
          if (index > 0) const SizedBox(height: SpacingTokens.sm),
          _DocumentRow(document: documents[index], visitDateFormat: visitDateFormat),
        ],
      ],
    );
  }
}

class _DocumentRow extends ConsumerStatefulWidget {
  const _DocumentRow({required this.document, required this.visitDateFormat});

  final PatientVisitDocument document;
  final DateFormat visitDateFormat;

  @override
  ConsumerState<_DocumentRow> createState() => _DocumentRowState();
}

class _DocumentRowState extends ConsumerState<_DocumentRow> {
  var _isDownloading = false;

  Future<void> _download() async {
    if (_isDownloading || !widget.document.attachment.canDownload) {
      return;
    }

    setState(() => _isDownloading = true);
    try {
      final service = ref.read(visitAttachmentServiceProvider);
      final download = await service.getVisitAttachmentDownload(attachmentId: widget.document.attachment.id);
      await service.downloadAttachmentBytes(download);
      if (mounted) {
        AppToast.success(context, message: 'Download started.');
      }
    } catch (_) {
      if (mounted) {
        AppToast.error(context, message: 'Unable to download document.');
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final attachment = widget.document.attachment;
    final label = attachment.label?.trim();
    final displayName = label != null && label.isNotEmpty ? label : attachment.fileType.label;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(context.shapeTokens.md),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_iconForFileType(attachment.fileType), size: 18, color: colors.primary),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: SpacingTokens.xs),
                  Text(
                    widget.visitDateFormat.format(widget.document.visitDate),
                    style: theme.textTheme.labelSmall?.copyWith(color: colors.mutedForeground),
                  ),
                  Text(
                    _formatFileSize(attachment.sizeBytes),
                    style: theme.textTheme.labelSmall?.copyWith(color: colors.mutedForeground),
                  ),
                ],
              ),
            ),
            if (attachment.canDownload)
              AppIconButton(
                icon: _isDownloading
                    ? const SizedBox(width: 16, height: 16, child: AppCircularProgress())
                    : const Icon(Icons.download_outlined, size: 18),
                tooltip: 'Download',
                onPressed: _isDownloading ? null : _download,
              ),
          ],
        ),
      ),
    );
  }

  static IconData _iconForFileType(VisitAttachmentFileType fileType) {
    return switch (fileType) {
      VisitAttachmentFileType.jpeg || VisitAttachmentFileType.png => Icons.image_outlined,
      VisitAttachmentFileType.docx => Icons.article_outlined,
      VisitAttachmentFileType.pdf => Icons.picture_as_pdf_outlined,
    };
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _DocumentsEmptyState extends StatelessWidget {
  const _DocumentsEmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.folder_open_outlined, size: 28, color: colors.mutedForeground),
        const SizedBox(height: SpacingTokens.sm),
        Text('No documents from visits.', style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground)),
      ],
    );
  }
}

class _DocumentsErrorState extends StatelessWidget {
  const _DocumentsErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Unable to load documents.', style: theme.textTheme.bodySmall?.copyWith(color: colors.destructive)),
        const SizedBox(height: SpacingTokens.sm),
        AppButton(label: 'Retry', expand: false, variant: AppButtonVariant.outline, onPressed: onRetry),
      ],
    );
  }
}
