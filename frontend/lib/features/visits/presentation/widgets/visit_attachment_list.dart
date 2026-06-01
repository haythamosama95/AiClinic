import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/presentation/visit_rpc_messages.dart';

/// Visit attachment list with upload, progress, and download (V1-5 US5).
class VisitAttachmentList extends ConsumerStatefulWidget {
  const VisitAttachmentList({
    required this.visitId,
    required this.branchId,
    required this.attachments,
    required this.canUpload,
    required this.onChanged,
    this.pickAttachment,
    super.key,
  });

  final String visitId;
  final String branchId;
  final List<VisitAttachmentItem> attachments;
  final bool canUpload;
  final VoidCallback onChanged;

  /// Test hook: bypasses platform file picker.
  final Future<VisitAttachmentPickInput?> Function()? pickAttachment;

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
    final theme = Theme.of(context);
    final dateFormat = DateFormat.yMMMd().add_jm();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Attachments', style: theme.textTheme.titleMedium),
            const Spacer(),
            if (widget.canUpload && !_isUploading)
              TextButton.icon(
                key: const Key('visit_attachment_upload_button'),
                onPressed: _pickAndUpload,
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload'),
              ),
          ],
        ),
        if (_isUploading) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, key: Key('visit_attachment_upload_progress')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Uploading ${_uploadingFilename ?? 'file'}…',
                  key: const Key('visit_attachment_upload_status'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            key: const Key('visit_attachment_error'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        if (widget.attachments.isEmpty && !_isUploading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No attachments yet.',
              key: const Key('visit_attachment_empty'),
              style: theme.textTheme.bodyMedium,
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

          return ListTile(
            key: Key('visit_attachment_row_${attachment.id}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(_iconForType(attachment.fileType)),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: attachment.canDownload
                ? _downloadingAttachmentId == attachment.id
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            key: Key('visit_attachment_download_progress'),
                          ),
                        )
                      : IconButton(
                          key: Key('visit_attachment_download_${attachment.id}'),
                          tooltip: 'Download',
                          icon: const Icon(Icons.download),
                          onPressed: () => _download(attachment.id),
                        )
                : null,
          );
        }),
      ],
    );
  }

  Future<void> _pickAndUpload() async {
    setState(() {
      _errorMessage = null;
    });

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
      await ref
          .read(visitAttachmentServiceProvider)
          .uploadAndRegister(organizationId: orgId, branchId: widget.branchId, visitId: widget.visitId, pick: pick);
      if (!mounted) {
        return;
      }
      widget.onChanged();
    } on VisitAttachmentValidationException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.message);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = visitMessageForRpc(error));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
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
      final download = await ref
          .read(visitAttachmentServiceProvider)
          .getVisitAttachmentDownload(attachmentId: attachmentId);
      final uri = Uri.tryParse(download.signedUrl);
      if (uri == null) {
        throw StateError('Download URL was invalid.');
      }
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        setState(() => _errorMessage = 'Could not open the download link.');
      }
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = visitMessageForRpc(error));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => _downloadingAttachmentId = null);
      }
    }
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static IconData _iconForType(VisitAttachmentFileType type) {
    return switch (type) {
      VisitAttachmentFileType.pdf => Icons.picture_as_pdf,
      VisitAttachmentFileType.docx => Icons.description,
      VisitAttachmentFileType.jpeg || VisitAttachmentFileType.png => Icons.image,
    };
  }
}
