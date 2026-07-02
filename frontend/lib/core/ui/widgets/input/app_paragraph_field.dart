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

bool _isQuillDocumentEmpty(QuillController controller) {
  final raw = controller.document.toPlainText();
  final text = raw.endsWith('\n') ? raw.substring(0, raw.length - 1) : raw;
  return text.trim().isEmpty;
}

DefaultStyles _paragraphEditorStyles(BuildContext context, {TextStyle? bodyStyle}) {
  final theme = Theme.of(context);
  final colors = context.semanticColors;
  final resolvedBody = bodyStyle ?? theme.textTheme.bodyLarge!.copyWith(color: colors.foreground, height: 1.5);
  final placeholderStyle = theme.textTheme.bodyLarge!.copyWith(color: colors.mutedForeground, height: 1.5);

  return DefaultStyles.getInstance(context).merge(
    DefaultStyles(
      paragraph: DefaultTextBlockStyle(
        resolvedBody,
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

/// Read-only display styles that keep every block and inline attribute on [bodyStyle].
DefaultStyles _displayEditorStyles(TextStyle bodyStyle) {
  const horizontal = HorizontalSpacing.zero;
  const vertical = VerticalSpacing.zero;
  final block = DefaultTextBlockStyle(bodyStyle, horizontal, vertical, vertical, null);
  final boldBlock = DefaultTextBlockStyle(
    bodyStyle.copyWith(fontWeight: FontWeight.bold),
    horizontal,
    vertical,
    vertical,
    null,
  );

  return DefaultStyles(
    h1: boldBlock,
    h2: boldBlock,
    h3: boldBlock,
    h4: boldBlock,
    h5: boldBlock,
    h6: boldBlock,
    paragraph: block,
    lineHeightNormal: block,
    lineHeightTight: block,
    lineHeightOneAndHalf: block,
    lineHeightDouble: block,
    leading: block,
    indent: block,
    align: block,
    quote: block,
    lists: DefaultListBlockStyle(bodyStyle, horizontal, vertical, vertical, null, null),
    bold: bodyStyle.copyWith(fontWeight: FontWeight.bold),
    italic: bodyStyle.copyWith(fontStyle: FontStyle.italic),
    underline: bodyStyle.copyWith(decoration: TextDecoration.underline),
    strikeThrough: bodyStyle.copyWith(decoration: TextDecoration.lineThrough),
    sizeSmall: bodyStyle,
    sizeLarge: bodyStyle,
    sizeHuge: bodyStyle,
    link: bodyStyle.copyWith(decoration: TextDecoration.underline),
    placeHolder: block,
  );
}

bool richDeltaIsEffectivelyEmpty(List<dynamic>? deltaJson) {
  if (deltaJson == null || deltaJson.isEmpty) {
    return true;
  }
  if (deltaJson.length == 1) {
    final first = deltaJson.first;
    if (first is Map && first['insert'] == '\n' && first['attributes'] == null) {
      return true;
    }
  }
  return false;
}

/// Plain-text fallback for a stored Quill delta when editor flush callbacks are unavailable.
String plainTextFromRichDelta(List<dynamic>? deltaJson) {
  if (richDeltaIsEffectivelyEmpty(deltaJson)) {
    return '';
  }
  final raw = Document.fromJson(deltaJson!).toPlainText();
  if (raw.endsWith('\n')) {
    return raw.substring(0, raw.length - 1);
  }
  return raw;
}

QuillController quillControllerFromDraft(List<dynamic>? deltaJson, String plainText, {bool readOnly = false}) {
  if (!richDeltaIsEffectivelyEmpty(deltaJson)) {
    return QuillController(
      document: Document.fromJson(deltaJson!),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: readOnly,
    );
  }
  final controller = QuillController.basic();
  controller.readOnly = readOnly;
  if (plainText.isNotEmpty) {
    controller.replaceText(0, 0, plainText, TextSelection.collapsed(offset: plainText.length));
  }
  return controller;
}

void setQuillControllerFromDraft(QuillController controller, List<dynamic>? deltaJson, String plainText) {
  if (!richDeltaIsEffectivelyEmpty(deltaJson)) {
    controller.document = Document.fromJson(deltaJson!);
    return;
  }
  final current = controller.plainTextEditingValue.text;
  final deleteLen = current.isEmpty ? 0 : current.length - 1;
  controller.replaceText(0, deleteLen, plainText, TextSelection.collapsed(offset: plainText.length));
}

const double _richToolbarIconSize = 12;

QuillSimpleToolbarConfig _minimalToolbarConfig(BuildContext context) {
  final colors = context.semanticColors;

  return QuillSimpleToolbarConfig(
    multiRowsDisplay: true,
    toolbarIconAlignment: WrapAlignment.end,
    toolbarSize: _richToolbarIconSize * 2,
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
    buttonOptions: const QuillSimpleToolbarButtonOptions(
      base: QuillToolbarBaseButtonOptions(iconSize: _richToolbarIconSize),
    ),
    iconTheme: QuillIconTheme(
      iconButtonSelectedData: IconButtonData(
        iconSize: _richToolbarIconSize,
        style: IconButton.styleFrom(foregroundColor: colors.accentForeground, backgroundColor: colors.accent),
      ),
      iconButtonUnselectedData: IconButtonData(
        iconSize: _richToolbarIconSize,
        style: IconButton.styleFrom(foregroundColor: colors.mutedForeground),
      ),
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
    this.removeBorder = false,
    this.fitParent = false,
    this.expands = false,
    this.minLines = 4,
    this.maxLines,
    this.minHeight,
    this.enabled = true,
    this.size = AppFieldSize.md,
    this.onChanged,
    this.onDocumentChanged,
    this.toolbarLeading,
    this.emptyStateIcon,
    this.emptyStateText,
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

  /// When `true` (rich mode only), the outer field border is omitted.
  final bool removeBorder;

  /// When `true` (rich mode only), the field fills a bounded parent height:
  /// the toolbar stays pinned and the editor scrolls in the remaining space.
  final bool fitParent;

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

  /// Optional widget pinned to the left of the rich-text toolbar row.
  final Widget? toolbarLeading;

  /// When set (rich mode only), shown centered while the document is empty.
  final IconData? emptyStateIcon;

  /// When set (rich mode only), shown centered while the document is empty.
  final String? emptyStateText;

  @override
  State<AppParagraphField> createState() => _AppParagraphFieldState();
}

class _AppParagraphFieldState extends State<AppParagraphField> {
  TextEditingController? _ownedTextController;
  QuillController? _ownedQuillController;
  final _focusNode = FocusNode();
  var _focused = false;
  var _emptyStateDismissed = false;

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
      setState(() {
        _focused = focused;
        if (focused) {
          _emptyStateDismissed = true;
        } else if (_isQuillDocumentEmpty(_quillController)) {
          _emptyStateDismissed = false;
        }
      });
    }
  }

  void _handleEmptyStatePressed() {
    if (!_emptyStateDismissed) {
      setState(() => _emptyStateDismissed = true);
    }
    _focusNode.requestFocus();
  }

  void _handleQuillChange() {
    widget.onDocumentChanged?.call(_quillController.document);
    setState(() {});
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

  bool get _shouldShowEmptyState =>
      !_emptyStateDismissed &&
      !_focused &&
      _isQuillDocumentEmpty(_quillController) &&
      (widget.emptyStateIcon != null || widget.emptyStateText != null);

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
            removeBorder: widget.removeBorder,
            fitParent: widget.fitParent,
            toolbarLeading: widget.toolbarLeading,
            emptyStateIcon: widget.emptyStateIcon,
            emptyStateText: widget.emptyStateText,
            showEmptyState: _shouldShowEmptyState,
            onEmptyStatePressed: _handleEmptyStatePressed,
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

/// Rich-text toolbar with a leading fade divider under the button row.
class _ToolbarWithFadingDivider extends StatelessWidget {
  const _ToolbarWithFadingDivider({required this.controller, required this.config, required this.dividerColor});

  final QuillController controller;
  final QuillSimpleToolbarConfig config;
  final Color dividerColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: QuillSimpleToolbar(controller: controller, config: config),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _FadingToolbarDivider(color: dividerColor)),
      ],
    );
  }
}

/// Horizontal rule under the rich-text toolbar that fades out at the leading edge.
class _FadingToolbarDivider extends StatelessWidget {
  const _FadingToolbarDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.45), color],
            stops: const [0, 0.35, 1],
          ),
        ),
      ),
    );
  }
}

