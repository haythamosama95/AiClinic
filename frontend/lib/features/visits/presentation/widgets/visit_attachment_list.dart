import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart' show VisitAttachmentDownloadResult;
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';

/// Visit attachment list with upload, progress, and download (V1-5 US5).
class VisitAttachmentList extends ConsumerStatefulWidget {
  const VisitAttachmentList({
    required this.visitId,
    required this.branchId,
    required this.attachments,
    required this.canUpload,
    required this.onChanged,
    this.pickAttachment,
    this.fetchDownloadBytes,
    this.saveDownloadedAttachment,
    super.key,
  });

  final String visitId;
  final String branchId;
  final List<VisitAttachmentItem> attachments;
  final bool canUpload;
  final VoidCallback onChanged;

  final Future<VisitAttachmentPickInput?> Function()? pickAttachment;
  final Future<Uint8List> Function(VisitAttachmentDownloadResult download)? fetchDownloadBytes;
  final Future<bool> Function(String filename, Uint8List bytes)? saveDownloadedAttachment;

  @override
  ConsumerState<VisitAttachmentList> createState() => _VisitAttachmentListState();
}

class _VisitAttachmentListState extends ConsumerState<VisitAttachmentList> {
  bool _isUploading = false;
  String? _uploadingFilename;
  String? _errorMessage;
  String? _downloadingAttachmentId;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final dateFormat = DateFormat.yMMMd().add_jm();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canUpload && !_isUploading)
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: const Key('visit_attachment_upload_button'),
              label: 'Upload file',
              variant: AppButtonVariant.outline,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              onPressed: _pickAndUpload,
            ),
          ),
        if (_isUploading) ...[
          const SizedBox(height: SpacingTokens.md),
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: AppCircularProgress(key: Key('visit_attachment_upload_progress')),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: Text(
                  'Uploading ${_uploadingFilename ?? 'file'}…',
                  key: const Key('visit_attachment_upload_status'),
                ),
              ),
            ],
          ),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: SpacingTokens.sm),
          Text(
            _errorMessage!,
            key: const Key('visit_attachment_error'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.destructive),
          ),
        ],
        if (widget.attachments.isEmpty && !_isUploading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
            child: Text(
              'No attachments yet.',
              key: const Key('visit_attachment_empty'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
            ),
          ),
        ...widget.attachments.map((attachment) {
          final title = attachment.label?.trim().isNotEmpty == true ? attachment.label! : attachment.fileType.label;
          final subtitle = [
            attachment.fileType.label,
            _formatSize(attachment.sizeBytes),
            if (attachment.uploadedByName?.trim().isNotEmpty == true) attachment.uploadedByName!,
            dateFormat.format(attachment.createdAt.toLocal()),
          ].join(' · ');

          return Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.sm),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.muted.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(context.shapeTokens.md),
                border: Border.all(color: colors.border),
              ),
              child: ListTile(
                key: Key('visit_attachment_row_${attachment.id}'),
                contentPadding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
                leading: Icon(_iconForType(attachment.fileType), color: colors.primary),
                title: Text(title),
                subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                trailing: attachment.canDownload
                    ? _downloadingAttachmentId == attachment.id
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: AppCircularProgress(key: Key('visit_attachment_download_progress')),
                          )
                        : AppIconButton(
                            key: Key('visit_attachment_download_${attachment.id}'),
                            tooltip: 'Download',
                            icon: const Icon(Icons.download_outlined, size: 18),
                            onPressed: () => _download(attachment.id),
                          )
                    : null,
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _pickAndUpload() async {
    setState(() => _errorMessage = null);

    final pick = widget.pickAttachment != null ? await widget.pickAttachment!() : await _pickFromPlatform();
    if (pick == null || !mounted) {
      return;
    }

    final orgId = ref.read(authSessionProvider).context?.organizationId?.trim();
    if (orgId == null || orgId.isEmpty) {
      setState(() => _errorMessage = 'Organization context is required to upload attachments.');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadingFilename = pick.filename;
      _errorMessage = null;
    });

    try {
      await ref.read(visitAttachmentServiceProvider).uploadAndRegister(
            organizationId: orgId,
            branchId: widget.branchId,
            visitId: widget.visitId,
            pick: pick,
          );
      if (!mounted) return;
      widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = visitMessageForUploadError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadingFilename = null;
        });
      }
    }
  }

  Future<VisitAttachmentPickInput?> _pickFromPlatform() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'jpg', 'jpeg', 'png'],
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final file = result.files.single;
    final bytes = file.bytes;
    final name = file.name.trim();
    if (bytes == null || name.isEmpty) {
      return null;
    }
    return VisitAttachmentPickInput(filename: name, bytes: bytes);
  }

  Future<void> _download(String attachmentId) async {
    setState(() {
      _downloadingAttachmentId = attachmentId;
      _errorMessage = null;
    });

    try {
      final service = ref.read(visitAttachmentServiceProvider);
      final download = await service.getVisitAttachmentDownload(attachmentId: attachmentId);
      final bytes = widget.fetchDownloadBytes != null
          ? await widget.fetchDownloadBytes!(download)
          : await service.downloadAttachmentBytes(download);
      final saved = widget.saveDownloadedAttachment != null
          ? await widget.saveDownloadedAttachment!(download.filename, bytes)
          : await _promptSaveDownload(download.filename, bytes);
      if (!saved && mounted) {
        return;
      }
    } on RpcFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = visitMessageForRpc(error));
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = visitMessageForDownloadError(error));
    } finally {
      if (mounted) {
        setState(() => _downloadingAttachmentId = null);
      }
    }
  }

  Future<bool> _promptSaveDownload(String filename, Uint8List bytes) async {
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Save attachment', fileName: filename, bytes: bytes);
    return path != null;
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static IconData _iconForType(VisitAttachmentFileType type) {
    return switch (type) {
      VisitAttachmentFileType.pdf => Icons.picture_as_pdf_outlined,
      VisitAttachmentFileType.docx => Icons.description_outlined,
      VisitAttachmentFileType.jpeg || VisitAttachmentFileType.png => Icons.image_outlined,
    };
  }
}
