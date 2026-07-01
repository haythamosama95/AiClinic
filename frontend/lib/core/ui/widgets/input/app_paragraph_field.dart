import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';

import 'app_field_size.dart';
import 'app_label.dart';

EdgeInsets _paragraphContentPadding(AppFieldSize size) => switch (size) {
  AppFieldSize.sm => const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  AppFieldSize.md => const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
  AppFieldSize.lg => const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
};

double _paragraphMinHeight(AppFieldSize size, int minLines) {
  final lineHeight = switch (size) {
    AppFieldSize.sm => 18.0,
    AppFieldSize.md => 20.0,
    AppFieldSize.lg => 22.0,
  };
  final padding = _paragraphContentPadding(size);
  return padding.vertical + (lineHeight * minLines);
}

FTextFieldStyleDelta _paragraphFieldStyle(AppFieldSize size, int minLines) => FTextFieldStyleDelta.delta(
  contentPadding: EdgeInsetsGeometryDelta.value(_paragraphContentPadding(size)),
  constraints: BoxConstraints(minHeight: _paragraphMinHeight(size, minLines)),
);

DefaultStyles _paragraphEditorStyles(BuildContext context) {
  final theme = Theme.of(context);
  final colors = context.semanticColors;
  final bodyStyle = theme.textTheme.bodyLarge!.copyWith(color: colors.foreground, height: 1.5);
  final placeholderStyle = theme.textTheme.bodyLarge!.copyWith(color: colors.mutedForeground, height: 1.5);

  return DefaultStyles.getInstance(context).merge(
    DefaultStyles(
      paragraph: DefaultTextBlockStyle(
        bodyStyle,
        HorizontalSpacing.zero,
        VerticalSpacing.zero,
        const VerticalSpacing(0, 8),
        null,
      ),
      placeHolder: DefaultTextBlockStyle(
        placeholderStyle,
        HorizontalSpacing.zero,
        VerticalSpacing.zero,
        VerticalSpacing.zero,
        null,
      ),
    ),
  );
}

QuillSimpleToolbarConfig _minimalToolbarConfig(BuildContext context) {
  final colors = context.semanticColors;

  return QuillSimpleToolbarConfig(
    multiRowsDisplay: true,
    toolbarIconAlignment: WrapAlignment.end,
    showDividers: true,
    showFontFamily: false,
    showFontSize: false,
    showDirection: true,
    showStrikeThrough: false,
    showInlineCode: false,
    showColorButton: false,
    showBackgroundColorButton: false,
    showClearFormat: false,
    showHeaderStyle: false,
    showListCheck: false,
    showCodeBlock: false,
    showQuote: false,
    showIndent: false,
    showLink: false,
    showSearchButton: false,
    showSubscript: false,
    showSuperscript: false,
    showLineHeightButton: false,
    showAlignmentButtons: false,
    decoration: const BoxDecoration(),
    iconTheme: QuillIconTheme(
      iconButtonSelectedData: IconButtonData(
        style: IconButton.styleFrom(foregroundColor: colors.accentForeground, backgroundColor: colors.accent),
      ),
      iconButtonUnselectedData: IconButtonData(style: IconButton.styleFrom(foregroundColor: colors.mutedForeground)),
    ),
  );
}

/// Multiline paragraph field for long-form text, with optional rich-text editing.
///
/// Plain mode wraps [FTextField] with multiline sizing. Rich mode embeds
/// [QuillSimpleToolbar] and [QuillEditor] inside a token-matched chrome.
///
/// When [expands] is `false` (default), the field keeps a fixed height based on
/// [minLines] and scrolls internally. When `true`, it grows with the content
/// from [minLines] upward (optionally capped by [maxLines]).
class AppParagraphField extends StatefulWidget {
  const AppParagraphField({
    this.label,
    this.hintText,
    this.description,
    this.error,
    this.controller,
    this.quillController,
    this.richText = false,
    this.transparentBackground = false,
    this.expands = false,
    this.minLines = 4,
    this.maxLines,
    this.minHeight,
    this.enabled = true,
    this.size = AppFieldSize.md,
    this.onChanged,
    this.onDocumentChanged,
    super.key,
  });

  final String? label;
  final String? hintText;
  final String? description;
  final String? error;
  final TextEditingController? controller;
  final QuillController? quillController;
  final bool richText;

  /// When `true`, the rich-text editor chrome is transparent so the parent
  /// container's background shows through. Ignored in plain mode.
  final bool transparentBackground;

