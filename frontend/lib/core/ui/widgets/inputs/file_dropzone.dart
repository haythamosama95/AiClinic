import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/spinner.dart';

enum AppFileItemStatus { uploading, success, error }

/// File entry displayed in [AppFileDropzone].
class AppFileItem {
  const AppFileItem({
    required this.id,
    required this.name,
    required this.size,
    required this.status,
    this.progress,
    this.error,
  });

  final String id;
  final String name;
  final int size;
  final AppFileItemStatus status;
  final double? progress;
  final String? error;

  AppFileItem copyWith({
    AppFileItemStatus? status,
    double? progress,
    String? error,
  }) {
    return AppFileItem(
      id: id,
      name: name,
      size: size,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
    );
  }
}

/// Drag-and-drop / browse file upload zone (presentation only).
class AppFileDropzone extends StatefulWidget {
  const AppFileDropzone({
    super.key,
    this.id,
    this.accept,
    this.multiple = true,
    this.disabled = false,
    this.invalid = false,
    this.files,
    this.maxSizeMb = 10,
    this.onFilesChange,
    this.onUpload,
  });

  final String? id;
  final List<String>? accept;
  final bool multiple;
  final bool disabled;
  final bool invalid;
  final List<AppFileItem>? files;
  final int maxSizeMb;
  final ValueChanged<List<AppFileItem>>? onFilesChange;
  final Future<void> Function(PlatformFile file)? onUpload;

  @override
  State<AppFileDropzone> createState() => _AppFileDropzoneState();
}

class _AppFileDropzoneState extends State<AppFileDropzone> {
  bool _dragOver = false;
  List<AppFileItem> _internal = [];

  List<AppFileItem> get _files => widget.files ?? _internal;

  void _setFiles(List<AppFileItem> next) {
    if (widget.files == null) setState(() => _internal = next);
    widget.onFilesChange?.call(next);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _processFiles(List<PlatformFile> incoming) async {
    var files = List<AppFileItem>.from(_files);

    for (final file in incoming) {
      if (file.size > widget.maxSizeMb * 1024 * 1024) {
        files = [
          ...files,
          AppFileItem(
            id: _newId(),
            name: file.name,
            size: file.size,
            status: AppFileItemStatus.error,
            error: 'File exceeds ${widget.maxSizeMb} MB limit',
          ),
        ];
        _setFiles(files);
        continue;
      }

      final item = AppFileItem(
        id: _newId(),
        name: file.name,
        size: file.size,
        status: AppFileItemStatus.uploading,
        progress: 0,
      );
      files = [...files, item];
      _setFiles(files);

      if (widget.onUpload != null) {
        try {
          for (var p = 20.0; p <= 100; p += 20) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            files = files
                .map((f) => f.id == item.id ? f.copyWith(progress: p) : f)
                .toList();
            _setFiles(files);
          }
          await widget.onUpload!(file);
          files = files
              .map(
                (f) => f.id == item.id
                    ? f.copyWith(
                        status: AppFileItemStatus.success,
                        progress: 100,
                      )
                    : f,
              )
              .toList();
        } catch (_) {
          files = files
              .map(
                (f) => f.id == item.id
                    ? f.copyWith(
                        status: AppFileItemStatus.error,
                        error: 'Upload failed. Try again.',
                      )
                    : f,
              )
              .toList();
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        files = files
            .map(
              (f) => f.id == item.id
                  ? f.copyWith(status: AppFileItemStatus.success, progress: 100)
                  : f,
            )
            .toList();
      }
      _setFiles(files);
    }
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  Future<void> _browse() async {
    if (widget.disabled) return;
    final result = await FilePicker.platform.pickFiles(
      type: widget.accept != null ? FileType.custom : FileType.any,
      allowedExtensions: widget.accept,
      allowMultiple: widget.multiple,
      withData: false,
    );
    if (result != null) await _processFiles(result.files);
  }

  void _remove(String id) {
    _setFiles(_files.where((f) => f.id != id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final reducedMotion = AppMotion.isReducedMotion(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          enabled: !widget.disabled,
          identifier: widget.id,
          child: Focus(
            onKeyEvent: (_, event) {
              if (widget.disabled) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space) {
                _browse();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: MouseRegion(
              onEnter: (_) {
                if (!widget.disabled) setState(() => _dragOver = true);
              },
              onExit: (_) => setState(() => _dragOver = false),
              child: GestureDetector(
                onTap: widget.disabled ? null : _browse,
                child: AnimatedContainer(
                  duration: reducedMotion ? Duration.zero : AppDurations.fast,
                  padding: const EdgeInsets.all(AppSpacing.s8),
                  decoration: BoxDecoration(
                    color: _dragOver
                        ? colors.surfaceSelected
                        : colors.surfaceDefault,
                    borderRadius: AppRadius.lgAll,
                    border: Border.all(
                      color: widget.invalid
                          ? colors.statusDangerBorder
                          : _dragOver
                          ? colors.borderFocus
                          : colors.borderDefault,
                      width: 2,
                      strokeAlign: BorderSide.strokeAlignInside,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.upload_file,
                        size: 32,
                        color: colors.iconMuted,
                      ),
                      const SizedBox(height: AppSpacing.s3),
                      Text(
                        'Drop files here',
                        style: typography.bodyStrong.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s1),
                      Text(
                        'PDF, JPG, PNG up to ${widget.maxSizeMb} MB',
                        style: typography.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s3),
                      OutlinedButton(
                        onPressed: widget.disabled ? null : _browse,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colors.borderDefault),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll,
                          ),
                        ),
                        child: Text(
                          'Browse files',
                          style: typography.bodyStrong.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s3),
          for (final file in _files)
            _FileListTile(
              file: file,
              formatSize: _formatSize,
              reducedMotion: reducedMotion,
              onRemove: () => _remove(file.id),
            ),
        ],
      ],
    );
  }
}

class _FileListTile extends StatelessWidget {
  const _FileListTile({
    required this.file,
    required this.formatSize,
    required this.reducedMotion,
    required this.onRemove,
  });

  final AppFileItem file;
  final String Function(int) formatSize;
  final bool reducedMotion;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.s2),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(Icons.description, size: 20, color: colors.iconMuted),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: typography.body.copyWith(color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  formatSize(file.size),
                  style: typography.caption.copyWith(
                    color: colors.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (file.status == AppFileItemStatus.uploading &&
                    file.progress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s1),
                    child: ClipRRect(
                      borderRadius: AppRadius.fullAll,
                      child: LinearProgressIndicator(
                        value: file.progress! / 100,
                        minHeight: 4,
                        backgroundColor: colors.surfaceMuted,
                        color: colors.actionPrimary,
                      ),
                    ),
                  ),
                if (file.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s0_5),
                    child: Text(
                      file.error!,
                      style: typography.caption.copyWith(
                        color: colors.statusDangerFg,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (file.status == AppFileItemStatus.uploading)
            const AppSpinner(size: AppSpinnerSize.sm)
          else if (file.status == AppFileItemStatus.success)
            Icon(Icons.check_circle, size: 20, color: colors.statusSuccessFg)
          else if (file.status == AppFileItemStatus.error)
            Icon(Icons.error_outline, size: 20, color: colors.statusDangerFg),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: colors.iconMuted),
            onPressed: onRemove,
            tooltip: 'Remove ${file.name}',
          ),
        ],
      ),
    );
  }
}