/// Centered prompt shown in an empty rich-text field.
class _RichParagraphEmptyState extends StatelessWidget {
  const _RichParagraphEmptyState({this.icon, this.text});

  final IconData? icon;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 32, color: colors.mutedForeground),
            if (text != null) const SizedBox(height: SpacingTokens.sm),
          ],
          if (text != null)
            Text(
              text!,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
              textAlign: TextAlign.center,
            ),
        ],
      ),
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
    this.removeBorder = false,
    this.fitParent = false,
    this.hintText,
    this.maxHeight,
    this.toolbarLeading,
    this.emptyStateIcon,
    this.emptyStateText,
    this.showEmptyState = false,
    this.onEmptyStatePressed,
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
  final bool removeBorder;
  final bool fitParent;
  final Widget? toolbarLeading;
  final IconData? emptyStateIcon;
  final String? emptyStateText;
  final bool showEmptyState;
  final VoidCallback? onEmptyStatePressed;

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

    final editorConfig = QuillEditorConfig(
      placeholder: hintText,
      padding: padding,
      minHeight: fitParent ? 0 : minHeight - padding.vertical,
      maxHeight: fitParent ? null : (maxHeight == null ? null : maxHeight! - padding.vertical),
      scrollable: fitParent || !expands || maxHeight != null,
      customStyles: _paragraphEditorStyles(context),
    );

    final editorBody = QuillEditor.basic(focusNode: focusNode, controller: controller, config: editorConfig);

    final hasEmptyStatePrompt = emptyStateIcon != null || emptyStateText != null;
    final editorWithEmptyState = hasEmptyStatePrompt
        ? Stack(
            fit: StackFit.expand,
            children: [
              editorBody,
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !showEmptyState,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    opacity: showEmptyState ? 1 : 0,
                    child: Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: enabled ? (_) => onEmptyStatePressed?.call() : null,
                        child: _RichParagraphEmptyState(icon: emptyStateIcon, text: emptyStateText),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          )
        : editorBody;

    final editorPane = fitParent
        ? Expanded(child: editorWithEmptyState)
        : expands
        ? ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight, maxHeight: maxHeight ?? double.infinity),
            child: editorWithEmptyState,
          )
        : SizedBox(height: minHeight, child: editorWithEmptyState);

    final toolbarConfig = _minimalToolbarConfig(context);

    final toolbarChrome = toolbarLeading == null
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: toolbarBackground,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: QuillSimpleToolbar(controller: controller, config: toolbarConfig),
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(color: toolbarBackground),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SpacingTokens.sm,
                SpacingTokens.xs,
                SpacingTokens.sm,
                SpacingTokens.xs,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  toolbarLeading!,
                  const SizedBox(width: SpacingTokens.md),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _ToolbarWithFadingDivider(
                        controller: controller,
                        config: toolbarConfig,
                        dividerColor: colors.border,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

    final editor = IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [toolbarChrome, editorPane]),
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
          border: removeBorder ? null : Border.all(color: borderColor, width: 1),
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
    this.removeBorder = false,
    this.expands = false,
    this.minLines = 4,
    this.maxLines,
    this.minHeight,
    this.enabled = true,
    this.size = AppFieldSize.md,
    this.validator,
    this.onChanged,
    this.onDocumentChanged,
    this.emptyStateIcon,
    this.emptyStateText,
    super.key,
  });

  final String label;
  final String? hintText;
  final String? description;
  final TextEditingController? controller;
  final QuillController? quillController;
  final bool richText;
  final bool transparentBackground;
  final bool removeBorder;
  final bool expands;
  final int minLines;
  final int? maxLines;
  final double? minHeight;
  final bool enabled;
  final AppFieldSize size;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<Document>? onDocumentChanged;
  final IconData? emptyStateIcon;
  final String? emptyStateText;

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
            removeBorder: widget.removeBorder,
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
            emptyStateIcon: widget.emptyStateIcon,
            emptyStateText: widget.emptyStateText,
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

