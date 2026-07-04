import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Presentation-level status for a file in [AppFileDropzone].
enum AppDropzoneFileStatus {
  queued,
  uploading,
  success,
  error,
}

/// A file selected through [AppFileDropzone].
class AppDropzoneFile {
  const AppDropzoneFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    this.path,
    this.bytes,
  });

  final String id;
  final String name;
  final int sizeBytes;

  /// Local filesystem path when available (desktop browse/drop).
  final String? path;

  /// In-memory bytes when no path is available.
  final Uint8List? bytes;
}

/// Per-file display state driven by the parent (upload progress, outcome).
class AppDropzoneFileState {
  const AppDropzoneFileState({
    required this.file,
    required this.status,
    this.progress,
    this.errorMessage,
  });

  final AppDropzoneFile file;
  final AppDropzoneFileStatus status;

  /// Upload progress from 0–100 when [status] is [AppDropzoneFileStatus.uploading].
  final double? progress;
  final String? errorMessage;
}

/// Drag-and-drop / browse file picker with per-file progress rows.
///
/// Selection is surfaced through [onFilesSelected]; upload lifecycle is owned by
/// the parent via [fileStates]. No network or storage I/O is performed here.
class AppFileDropzone extends StatefulWidget {
  const AppFileDropzone({
    required this.fileStates,
    this.onFilesSelected,
    this.onRemove,
    this.allowedExtensions = const ['pdf', 'jpg', 'jpeg', 'png'],
    this.allowMultiple = true,
    this.maxFileSizeBytes = 10 * 1024 * 1024,
    this.disabled = false,
    this.invalid = false,
    this.dropPrompt = 'Drop files here',
    this.browseLabel = 'Browse files',
    this.acceptedTypesHint,
    super.key,
  });

  /// Inbound per-file status and progress from the parent.
  final List<AppDropzoneFileState> fileStates;

  /// Called when the user drops or browses new files (presentation validation
  /// available via [validateFile]).
  final ValueChanged<List<AppDropzoneFile>>? onFilesSelected;

  /// Called when the user removes a file row.
  final ValueChanged<AppDropzoneFile>? onRemove;

  final List<String>? allowedExtensions;
  final bool allowMultiple;
  final int? maxFileSizeBytes;
  final bool disabled;
  final bool invalid;
  final String dropPrompt;
  final String browseLabel;

  /// Defaults to an uppercase extension list + max size derived from [maxFileSizeBytes].
  final String? acceptedTypesHint;

  /// Presentation-level validation for a selected file.
  static String? validateFile(
    AppDropzoneFile file, {
    List<String>? allowedExtensions,
    int? maxFileSizeBytes,
  }) {
    if (maxFileSizeBytes != null && file.sizeBytes > maxFileSizeBytes) {
      final limitMb = (maxFileSizeBytes / (1024 * 1024)).round();
      return 'File exceeds $limitMb MB limit';
    }
    if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
      final normalized = allowedExtensions
          .map((ext) => ext.toLowerCase().replaceAll('.', ''))
          .toSet();
      final dot = file.name.lastIndexOf('.');
      if (dot == -1 || dot == file.name.length - 1) {
        return 'File type not allowed';
      }
      final ext = file.name.substring(dot + 1).toLowerCase();
      if (!normalized.contains(ext)) {
        return 'File type not allowed';
      }
    }
    return null;
  }

  @override
  State<AppFileDropzone> createState() => _AppFileDropzoneState();
}

class _AppFileDropzoneState extends State<AppFileDropzone> {
  static int _idCounter = 0;

  bool _dragOver = false;

  bool get _isInteractive =>
      !widget.disabled && widget.onFilesSelected != null;

  String _generateId() {
    _idCounter += 1;
    return 'dropzone_$_idCounter';
  }

