import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_encounter_persistence.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_opener.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart' show VisitAttachmentDownloadResult;
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_field_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/health_profile_card_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_name_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Visit attachment list with upload, progress, and download (V1-5 US5).
class VisitAttachmentList extends ConsumerStatefulWidget {
  const VisitAttachmentList({
    required this.visitId,
    required this.branchId,
    required this.attachments,
    required this.canUpload,
    required this.onChanged,
    required this.sectionTitle,
    required this.sectionKind,
    this.encounterShell = false,
    this.summaryMode = false,
    this.expandBody = false,
    this.pickAttachment,
    this.promptAttachmentLabel,
    this.fetchDownloadBytes,
    this.openDownloadedAttachment,
    this.deferPersistence = false,
    super.key,
  });

  final String visitId;
  final String branchId;
  final List<VisitAttachmentItem> attachments;
  final bool canUpload;
  final VoidCallback onChanged;
  final String sectionTitle;
  final VisitPanelKind sectionKind;
  final bool encounterShell;
  final bool summaryMode;
  final bool expandBody;
  final bool deferPersistence;

  final Future<VisitAttachmentPickInput?> Function()? pickAttachment;
  final Future<String?> Function(VisitAttachmentPickInput pick)? promptAttachmentLabel;
  final Future<Uint8List> Function(VisitAttachmentDownloadResult download)? fetchDownloadBytes;
  final Future<void> Function(VisitAttachmentItem attachment, String filename, Uint8List bytes)?
  openDownloadedAttachment;

  @override
  ConsumerState<VisitAttachmentList> createState() => _VisitAttachmentListState();
}

class _VisitAttachmentListState extends ConsumerState<VisitAttachmentList> {
  bool _isUploading = false;
  String? _uploadingLabel;
  String? _errorMessage;
  String? _downloadingAttachmentId;
  String? _deletingAttachmentId;

  bool get _hasItems => widget.attachments.isNotEmpty;

  List<Widget>? _shelfActions() {
    if (!widget.canUpload || _isUploading || widget.encounterShell || widget.summaryMode || !_hasItems) return null;

    return [
      AppNotchedCardAction(
        providesOwnBackground: true,
        action: AppButton(
          key: const Key('visit_attachment_upload_button'),
          label: 'Upload file',
          size: AppFieldSize.sm,
          icon: const Icon(Icons.upload_file_outlined, size: 18),
          onPressed: _pickAndUpload,
        ),
      ),
    ];
  }

  Widget? _encounterHeaderTrailing() {
    if (!widget.encounterShell || !widget.canUpload || _isUploading || !_hasItems) return null;

    final theme = context.visitTheme;
    return AppIconButton(
      key: const Key('visit_attachment_upload_button'),
      icon: Icon(Icons.upload_file_outlined, size: HealthProfileCardTokens.addIconSize, color: theme.pulse),
      tooltip: 'Upload file',
      onPressed: _pickAndUpload,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.summaryMode) {
      return _buildSummaryLayout();
    }

    final body = encounterExpandedSectionBody(
      expandBody: widget.expandBody,
      centerWhenEmpty: widget.encounterShell && _shouldCenterEmptyState(),
      child: _buildBody(),
    );

    if (widget.encounterShell) {
      return EncounterFieldCard(
        title: widget.sectionTitle,
        titleIcon: widget.sectionKind.icon,
        expandBody: widget.expandBody,
        headerTrailing: _encounterHeaderTrailing(),
        child: body,
      );
    }

    return VisitSectionCard(
      kind: widget.sectionKind,
      title: widget.sectionTitle,
      headerActions: _shelfActions(),
      child: body,
    );
  }