/// Read-only rich-text body for displaying saved Quill delta JSON.
class AppRichTextDisplay extends StatefulWidget {
  const AppRichTextDisplay({required this.plainText, this.deltaJson, this.textStyle, super.key});

  final String plainText;
  final List<dynamic>? deltaJson;
  final TextStyle? textStyle;

  @override
  State<AppRichTextDisplay> createState() => _AppRichTextDisplayState();
}

class _AppRichTextDisplayState extends State<AppRichTextDisplay> {
  late final QuillController _controller;

  @override
  void initState() {
    super.initState();
    _controller = quillControllerFromDraft(widget.deltaJson, widget.plainText, readOnly: true);
  }

  @override
  void didUpdateWidget(covariant AppRichTextDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deltaJson != widget.deltaJson || oldWidget.plainText != widget.plainText) {
      setQuillControllerFromDraft(_controller, widget.deltaJson, widget.plainText);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bodyStyle = widget.textStyle ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

    return DefaultTextStyle(
      style: bodyStyle,
      child: QuillEditor.basic(
        controller: _controller,
        config: QuillEditorConfig(
          padding: EdgeInsets.zero,
          scrollable: false,
          autoFocus: false,
          expands: false,
          customStyles: _displayEditorStyles(bodyStyle),
        ),
      ),
    );
  }
}