  /// When `false`, height is fixed to [minLines] and content scrolls inside.
  /// When `true`, the field grows vertically as text is added.
  final bool expands;
  final int minLines;
  final int? maxLines;
  final double? minHeight;
  final bool enabled;
  final AppFieldSize size;
  final ValueChanged<String>? onChanged;
  final ValueChanged<Document>? onDocumentChanged;

  @override
  State<AppParagraphField> createState() => _AppParagraphFieldState();
}

class _AppParagraphFieldState extends State<AppParagraphField> {
  TextEditingController? _ownedTextController;
  QuillController? _ownedQuillController;
  final _focusNode = FocusNode();
  var _focused = false;

  TextEditingController get _textController => widget.controller ?? _ownedTextController!;

  QuillController get _quillController => widget.quillController ?? _ownedQuillController!;

  @override
  void initState() {
    super.initState();
    if (!widget.richText && widget.controller == null) {
      _ownedTextController = TextEditingController();
    }
    if (widget.richText && widget.quillController == null) {
      _ownedQuillController = QuillController.basic();
    }
    _focusNode.addListener(_handleFocusChange);
    if (widget.richText) {
      _quillController.addListener(_handleQuillChange);
    }
  }

  @override
  void didUpdateWidget(covariant AppParagraphField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.richText != oldWidget.richText) {
      throw StateError('AppParagraphField.richText cannot change after mount.');
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    if (widget.richText) {
      _quillController.removeListener(_handleQuillChange);
    }
    _ownedTextController?.dispose();
    _ownedQuillController?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _focusNode.hasFocus;
    if (focused != _focused) {
      setState(() => _focused = focused);
    }
  }

  void _handleQuillChange() {
    widget.onDocumentChanged?.call(_quillController.document);
  }

  double get _resolvedMinHeight => widget.minHeight ?? _paragraphMinHeight(widget.size, widget.minLines);

  int? get _effectiveMaxLines => widget.expands ? widget.maxLines : (widget.maxLines ?? widget.minLines);

  double? get _resolvedMaxHeight {
    final maxLines = widget.maxLines;
    if (!widget.expands || maxLines == null) {
      return null;
    }
    return _paragraphMinHeight(widget.size, maxLines);
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.richText
        ? _RichParagraphEditor(
            controller: _quillController,
            focusNode: _focusNode,
            hintText: widget.hintText,
            enabled: widget.enabled,
            size: widget.size,
            minHeight: _resolvedMinHeight,
            expands: widget.expands,
            maxHeight: _resolvedMaxHeight,
            focused: _focused,
            hasError: widget.error != null,
            transparentBackground: widget.transparentBackground,
          )
        : _PlainParagraphEditor(
            controller: _textController,
            focusNode: _focusNode,
            hintText: widget.hintText,
            enabled: widget.enabled,
            size: widget.size,
            minLines: widget.minLines,
            maxLines: _effectiveMaxLines,
            onChanged: widget.onChanged,
          );

    return AppLabel(label: widget.label, description: widget.description, error: widget.error, child: field);
  }
}

class _PlainParagraphEditor extends StatelessWidget {
  const _PlainParagraphEditor({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.size,
    required this.minLines,
    this.hintText,
    this.maxLines,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? hintText;
  final bool enabled;
  final AppFieldSize size;
  final int minLines;
  final int? maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return FTextField(
      control: FTextFieldControl.managed(
        controller: controller,
        onChange: onChanged == null ? null : (value) => onChanged!(value.text),
      ),
      focusNode: focusNode,
      size: size.forui,
      style: _paragraphFieldStyle(size, minLines),
      hint: hintText,
      enabled: enabled,
      minLines: minLines,
      maxLines: maxLines,
      textAlignVertical: TextAlignVertical.top,
    );
  }
}

class _RichParagraphEditor extends StatelessWidget {
  const _RichParagraphEditor({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.size,
    required this.minHeight,
    required this.expands,
    required this.focused,
    required this.hasError,
    this.transparentBackground = false,
    this.hintText,
    this.maxHeight,
  });

  final QuillController controller;
  final FocusNode focusNode;
  final String? hintText;
  final bool enabled;
  final AppFieldSize size;
  final double minHeight;
  final bool expands;
  final double? maxHeight;
  final bool focused;
  final bool hasError;
  final bool transparentBackground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final padding = _paragraphContentPadding(size);
    final fieldBackground = transparentBackground ? Colors.transparent : colors.background;
    final toolbarBackground = transparentBackground ? Colors.transparent : colors.muted.withValues(alpha: 0.35);
    final borderColor = hasError
        ? theme.colorScheme.error
        : focused
        ? colors.ring
        : colors.input;