  Widget _buildSummaryLayout() {
    final theme = context.visitTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.sectionTitle.toUpperCase(), style: theme.eyebrow(size: 10).copyWith(letterSpacing: 1.2)),
          const SizedBox(height: SpacingTokens.xs + 1),
          _buildSummaryBody(),
        ],
      ),
    );
  }

  Widget _buildSummaryBody() {
    if (!_hasItems) {
      return _buildEmptyState();
    }

    final count = widget.attachments.length;
    final useBulletList = count > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errorMessage != null) ...[
          Text(
            _errorMessage!,
            key: const Key('visit_attachment_error'),
            style: context.visitTheme.caption(color: context.visitTheme.danger),
          ),
          const SizedBox(height: SpacingTokens.sm),
        ],
        for (var index = 0; index < count; index++)
          _SummaryAttachmentRow(
            attachment: widget.attachments[index],
            isOpening: _downloadingAttachmentId == widget.attachments[index].id,
            showBullet: useBulletList,
            isLast: index == count - 1,
            onOpen: () => _open(widget.attachments[index]),
          ),
      ],
    );
  }

  bool _shouldCenterEmptyState() {
    return !_hasItems && !_isUploading && _errorMessage == null;
  }

  Widget _buildEmptyState() {
    if (widget.summaryMode) {
      final theme = context.visitTheme;
      return KeyedSubtree(
        key: const Key('visit_attachment_empty'),
        child: Text('—', style: theme.body(color: theme.mutedInk)),
      );
    }

    return VisitEmptyHint(
      key: const Key('visit_attachment_empty'),
      message: 'No attachments yet.',
      icon: Icons.attach_file_outlined,
      actionLabel: widget.canUpload && !_isUploading ? 'Upload file' : null,
      actionIcon: Icons.upload_file_outlined,
      onAction: widget.canUpload && !_isUploading ? _pickAndUpload : null,
      actionKey: widget.canUpload ? const Key('visit_attachment_upload_button') : null,
    );
  }

  Widget _buildBody() {
    if (widget.summaryMode) {
      return _buildSummaryBody();
    }

    if (widget.encounterShell && widget.expandBody && _shouldCenterEmptyState()) {
      return _buildEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                  'Uploading ${_uploadingLabel ?? 'attachment'}…',
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
            style: context.visitTheme.caption(color: context.visitTheme.danger),
          ),
        ],
        if (!_hasItems && !_isUploading) _buildEmptyState(),
        Wrap(
          spacing: SpacingTokens.sm,
          runSpacing: SpacingTokens.sm,
          children: [
            for (final attachment in widget.attachments)
              _AttachmentTile(
                attachment: attachment,
                isOpening: _downloadingAttachmentId == attachment.id,
                isDeleting: _deletingAttachmentId == attachment.id,
                onOpen: () => _open(attachment),
                onDelete: () => _delete(attachment),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickAndUpload() async {
    setState(() => _errorMessage = null);

    final pick = widget.pickAttachment != null ? await widget.pickAttachment!() : await _pickFromPlatform();
    if (pick == null || !mounted) {
      return;
    }

    final label = widget.promptAttachmentLabel != null
        ? await widget.promptAttachmentLabel!(pick)
        : await VisitAttachmentNameDialog.show(context, filename: pick.filename);
    if (label == null || label.trim().isEmpty || !mounted) {
      return;
    }
    final trimmedLabel = label.trim();

    final session = ref.read(authSessionProvider).context;
    final orgId = session?.organizationId?.trim();
    final staffId = session?.staffProfile.staffMemberId.trim();
    if (widget.deferPersistence) {
      if (staffId == null || staffId.isEmpty) {
        setState(() => _errorMessage = 'Staff context is required to stage attachments.');
        return;
      }
      try {
        await visitEncounterPersistence(ref, visitId: widget.visitId, deferPersistence: true).stageAttachment(
          pick: pick,
          label: trimmedLabel,
          uploadedBy: staffId,
          uploadedByName: session?.staffProfile.fullName,
        );
        if (!mounted) return;
        widget.onChanged();
      } catch (error) {
        if (!mounted) return;
        setState(() => _errorMessage = visitMessageForUploadError(error));
      }
      return;
    }

    if (orgId == null || orgId.isEmpty) {
      setState(() => _errorMessage = 'Organization context is required to upload attachments.');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadingLabel = trimmedLabel;
      _errorMessage = null;
    });

    try {
      await visitEncounterPersistence(
        ref,
        visitId: widget.visitId,
        deferPersistence: false,
      ).uploadAndRegisterAttachment(organizationId: orgId, branchId: widget.branchId, pick: pick, label: trimmedLabel);
      if (!mounted) return;
      widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = visitMessageForUploadError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadingLabel = null;
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

  Future<void> _open(VisitAttachmentItem attachment) async {
    if (!attachment.canDownload) {
      return;
    }

    if (widget.deferPersistence && isVisitDraftId(attachment.id)) {
      final bytes = ref
          .read(visitDocumentationProvider(widget.visitId))
          .value
          ?.encounterDraft
          .pendingAttachmentBytes(attachment.id);
      if (bytes == null) return;
      final preferredName = attachment.label?.trim().isNotEmpty == true ? attachment.label : 'attachment';
      await openVisitAttachmentBytes(bytes: bytes, fileType: attachment.fileType, preferredName: preferredName);
      return;
    }

    setState(() {
      _downloadingAttachmentId = attachment.id;
      _errorMessage = null;
    });

    try {
      final service = ref.read(visitAttachmentServiceProvider);
      final download = await service.getVisitAttachmentDownload(attachmentId: attachment.id);
      final bytes = widget.fetchDownloadBytes != null
          ? await widget.fetchDownloadBytes!(download)
          : await service.downloadAttachmentBytes(download);

      if (widget.openDownloadedAttachment != null) {
        await widget.openDownloadedAttachment!(attachment, download.filename, bytes);
      } else {
        final preferredName = attachment.label?.trim().isNotEmpty == true ? attachment.label : download.filename;
        await openVisitAttachmentBytes(bytes: bytes, fileType: attachment.fileType, preferredName: preferredName);
      }
    } on RpcFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = visitMessageForRpc(error));
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = visitMessageForOpenError(error));
    } finally {
      if (mounted) {
        setState(() => _downloadingAttachmentId = null);
      }
    }
  }

  Future<void> _delete(VisitAttachmentItem attachment) async {
    final title = attachment.label?.trim().isNotEmpty == true ? attachment.label! : attachment.fileType.label;
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete attachment?'),
        content: Text('Delete "$title"? This cannot be undone.'),
        actions: [
          AppButton(label: 'Cancel', variant: AppButtonVariant.secondary, onPressed: () => Navigator.pop(ctx, false)),
          AppButton(label: 'Delete', variant: AppButtonVariant.destructive, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (remove != true || !mounted) return;

    setState(() {
      _deletingAttachmentId = attachment.id;
      _errorMessage = null;
    });

    try {
      await visitEncounterPersistence(
        ref,
        visitId: widget.visitId,
        deferPersistence: widget.deferPersistence,
      ).deleteVisitAttachment(attachmentId: attachment.id);
      if (!mounted) return;
      widget.onChanged();
    } on RpcFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = visitMessageForRpc(error));
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => _deletingAttachmentId = null);
      }
    }
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

