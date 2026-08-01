import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Upload lifecycle for a file in [AppFileDropzone] (web `FileItem.status`).
enum AppFileItemStatus { uploading, success, error }

/// File row model for [AppFileDropzone] (web `FileItem`).
@immutable
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
  final int? progress;
  final String? error;

  AppFileItem copyWith({String? id, String? name, int? size, AppFileItemStatus? status, int? progress, String? error}) {
    return AppFileItem(
      id: id ?? this.id,
      name: name ?? this.name,
      size: size ?? this.size,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
    );
  }
}

/// Drag-and-drop / browse file upload zone (web `FileDropzone`).
class AppFileDropzone extends StatefulWidget {
  const AppFileDropzone({
    this.id,
    this.accept = '.pdf,.jpg,.jpeg,.png',
    this.multiple = true,
    this.disabled = false,
    this.invalid = false,
    this.files,
    this.onFilesChange,
    this.onUpload,
    this.maxSizeMb = 10,
    this.ariaLabelledBy,
    this.ariaDescribedBy,
    super.key,
  });

  final String? id;
  final String accept;
  final bool multiple;
  final bool disabled;
  final bool invalid;
  final List<AppFileItem>? files;
  final ValueChanged<List<AppFileItem>>? onFilesChange;
  final Future<void> Function(PlatformFile file)? onUpload;
  final int maxSizeMb;
  final String? ariaLabelledBy;
  final String? ariaDescribedBy;

  @override
  State<AppFileDropzone> createState() => _AppFileDropzoneState();
}

class _IncomingFile {
  const _IncomingFile({required this.name, required this.size, this.path, this.bytes});

  final String name;
  final int size;
  final String? path;
  final Uint8List? bytes;

  factory _IncomingFile.fromPlatform(PlatformFile file) {
    return _IncomingFile(name: file.name, size: file.size, path: file.path, bytes: file.bytes);
  }

  PlatformFile toPlatformFile() {
    return PlatformFile(name: name, size: size, path: path, bytes: bytes);
  }
}

class _AppFileDropzoneState extends State<AppFileDropzone> {
  final _focusNode = FocusNode();
  var _dragOver = false;
  List<AppFileItem> _internalFiles = [];

  bool get _isControlled => widget.files != null;

  List<AppFileItem> get _files => widget.files ?? _internalFiles;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _setFiles(List<AppFileItem> next) {
    if (!_isControlled) {
      setState(() => _internalFiles = next);
    }
    widget.onFilesChange?.call(next);
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}';

  List<String> _parseAccept(String accept) {
    return accept
        .split(',')
        .map((part) => part.trim().replaceFirst(RegExp(r'^\.'), ''))
        .where((part) => part.isNotEmpty)
        .toList();
  }

  Future<void> _browse() async {
    if (widget.disabled) return;

    final extensions = _parseAccept(widget.accept);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      allowMultiple: widget.multiple,
      withData: widget.onUpload != null,
    );
    if (result == null || !mounted) return;