    final editorBody = QuillEditor.basic(
      focusNode: focusNode,
      controller: controller,
      config: QuillEditorConfig(
        placeholder: hintText,
        padding: padding,
        minHeight: minHeight - padding.vertical,
        maxHeight: maxHeight == null ? null : maxHeight! - padding.vertical,
        scrollable: !expands || maxHeight != null,
        customStyles: _paragraphEditorStyles(context),
      ),
    );

    final editor = IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: toolbarBackground,
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: QuillSimpleToolbar(controller: controller, config: _minimalToolbarConfig(context)),
              ),
            ),
            if (expands)
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight, maxHeight: maxHeight ?? double.infinity),
                child: editorBody,
              )
            else
              SizedBox(height: minHeight, child: editorBody),
          ],
        ),
      ),
    );

    return Localizations(
      locale: Localizations.localeOf(context),
      delegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: fieldBackground,
          borderRadius: BorderRadius.circular(RadiusTokens.lg),
          border: Border.all(color: borderColor, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: editor,
      ),
    );
  }
}

/// Form-friendly paragraph field with validation.
class AppParagraphFormField extends StatefulWidget {
  const AppParagraphFormField({
    required this.label,
    this.hintText,
    this.description,
    this.controller,
    this.quillController,
    this.richText = false,
    this.transparentBackground = false,
    this.expands = false,
    this.minLines = 4,
    this.maxLines,
    this.minHeight,
    this.enabled = true,
    this.size = AppFieldSize.md,
    this.validator,
    this.onChanged,
    this.onDocumentChanged,
    super.key,
  });

  final String label;
  final String? hintText;
  final String? description;
  final TextEditingController? controller;
  final QuillController? quillController;
  final bool richText;
  final bool transparentBackground;
  final bool expands;
  final int minLines;
  final int? maxLines;
  final double? minHeight;
  final bool enabled;
  final AppFieldSize size;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<Document>? onDocumentChanged;

  @override
  State<AppParagraphFormField> createState() => _AppParagraphFormFieldState();
}

class _AppParagraphFormFieldState extends State<AppParagraphFormField> {
  QuillController? _ownedQuillController;

  QuillController get _quillController => widget.quillController ?? _ownedQuillController!;

  @override
  void initState() {
    super.initState();
    if (widget.richText && widget.quillController == null) {
      _ownedQuillController = QuillController.basic();
    }
    if (widget.richText) {
      _quillController.addListener(_handleQuillChange);
    }
  }

  @override
  void dispose() {
    if (widget.richText) {
      _quillController.removeListener(_handleQuillChange);
    }
    _ownedQuillController?.dispose();
    super.dispose();
  }

  void _handleQuillChange() {
    widget.onDocumentChanged?.call(_quillController.document);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.richText) {
      return FormField<String>(
        validator: widget.validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        initialValue: _quillController.document.toPlainText(),
        builder: (state) {
          return AppParagraphField(
            label: widget.label,
            hintText: widget.hintText,
            description: widget.description,
            error: state.errorText,
            quillController: _quillController,
            richText: true,
            transparentBackground: widget.transparentBackground,
            expands: widget.expands,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            minHeight: widget.minHeight,
            enabled: widget.enabled,
            size: widget.size,
            onDocumentChanged: (document) {
              state.didChange(document.toPlainText());
              widget.onDocumentChanged?.call(document);
            },
          );
        },
      );
    }

    return FTextFormField(
      control: widget.controller != null
          ? FTextFieldControl.managed(
              controller: widget.controller,
              onChange: widget.onChanged == null ? null : (value) => widget.onChanged!(value.text),
            )
          : FTextFieldControl.managed(
              onChange: widget.onChanged == null ? null : (value) => widget.onChanged!(value.text),
            ),
      size: widget.size.forui,
      style: _paragraphFieldStyle(widget.size, widget.minLines),
      label: Text(widget.label, style: theme.textTheme.labelMedium),
      description: widget.description == null ? null : Text(widget.description!, style: theme.textTheme.bodySmall),
      hint: widget.hintText,
      enabled: widget.enabled,
      minLines: widget.minLines,
      maxLines: widget.expands ? widget.maxLines : (widget.maxLines ?? widget.minLines),
      textAlignVertical: TextAlignVertical.top,
      validator: widget.validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
    );
  }
}
