import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Serializable rich-text document stored as Quill delta JSON operations.
@immutable
class AppRichTextValue {
  const AppRichTextValue(this.deltaJson);

  /// Empty document (single trailing newline).
  static const AppRichTextValue empty = AppRichTextValue([
    {'insert': '\n'},
  ]);

  /// Quill delta operations suitable for persistence APIs.
  final List<dynamic> deltaJson;

  /// Parses a JSON-encoded delta operations array.
  factory AppRichTextValue.fromJsonString(String? json) {
    if (json == null || json.trim().isEmpty) {
      return AppRichTextValue.empty;
    }
    final decoded = jsonDecode(json);
    if (decoded is! List) {
      return AppRichTextValue.empty;
    }
    return AppRichTextValue(List<dynamic>.from(decoded));
  }

  /// Encodes [deltaJson] for storage or transport.
  String toJsonString() => jsonEncode(deltaJson);

  /// Whether the document has no meaningful text content.
  bool get isEffectivelyEmpty {
    if (deltaJson.isEmpty) return true;
    if (deltaJson.length == 1) {
      final first = deltaJson.first;
      if (first is Map && first['insert'] == '\n') {
        return true;
      }
    }
    return false;
  }

  /// Plain-text projection of the delta (trailing newline trimmed).
  String toPlainText() {
    if (isEffectivelyEmpty) return '';
    final raw = Document.fromJson(deltaJson).toPlainText();
    if (raw.endsWith('\n')) {
      return raw.substring(0, raw.length - 1);
    }
    return raw;
  }

  @override
  bool operator ==(Object other) {
    return other is AppRichTextValue &&
        jsonEncode(other.deltaJson) == jsonEncode(deltaJson);
  }

  @override
  int get hashCode => jsonEncode(deltaJson).hashCode;
}

/// Controller for [AppRichTextEditor] when parent widgets need imperative access.
///
/// Prefer [value] and [AppRichTextEditor.onChanged] for typical form binding.
/// [quillController] is exposed for advanced formatting or embed configuration.
class AppRichTextEditorController {
  AppRichTextEditorController({AppRichTextValue? initialValue})
    : quillController = QuillController(
        document: _documentFromValue(initialValue ?? AppRichTextValue.empty),
        selection: const TextSelection.collapsed(offset: 0),
      ),
      focusNode = FocusNode(),
      scrollController = ScrollController();

  final QuillController quillController;
  final FocusNode focusNode;
  final ScrollController scrollController;

  AppRichTextValue get value => AppRichTextValue(
    quillController.document.toDelta().toJson(),
  );

  set value(AppRichTextValue next) {
    quillController.document = _documentFromValue(next);
  }

  void dispose() {
    quillController.dispose();
    focusNode.dispose();
    scrollController.dispose();
  }
}

/// Token-styled rich-text editor for clinical and SOAP notes.
///
/// Wraps `flutter_quill` behind [AppRichTextValue] serialization so feature code
/// does not depend on quill types. Compose with [AppFormField] for labels and
/// helper/error text.
class AppRichTextEditor extends StatefulWidget {
  const AppRichTextEditor({
    this.controller,
    this.initialValue,
    this.onChanged,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.placeholder,
    this.minRows = 3,
    super.key,
  });

  final AppRichTextEditorController? controller;
  final AppRichTextValue? initialValue;
  final ValueChanged<AppRichTextValue>? onChanged;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String? placeholder;
  final int minRows;

  @override
  State<AppRichTextEditor> createState() => _AppRichTextEditorState();
}

class _AppRichTextEditorState extends State<AppRichTextEditor> {
  AppRichTextEditorController? _ownedController;
  bool _ownsController = false;

  AppRichTextEditorController get _editorController =>
      widget.controller ?? _ownedController!;

  QuillController get _quill => _editorController.quillController;