    await _processIncomingFiles(result.files.map(_IncomingFile.fromPlatform).toList());
  }

  Future<void> _processIncomingFiles(List<_IncomingFile> incoming) async {
    for (final file in incoming) {
      await _processOne(file);
    }
  }

  Future<void> _processOne(_IncomingFile file) async {
    final maxBytes = widget.maxSizeMb * 1024 * 1024;

    if (file.size > maxBytes) {
      final item = AppFileItem(
        id: _newId(),
        name: file.name,
        size: file.size,
        status: AppFileItemStatus.error,
        error: 'File exceeds ${widget.maxSizeMb} MB limit',
      );
      _setFiles([..._files, item]);
      return;
    }

    final item = AppFileItem(
      id: _newId(),
      name: file.name,
      size: file.size,
      status: AppFileItemStatus.uploading,
      progress: 0,
    );
    var current = [..._files, item];
    _setFiles(current);

    if (widget.onUpload != null) {
      try {
        for (final progress in [20, 40, 60, 80, 100]) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (!mounted) return;
          current = current.map((f) => f.id == item.id ? f.copyWith(progress: progress) : f).toList();
          _setFiles(current);
        }
        await widget.onUpload!(file.toPlatformFile());
        if (!mounted) return;
        current = current
            .map((f) => f.id == item.id ? f.copyWith(status: AppFileItemStatus.success, progress: 100) : f)
            .toList();
        _setFiles(current);
      } catch (_) {
        if (!mounted) return;
        current = current
            .map(
              (f) =>
                  f.id == item.id ? f.copyWith(status: AppFileItemStatus.error, error: 'Upload failed. Try again.') : f,
            )
            .toList();
        _setFiles(current);
      }
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      current = current
          .map((f) => f.id == item.id ? f.copyWith(status: AppFileItemStatus.success, progress: 100) : f)
          .toList();
      _setFiles(current);
    }
  }

  Future<void> _handleDropData(Object? data) async {
    if (widget.disabled || data == null) return;

    final incoming = <_IncomingFile>[];

    if (data is List) {
      for (final item in data) {
        final file = await _incomingFromDynamic(item);
        if (file != null) incoming.add(file);
      }
    } else {
      final file = await _incomingFromDynamic(data);
      if (file != null) incoming.add(file);
    }

    if (incoming.isNotEmpty) {
      await _processIncomingFiles(incoming);
    }
  }

  Future<_IncomingFile?> _incomingFromDynamic(Object? item) async {
    if (item is String) {
      return _IncomingFile(name: item.split(RegExp(r'[/\\]')).last, size: 0, path: item);
    }

    try {
      final dynamic file = item;
      final name = file.name;
      if (name is String) {
        final size = await file.length() as int;
        final path = file.path as String?;
        return _IncomingFile(name: name, size: size, path: path);
      }
    } catch (_) {
      // Not a file-like drop payload.
    }
    return null;
  }

  void _remove(String fileId) {
    _setFiles(_files.where((f) => f.id != fileId).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DragTarget<Object>(
          onWillAcceptWithDetails: (details) => !widget.disabled,
          onMove: (_) {
            if (!_dragOver && !widget.disabled) {
              setState(() => _dragOver = true);
            }
          },
          onLeave: (_) {
            if (_dragOver) {
              setState(() => _dragOver = false);
            }
          },
          onAcceptWithDetails: (details) {
            setState(() => _dragOver = false);
            _handleDropData(details.data);
          },
          builder: (context, candidateData, rejectedData) {
            final isDragOver = _dragOver || candidateData.isNotEmpty;
            return _DropzoneArea(
              id: widget.id,
              disabled: widget.disabled,
              invalid: widget.invalid,
              dragOver: isDragOver,
              maxSizeMb: widget.maxSizeMb,
              focusNode: _focusNode,
              ariaLabelledBy: widget.ariaLabelledBy,
              ariaDescribedBy: widget.ariaDescribedBy,
              onActivate: _browse,
              onBrowse: _browse,
            );
          },
        ),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.space3),
          Semantics(
            label: 'Uploaded files',
            child: Column(
              children: [
                for (final file in _files)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                    child: _FileRow(file: file, onRemove: () => _remove(file.id)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DropzoneArea extends StatefulWidget {
  const _DropzoneArea({
    required this.disabled,
    required this.invalid,
    required this.dragOver,
    required this.maxSizeMb,
    required this.focusNode,
    required this.onActivate,
    required this.onBrowse,
    this.id,
    this.ariaLabelledBy,
    this.ariaDescribedBy,
  });

  final String? id;
  final bool disabled;
  final bool invalid;
  final bool dragOver;
  final int maxSizeMb;
  final FocusNode focusNode;
  final String? ariaLabelledBy;
  final String? ariaDescribedBy;
  final VoidCallback onActivate;
  final VoidCallback onBrowse;

  @override
  State<_DropzoneArea> createState() => _DropzoneAreaState();
}

class _DropzoneAreaState extends State<_DropzoneArea> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final borderColor = widget.invalid
        ? colors.statusDangerBorder
        : widget.dragOver
        ? colors.signalColor
        : colors.borderDefault;
    final backgroundColor = widget.dragOver
        ? colors.surfaceSelected
        : _hovered && !widget.disabled
        ? colors.surfaceHover
        : colors.surfaceDefault;

    return Semantics(
      button: true,
      enabled: !widget.disabled,
      label: 'Drop files here',
<<<<<<< HEAD
=======
      identifier: widget.id,
>>>>>>> master
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (node, event) {
          if (widget.disabled) return KeyEventResult.ignored;
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onActivate();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          onEnter: widget.disabled ? null : (_) => setState(() => _hovered = true),
          onExit: widget.disabled ? null : (_) => setState(() => _hovered = false),
          cursor: widget.disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.disabled ? null : widget.onActivate,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(AppSpacing.space8),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: borderColor, width: 2, strokeAlign: BorderSide.strokeAlignInside),
              ),
              child: Opacity(
                opacity: widget.disabled ? 0.5 : 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.upload_file, size: 32, color: colors.iconMuted),
                    const SizedBox(height: AppSpacing.space3),
                    Text(
                      'Drop files here',
                      style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.space1),
                    Text(
                      'PDF, JPG, PNG up to ${widget.maxSizeMb} MB',
                      style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.space3),
                    _BrowseButton(disabled: widget.disabled, onPressed: widget.onBrowse),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrowseButton extends StatelessWidget {
  const _BrowseButton({required this.disabled, required this.onPressed});

  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: 'Browse files',
      child: Material(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: disabled
              ? null
              : () {
                  onPressed();
                },
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.borderDefault),
            ),
            child: Text('Browse files', style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.onRemove});

  final AppFileItem file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

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
            Icon(Icons.description_outlined, size: 20, color: colors.iconMuted),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: AppTypography.body(context).copyWith(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _formatSize(file.size),
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: colors.textTertiary, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  if (file.status == AppFileItemStatus.uploading && file.progress != null) ...[
                    const SizedBox(height: AppSpacing.space1),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      child: LinearProgressIndicator(
                        value: file.progress! / 100,
                        minHeight: 4,
                        backgroundColor: colors.surfaceMuted,
                        color: colors.actionPrimary,
                        semanticsLabel: 'Upload progress',
                        semanticsValue: '${file.progress}%',
                      ),
                    ),
                  ],
                  if (file.error != null) ...[
                    const SizedBox(height: AppSpacing.space05),
                    Text(file.error!, style: AppTypography.caption(context).copyWith(color: colors.statusDangerFg)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.space2),
            _StatusIcon(status: file.status),
            const SizedBox(width: AppSpacing.space1),
            Semantics(
              button: true,
              label: 'Remove ${file.name}',
              child: IconButton(
                onPressed: onRemove,
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
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final AppFileItemStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return switch (status) {
      AppFileItemStatus.uploading => SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.iconMuted),
      ),
      AppFileItemStatus.success => Semantics(
        label: 'Upload complete',
        child: Icon(Icons.check_circle, size: 20, color: colors.statusSuccessFg),
      ),
      AppFileItemStatus.error => Semantics(
        label: 'Upload failed',
        child: Icon(Icons.error_outline, size: 20, color: colors.statusDangerFg),
      ),
    };
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