  String _resolvedAcceptedTypesHint() {
    if (widget.acceptedTypesHint != null) {
      return widget.acceptedTypesHint!;
    }
    final extensions = widget.allowedExtensions;
    final label = extensions == null || extensions.isEmpty
        ? 'Files'
        : extensions
              .map((ext) => ext.replaceAll('.', '').toUpperCase())
              .join(', ');
    if (widget.maxFileSizeBytes == null) return label;
    final limitMb = (widget.maxFileSizeBytes! / (1024 * 1024)).round();
    return '$label up to ${limitMb}MB';
  }

  Future<void> _browseFiles() async {
    if (!_isInteractive) return;

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: widget.allowMultiple,
      type: widget.allowedExtensions == null || widget.allowedExtensions!.isEmpty
          ? FileType.any
          : FileType.custom,
      allowedExtensions: widget.allowedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final selected = result.files
        .map(_fileFromPlatform)
        .where((file) => file.name.isNotEmpty)
        .toList();
    _emitSelected(selected);
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    if (!_isInteractive) return;
    setState(() => _dragOver = false);

    final selected = <AppDropzoneFile>[];
    for (final item in details.files) {
      if (item is DropItemDirectory) continue;
      selected.add(await _fileFromDropItem(item));
    }
    _emitSelected(selected);
  }

  void _emitSelected(List<AppDropzoneFile> files) {
    if (files.isEmpty) return;
    final next = widget.allowMultiple ? files : [files.first];
    widget.onFilesSelected?.call(next);
  }

  AppDropzoneFile _fileFromPlatform(PlatformFile file) {
    return AppDropzoneFile(
      id: _generateId(),
      name: file.name,
      sizeBytes: file.size,
      path: file.path,
      bytes: file.bytes,
    );
  }