  static const double _minHeightFactor = 2;
  static const double _toolbarHeight = AppSpacing.s8;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownedController = AppRichTextEditorController(
        initialValue: widget.initialValue,
      );
      _ownsController = true;
    }
    _quill.addListener(_handleQuillChanged);
    _syncInteractionState();
  }

  @override
  void didUpdateWidget(covariant AppRichTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.quillController.removeListener(_handleQuillChanged);
      if (_ownsController) {
        _ownedController?.dispose();
        _ownedController = null;
        _ownsController = false;
      }
      if (widget.controller == null) {
        _ownedController = AppRichTextEditorController(
          initialValue: widget.initialValue,
        );
        _ownsController = true;
      }
      _quill.addListener(_handleQuillChanged);
    } else if (_ownsController &&
        widget.initialValue != null &&
        widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != _editorController.value) {
      _editorController.value = widget.initialValue!;
    }
    _syncInteractionState();
  }

  @override
  void dispose() {
    _quill.removeListener(_handleQuillChanged);
    if (_ownsController) {
      _ownedController?.dispose();
    }
    super.dispose();
  }

  void _handleQuillChanged() {
    widget.onChanged?.call(_editorController.value);
    if (mounted) setState(() {});
  }

  void _syncInteractionState() {
    _quill.readOnly = widget.disabled || widget.readOnly;
  }

  double get _editorMinHeight =>
      AppSpacing.s8 * _minHeightFactor * (widget.minRows / 3);

  double get _frameMinHeight =>
      _editorMinHeight + (widget.readOnly || widget.disabled ? 0 : _toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final framePadding = widget.size.padding;
    final showToolbar = !widget.readOnly && !widget.disabled;
    final editorConfig = _editorConfig(context);

    return AppInputFrame(
      focusNode: _editorController.focusNode,
      size: widget.size,
      invalid: widget.invalid,
      disabled: widget.disabled,
      readOnly: widget.readOnly,
      minHeight: _frameMinHeight,
      padding: EdgeInsetsDirectional.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showToolbar) ...[
            _AppRichTextToolbar(
              controller: _quill,
              focusNode: _editorController.focusNode,
              disabled: widget.disabled,
            ),
            Divider(
              height: AppSignal.thickness,
              thickness: AppSignal.thickness,
              color: colors.borderSubtle,
            ),
          ],
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              framePadding.start,
              AppSpacing.s2,
              framePadding.end,
              AppSpacing.s2,
            ),
            child: SizedBox(
              height: _editorMinHeight,
              child: QuillEditor(
                focusNode: _editorController.focusNode,
                scrollController: _editorController.scrollController,
                controller: _quill,
                config: editorConfig,
              ),
            ),
          ),
        ],
      ),
    );
  }

  QuillEditorConfig _editorConfig(BuildContext context) {
    final colors = context.colors;
    return QuillEditorConfig(
      placeholder: widget.placeholder,
      customStyles: _editorStyles(context, widget.size),
      padding: EdgeInsets.zero,
      scrollable: true,
      autoFocus: false,
      enableSelectionToolbar: !widget.readOnly && !widget.disabled,
      readOnlyMouseCursor: widget.readOnly
          ? SystemMouseCursors.basic
          : SystemMouseCursors.text,
      textSelectionThemeData: TextSelectionThemeData(
        cursorColor: colors.borderFocus,
        selectionColor: colors.surfaceSelected,
        selectionHandleColor: colors.borderFocus,
      ),
    );
  }
}

Document _documentFromValue(AppRichTextValue value) {
  if (value.isEffectivelyEmpty) {
    return Document();
  }
  return Document.fromJson(value.deltaJson);
}

DefaultStyles _editorStyles(BuildContext context, AppFieldSize size) {
  final colors = context.colors;
  final typography = context.typography;
  final baseStyle = appBareInputTextStyle(context, size: size).copyWith(
    height: 1.4,
    decoration: TextDecoration.none,
  );

  const horizontalSpacing = HorizontalSpacing(0, 0);
  const verticalSpacing = VerticalSpacing(AppSpacing.s1, 0);
  const lineSpacing = VerticalSpacing(0, 0);

  DefaultTextBlockStyle block(TextStyle style) => DefaultTextBlockStyle(
    style.copyWith(color: colors.textPrimary, decoration: TextDecoration.none),
    horizontalSpacing,
    verticalSpacing,
    lineSpacing,
    null,
  );

  TextStyle heading(TextStyle style) =>
      style.copyWith(color: colors.textPrimary, decoration: TextDecoration.none);

  final listStyle = DefaultListBlockStyle(
    baseStyle.copyWith(color: colors.textPrimary),
    horizontalSpacing,
    verticalSpacing,
    lineSpacing,
    null,
    null,
  );

  return DefaultStyles(
    paragraph: block(baseStyle),
    h1: block(heading(typography.h1)),
    h2: block(heading(typography.h2)),
    h3: block(heading(typography.h3)),
    placeHolder: DefaultTextBlockStyle(
      baseStyle.copyWith(color: colors.textPlaceholder),
      horizontalSpacing,
      verticalSpacing,
      lineSpacing,
      null,
    ),
    bold: baseStyle.copyWith(fontWeight: FontWeight.w600),
    italic: baseStyle.copyWith(fontStyle: FontStyle.italic),
    underline: baseStyle.copyWith(decoration: TextDecoration.underline),
    lists: listStyle,
    link: baseStyle.copyWith(
      color: colors.textLink,
      decoration: TextDecoration.underline,
    ),
  );
}

class _AppRichTextToolbar extends StatelessWidget {
  const _AppRichTextToolbar({
    required this.controller,
    required this.focusNode,
    required this.disabled,
  });

  final QuillController controller;
  final FocusNode focusNode;
  final bool disabled;