class _SummaryAttachmentRow extends StatelessWidget {
  const _SummaryAttachmentRow({
    required this.attachment,
    required this.isOpening,
    required this.onOpen,
    this.showBullet = false,
    this.isLast = true,
  });

  final VisitAttachmentItem attachment;
  final bool isOpening;
  final VoidCallback onOpen;
  final bool showBullet;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final title = attachment.label?.trim().isNotEmpty == true ? attachment.label! : attachment.fileType.label;
    final canOpen = attachment.canDownload && !isOpening;
    final textStyle = theme.body(color: attachment.canDownload ? theme.pulse : null);

    final content = GestureDetector(
      onTap: canOpen ? onOpen : null,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: canOpen ? SystemMouseCursors.click : MouseCursor.defer,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isOpening) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: AppCircularProgress(key: Key('visit_attachment_open_progress')),
              ),
              const SizedBox(width: SpacingTokens.xs),
            ],
            Expanded(
              child: Text(title, key: Key('visit_attachment_row_${attachment.id}'), style: textStyle),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : SpacingTokens.xs),
      child: showBullet
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•', style: theme.body(color: theme.mutedInk)),
                const SizedBox(width: SpacingTokens.xs),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.isOpening,
    required this.isDeleting,
    required this.onOpen,
    required this.onDelete,
  });

  final VisitAttachmentItem attachment;
  final bool isOpening;
  final bool isDeleting;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final title = attachment.label?.trim().isNotEmpty == true ? attachment.label! : attachment.fileType.label;
    final meta = _VisitAttachmentListState._formatSize(attachment.sizeBytes);
    final canOpen = attachment.canDownload && !isOpening && !isDeleting;

    return ConstrainedBox(
      key: Key('visit_attachment_row_${attachment.id}'),
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      child: Material(
        color: theme.tile,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(theme.tileRadius),
          side: BorderSide(color: theme.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canOpen ? onOpen : null,
          mouseCursor: canOpen ? SystemMouseCursors.click : MouseCursor.defer,
          child: Padding(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: theme.pulse.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(theme.tileRadius - 1),
                      ),
                      alignment: Alignment.center,
                      child: isOpening
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: AppCircularProgress(key: Key('visit_attachment_open_progress')),
                            )
                          : Icon(
                              _VisitAttachmentListState._iconForType(attachment.fileType),
                              size: 20,
                              color: theme.pulseDeep,
                            ),
                    ),
                    const Spacer(),
                    if (attachment.canDelete)
                      isDeleting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: AppCircularProgress(key: Key('visit_attachment_delete_progress')),
                            )
                          : AppIconButton(
                              key: Key('visit_attachment_delete_${attachment.id}'),
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: isOpening ? null : onDelete,
                            ),
                  ],
                ),
                const SizedBox(height: SpacingTokens.sm),
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.bodyStrong(size: 14)),
                const SizedBox(height: SpacingTokens.xs),
                Text(meta, style: theme.caption(size: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
