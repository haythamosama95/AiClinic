import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_opener.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Visit attachments via [AppFileDropzone] with staged upload on save (V1-5 US5).
class EncounterAttachmentsPanel extends ConsumerStatefulWidget {
  const EncounterAttachmentsPanel({
    required this.visitId,
    required this.branchId,
    required this.attachments,
    required this.canUpload,
    super.key,
  });

  final String visitId;
  final String branchId;
  final List<VisitAttachmentItem> attachments;
  final bool canUpload;

  @override
  ConsumerState<EncounterAttachmentsPanel> createState() => _EncounterAttachmentsPanelState();
}

class _EncounterAttachmentsPanelState extends ConsumerState<EncounterAttachmentsPanel> {
  String? _downloadingId;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final fileStates = [
      for (final attachment in widget.attachments)
        AppDropzoneFileState(
          file: AppDropzoneFile(
            id: attachment.id,
            name: attachment.label ?? attachment.fileType.label,
            sizeBytes: attachment.sizeBytes,
          ),
          status: AppDropzoneFileStatus.success,
        ),
    ];

    return AppCard(
      padding: AppCardPadding.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionHeader(
            title: 'Attachments',
            description: 'PDF, Word, JPEG, and PNG up to 25 MB',
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.s2),
            AppAlert(variant: AppAlertVariant.danger, title: _errorMessage!),
          ],
          const SizedBox(height: AppSpacing.s3),
          AppFileDropzone(
            fileStates: fileStates,
            disabled: !widget.canUpload,
            allowedExtensions: const ['pdf', 'docx', 'jpg', 'jpeg', 'png'],
            maxFileSizeBytes: VisitAttachmentService.maxBytes,
            acceptedTypesHint: 'PDF, DOCX, JPEG, PNG up to 25MB',
            onFilesSelected: widget.canUpload ? _handleFilesSelected : null,
            onRemove: widget.canUpload ? _handleRemove : null,
          ),
          if (widget.attachments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s3),
            for (final attachment in widget.attachments)
              if (attachment.canDownload)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s2),
                  child: AppButton(
                    label: _downloadingId == attachment.id ? 'Opening…' : 'Open ${attachment.label ?? 'attachment'}',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    leadingIcon: LucideIcons.download,
                    loading: _downloadingId == attachment.id,
                    onPressed: _downloadingId == attachment.id
                        ? null
                        : () => _openAttachment(attachment),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleFilesSelected(List<AppDropzoneFile> files) async {
    final auth = ref.read(authSessionProvider);
    final staff = auth.context?.staffProfile;
    if (staff == null) return;

    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);

    for (final file in files) {
      final validationError = AppFileDropzone.validateFile(
        file,
        allowedExtensions: const ['pdf', 'docx', 'jpg', 'jpeg', 'png'],
        maxFileSizeBytes: VisitAttachmentService.maxBytes,
      );
      if (validationError != null) {
        setState(() => _errorMessage = validationError);
        continue;
      }

      final bytes = await _readBytes(file);
      if (bytes == null) continue;

      final label = await _promptLabel(file.name);
      if (label == null || !mounted) continue;

      notifier.stageAttachment(
        pick: VisitAttachmentPickInput(filename: file.name, bytes: bytes),
        label: label,
        uploadedBy: staff.staffMemberId,
        uploadedByName: staff.fullName,
      );
    }
  }

  Future<Uint8List?> _readBytes(AppDropzoneFile file) async {
    if (file.bytes != null) return file.bytes;
    // Path-based reads are handled by the dropzone on desktop; bytes should be present.
    return null;
  }

  Future<String?> _promptLabel(String filename) async {
    final controller = TextEditingController(text: filename);
    final result = await showAppDialog<String>(
      context,
      size: AppDialogSize.sm,
      semanticLabel: 'Attachment label',
      builder: (dialogContext, close) {
        return AppDialog(
          title: 'Attachment label',
          onClose: () => close(),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppFormField(
                label: 'Label',
                child: AppTextField(controller: controller, hintText: filename),
              ),
              const SizedBox(height: AppSpacing.s4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    onPressed: () => close(),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  AppButton(
                    label: 'Add',
                    size: AppButtonSize.sm,
                    onPressed: () => close(controller.text.trim()),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    final trimmed = result?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _handleRemove(AppDropzoneFile file) {
    ref.read(visitDocumentationProvider(widget.visitId).notifier).stageDeleteAttachment(file.id);
  }

  Future<void> _openAttachment(VisitAttachmentItem attachment) async {
    if (isVisitDraftId(attachment.id)) {
      final bytes = ref
          .read(visitDocumentationProvider(widget.visitId))
          .value
          ?.encounterDraft
          .pendingAttachmentBytes(attachment.id);
      if (bytes == null) return;
      try {
        await openVisitAttachmentBytes(
          bytes: bytes,
          fileType: attachment.fileType,
          preferredName: attachment.label,
        );
      } catch (error) {
        if (!mounted) return;
        setState(() => _errorMessage = visitMessageForOpenError(error));
      }
      return;
    }

    setState(() {
      _downloadingId = attachment.id;
      _errorMessage = null;
    });

    try {
      final service = ref.read(visitAttachmentServiceProvider);
      final download = await service.getVisitAttachmentDownload(attachmentId: attachment.id);
      final bytes = await service.downloadAttachmentBytes(download);
      await openVisitAttachmentBytes(
        bytes: bytes,
        fileType: attachment.fileType,
        preferredName: attachment.label,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = visitMessageForDownloadError(error));
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }
}