  static const double _height = AppSpacing.s8;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textDirection = Directionality.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final style = controller.getSelectionStyle();

        return SizedBox(
          height: _height,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.s1,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: textDirection == TextDirection.rtl,
              child: Row(
                textDirection: textDirection,
                children: [
                  _FormatButton(
                    icon: LucideIcons.bold,
                    label: 'Bold',
                    isActive: _isActive(style, Attribute.bold),
                    disabled: disabled,
                    onPressed: () => _toggleAttribute(Attribute.bold),
                  ),
                  _FormatButton(
                    icon: LucideIcons.italic,
                    label: 'Italic',
                    isActive: _isActive(style, Attribute.italic),
                    disabled: disabled,
                    onPressed: () => _toggleAttribute(Attribute.italic),
                  ),
                  _FormatButton(
                    icon: LucideIcons.underline,
                    label: 'Underline',
                    isActive: _isActive(style, Attribute.underline),
                    disabled: disabled,
                    onPressed: () => _toggleAttribute(Attribute.underline),
                  ),
                  _ToolbarDivider(color: colors.borderSubtle),
                  _FormatButton(
                    icon: LucideIcons.list,
                    label: 'Bullet list',
                    isActive: _isListActive(style, Attribute.ul),
                    disabled: disabled,
                    onPressed: () => _toggleAttribute(Attribute.ul),
                  ),
                  _FormatButton(
                    icon: LucideIcons.listOrdered,
                    label: 'Numbered list',
                    isActive: _isListActive(style, Attribute.ol),
                    disabled: disabled,
                    onPressed: () => _toggleAttribute(Attribute.ol),
                  ),
                  _ToolbarDivider(color: colors.borderSubtle),
                  _FormatButton(
                    icon: LucideIcons.heading1,
                    label: 'Heading 1',
                    isActive: _isHeaderActive(style, Attribute.h1),
                    disabled: disabled,
                    onPressed: () => _toggleHeader(Attribute.h1),
                  ),
                  _FormatButton(
                    icon: LucideIcons.heading2,
                    label: 'Heading 2',
                    isActive: _isHeaderActive(style, Attribute.h2),
                    disabled: disabled,
                    onPressed: () => _toggleHeader(Attribute.h2),
                  ),
                  _FormatButton(
                    icon: LucideIcons.heading3,
                    label: 'Heading 3',
                    isActive: _isHeaderActive(style, Attribute.h3),
                    disabled: disabled,
                    onPressed: () => _toggleHeader(Attribute.h3),
                  ),
                  _ToolbarDivider(color: colors.borderSubtle),
                  _FormatButton(
                    icon: LucideIcons.eraser,
                    label: 'Clear formatting',
                    disabled: disabled,
                    onPressed: _clearFormatting,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isActive(Style style, Attribute<dynamic> attribute) {
    return style.containsKey(attribute.key);
  }

  bool _isListActive(Style style, Attribute<dynamic> attribute) {
    final current = style.attributes[Attribute.list.key];
    return current?.value == attribute.value;
  }

  bool _isHeaderActive(Style style, Attribute<dynamic> attribute) {
    final current = style.attributes[Attribute.header.key];
    return current?.value == attribute.value;
  }

  void _toggleAttribute(Attribute<dynamic> attribute) {
    final style = controller.getSelectionStyle();
    final isToggled = attribute.key == 'list'
        ? _isListActive(style, attribute)
        : _isActive(style, attribute);
    controller.formatSelection(
      Attribute.clone(attribute, isToggled ? null : attribute.value),
    );
    focusNode.requestFocus();
  }

  void _toggleHeader(Attribute<int?> header) {
    final style = controller.getSelectionStyle();
    final isToggled = _isHeaderActive(style, header);
    controller.formatSelection(
      Attribute.clone(Attribute.header, isToggled ? null : header.value),
    );
    focusNode.requestFocus();
  }

  void _clearFormatting() {
    final attributes = <Attribute<dynamic>>{};
    for (final style in controller.getAllSelectionStyles()) {
      attributes.addAll(style.attributes.values);
    }
    for (final attribute in attributes) {
      controller.formatSelection(Attribute.clone(attribute, null));
    }
    focusNode.requestFocus();
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isActive = false,
    this.disabled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isActive;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return AppTooltip(
      message: label,
      child: AppIconButton(
        icon: icon,
        semanticLabel: label,
        size: AppIconButtonSize.sm,
        variant: isActive
            ? AppIconButtonVariant.secondary
            : AppIconButtonVariant.ghost,
        disabled: disabled,
        onPressed: disabled ? null : onPressed,
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.s5,
      child: VerticalDivider(
        width: AppSpacing.s2,
        thickness: AppSignal.thickness,
        color: color,
      ),
    );
  }
}