  Future<AppDropzoneFile> _fileFromDropItem(DropItem item) async {
    final size = await item.length();
    final path = item.path;
    Uint8List? bytes;
    if (path.isEmpty) {
      bytes = await item.readAsBytes();
    }
    return AppDropzoneFile(
      id: _generateId(),
      name: item.name,
      sizeBytes: size,
      path: path.isNotEmpty ? path : null,
      bytes: bytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final reduced = AppMotion.reduced(context);
    final transitionDuration =
        reduced ? AppDurations.instant : AppDurations.base;

    final borderColor = widget.invalid
        ? colors.statusDangerBorder
        : _dragOver
        ? colors.borderFocus
        : colors.borderDefault;
    final backgroundColor = _dragOver
        ? colors.surfaceSelected
        : colors.surfaceSunken;
    final backgroundTint = _dragOver
        ? colors.actionPrimary.withValues(alpha: 0.06)
        : null;

    final dropArea = AnimatedContainer(
      duration: transitionDuration,
      curve: AppEasings.standard,
      decoration: BoxDecoration(
        color: backgroundTint != null
            ? Color.alphaBlend(backgroundTint, backgroundColor)
            : backgroundColor,
        borderRadius: AppRadii.lgAll,
      ),
      padding: const EdgeInsetsDirectional.all(AppSpacing.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            icon: LucideIcons.upload,
            size: AppIconSize.xl,
            color: colors.iconMuted,
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            widget.dropPrompt,
            style: typography.bodyStrong.copyWith(color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s1),
          Text(
            _resolvedAcceptedTypesHint(),
            style: typography.caption.copyWith(color: colors.textTertiary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s3),
          AppButton(
            label: widget.browseLabel,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.md,
            disabled: widget.disabled,
            onPressed: _isInteractive ? _browseFiles : null,
          ),
        ],
      ),
    );

    final framedDropArea = CustomPaint(
      foregroundPainter: _DashedRoundedRectPainter(
        color: borderColor,
        strokeWidth: AppSpacing.sPx * 2,
        radius: AppRadii.lg,
        dashLength: AppSpacing.s1 + AppSpacing.sPx * 2,
        gapLength: AppSpacing.s1,
      ),
      child: dropArea,
    );

    return Opacity(
      opacity: widget.disabled ? 0.5 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropTarget(
            enable: _isInteractive,
            onDragEntered: (_) => setState(() => _dragOver = true),
            onDragExited: (_) => setState(() => _dragOver = false),
            onDragDone: _handleDrop,
            child: Semantics(
              button: true,
              enabled: _isInteractive,
              label: widget.dropPrompt,
              onTap: _isInteractive ? _browseFiles : null,
              child: AppPressable.builder(
                enabled: _isInteractive,
                onTap: _browseFiles,
                borderRadius: AppRadii.lgAll,
                builder: (context, states, _) {
                  final hovered = states.contains(WidgetState.hovered);
                  return AnimatedContainer(
                    duration: transitionDuration,
                    curve: AppEasings.standard,
                    decoration: BoxDecoration(
                      borderRadius: AppRadii.lgAll,
                      color: hovered && !_dragOver
                          ? colors.surfaceHover.withValues(alpha: 0.35)
                          : Colors.transparent,
                    ),
                    child: framedDropArea,
                  );
                },
              ),
            ),
          ),
          if (widget.fileStates.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s3),
            Semantics(
              container: true,
              label: 'Uploaded files',
              child: AppStagger(
                children: [
                  for (final state in widget.fileStates)
                    _AppDropzoneFileRow(
                      key: ValueKey(state.file.id),
                      state: state,
                      onRemove: widget.onRemove,
                      disabled: widget.disabled,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppDropzoneFileRow extends StatelessWidget {
  const _AppDropzoneFileRow({
    required this.state,
    required this.onRemove,
    required this.disabled,
    super.key,
  });

  final AppDropzoneFileState state;
  final ValueChanged<AppDropzoneFile>? onRemove;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final file = state.file;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          borderRadius: AppRadii.mdAll,
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s2,
          ),
          child: Row(
            children: [
              AppIcon(
                icon: LucideIcons.fileText,
                size: AppIconSize.md,
                color: colors.iconMuted,
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: typography.body.copyWith(color: colors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _formatSize(file.sizeBytes),
                      style: typography
                          .tabular(typography.caption)
                          .copyWith(color: colors.textTertiary),
                    ),
                    if (state.status == AppDropzoneFileStatus.uploading &&
                        state.progress != null) ...[
                      const SizedBox(height: AppSpacing.s1),
                      AppProgress(
                        value: state.progress!,
                        size: AppProgressSize.sm,
                      ),
                    ],
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.s0_5),
                      Text(
                        state.errorMessage!,
                        style: typography.caption.copyWith(
                          color: colors.statusDangerFg,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              _StatusIndicator(status: state.status),
              AppIconButton(
                icon: LucideIcons.x,
                semanticLabel: 'Remove ${file.name}',
                variant: AppIconButtonVariant.ghost,
                size: AppIconButtonSize.sm,
                disabled: disabled,
                onPressed: disabled || onRemove == null
                    ? null
                    : () => onRemove!(file),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status});

  final AppDropzoneFileStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return switch (status) {
      AppDropzoneFileStatus.uploading => const AppSpinner(size: AppSpinnerSize.sm),
      AppDropzoneFileStatus.success => AppIcon(
        icon: LucideIcons.checkCircle2,
        size: AppIconSize.md,
        color: colors.statusSuccessFg,
        semanticLabel: 'Upload complete',
      ),
      AppDropzoneFileStatus.error => AppIcon(
        icon: LucideIcons.alertCircle,
        size: AppIconSize.md,
        color: colors.statusDangerFg,
        semanticLabel: 'Upload failed',
      ),
      AppDropzoneFileStatus.queued => SizedBox(
        width: AppIconSize.md.value,
        height: AppIconSize.md.value,
      ),
    };
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _DashedRoundedRectPainter extends CustomPainter {
  _DashedRoundedRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dashLength,
    required this.gapLength,
  });

  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final inset = strokeWidth / 2;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rect);

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius;
  }
}
