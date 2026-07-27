import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/rich_text/rich_text_delta_utils.dart';

typedef AppRichTextChanged = void Function(String plainText, List<dynamic>? richDelta);

EdgeInsets _editorContentPadding(AppInputSize size) => switch (size) {
  AppInputSize.sm => const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
  AppInputSize.md => const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
  AppInputSize.lg => const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
};

double _editorMinHeight(AppInputSize size, int minLines) {
  final lineHeight = switch (size) {
    AppInputSize.sm => 18.0,
    AppInputSize.md => 20.0,
    AppInputSize.lg => 22.0,
  };
  final padding = _editorContentPadding(size);
  return padding.vertical + (lineHeight * minLines);
}

DefaultStyles _editorStyles(BuildContext context, AppInputSize size, {required bool disabled}) {
  final bodyStyle = appBareInputTextStyle(context, size, disabled: disabled).copyWith(height: 1.5);
  final placeholderStyle = bodyStyle.copyWith(color: context.appColors.textPlaceholder);
  const blockSpacing = HorizontalSpacing.zero;
  const listVerticalSpacing = VerticalSpacing(6, 0);
  const listLineSpacing = VerticalSpacing(0, 6);

  final paragraphBlock = DefaultTextBlockStyle(
    bodyStyle,
    blockSpacing,
    VerticalSpacing.zero,
    const VerticalSpacing(0, 8),
    null,
  );

  return DefaultStyles.getInstance(context).merge(
    DefaultStyles(
      paragraph: paragraphBlock,
      placeHolder: DefaultTextBlockStyle(
        placeholderStyle,
        blockSpacing,
        VerticalSpacing.zero,
        VerticalSpacing.zero,
        null,
      ),
      lists: DefaultListBlockStyle(bodyStyle, blockSpacing, listVerticalSpacing, listLineSpacing, null, null),
      leading: DefaultTextBlockStyle(bodyStyle, blockSpacing, VerticalSpacing.zero, VerticalSpacing.zero, null),
      indent: DefaultTextBlockStyle(bodyStyle, blockSpacing, listVerticalSpacing, listLineSpacing, null),
      link: bodyStyle.copyWith(
        color: context.appColors.textLink,
        decoration: TextDecoration.underline,
        decorationColor: context.appColors.textLink,
      ),
    ),
  );
}

QuillSimpleToolbarConfig _toolbarConfig(BuildContext context, AppInputSize size) {
  final colors = context.appColors;
  final metrics = appInputMetrics(context, size);
  final iconSize = metrics.iconSize;
  final toolbarButtonOptions = QuillSimpleToolbarButtonOptions(
    base: QuillToolbarBaseButtonOptions(iconSize: iconSize, iconButtonFactor: 1.35),
  );

  return QuillSimpleToolbarConfig(
    multiRowsDisplay: true,
    toolbarIconAlignment: WrapAlignment.end,
    toolbarSize: iconSize * 1.75,
    buttonOptions: toolbarButtonOptions,
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
        style: IconButton.styleFrom(foregroundColor: colors.actionPrimaryFg, backgroundColor: colors.actionPrimary),
      ),
      iconButtonUnselectedData: IconButtonData(style: IconButton.styleFrom(foregroundColor: colors.iconMuted)),
    ),
  );
}

/// Plain text extracted from a Quill [Document], without the trailing newline.
String plainTextFromQuillDocument(Document document) {
  final raw = document.toPlainText();
  if (raw.endsWith('\n')) {
    return raw.substring(0, raw.length - 1);
  }
  return raw;
}

/// Delta JSON for persistence, or `null` when the document is effectively empty.
List<dynamic>? richDeltaFromQuillDocument(Document document) {
  final delta = document.toDelta().toJson();
  if (richDeltaIsEffectivelyEmpty(delta)) {
    return null;
  }
  return delta;
}

/// Builds a [QuillController] from a stored delta or plain-text fallback.
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
    setQuillControllerPlainText(controller, plainText);
  }
  return controller;
}

/// Replaces the controller document from a stored delta or plain-text fallback.
void setQuillControllerFromDraft(QuillController controller, List<dynamic>? deltaJson, String plainText) {
  if (!richDeltaIsEffectivelyEmpty(deltaJson)) {
    controller.document = Document.fromJson(deltaJson!);
    return;
  }
  setQuillControllerPlainText(controller, plainText);
}

/// Replaces all content in [controller] with [plainText].
void setQuillControllerPlainText(QuillController controller, String plainText) {
  final current = controller.plainTextEditingValue.text;
  final deleteLen = current.isEmpty ? 0 : current.length - 1;
  controller.replaceText(0, deleteLen, plainText, TextSelection.collapsed(offset: plainText.length));
}

/// Application-owned rich-text editor with a minimal formatting toolbar.
class AppRichTextEditor extends StatefulWidget {
  const AppRichTextEditor({
    this.controller,
    this.focusNode,
    this.onChanged,
    this.placeholder,
    this.id,
    this.size = AppInputSize.md,
    this.minLines = 3,
    this.autoGrow = false,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    super.key,
  });

  final QuillController? controller;
  final FocusNode? focusNode;
  final AppRichTextChanged? onChanged;
  final String? placeholder;
  final String? id;
  final AppInputSize size;
  final int minLines;
  final bool autoGrow;
  final bool invalid;
  final bool disabled;
  final bool readOnly;

  @override
  State<AppRichTextEditor> createState() => _AppRichTextEditorState();
}

class _AppRichTextEditorState extends State<AppRichTextEditor> {
  QuillController? _ownedController;
  late final FocusNode _focusNode;
  var _ownsFocusNode = false;
  var _focused = false;

  QuillController get _controller => widget.controller ?? _ownedController!;

  bool get _enabled => !widget.disabled && !widget.readOnly;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownedController = QuillController.basic();
    }
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
    _controller.addListener(_handleDocumentChange);
    _controller.readOnly = widget.readOnly || widget.disabled;
  }

  @override
  void didUpdateWidget(covariant AppRichTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.readOnly = widget.readOnly || widget.disabled;
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    _controller.removeListener(_handleDocumentChange);
    _ownedController?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _focusNode.hasFocus;
    if (focused != _focused) {
      setState(() => _focused = focused);
    }
  }

  void _handleDocumentChange() {
    widget.onChanged?.call(
      plainTextFromQuillDocument(_controller.document),
      richDeltaFromQuillDocument(_controller.document),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final minHeight = _editorMinHeight(widget.size, widget.minLines);
    final padding = _editorContentPadding(widget.size);
    final toolbarConfig = _toolbarConfig(context, widget.size);
    final bodyStyle = appBareInputTextStyle(context, widget.size, disabled: widget.disabled).copyWith(height: 1.5);

    final editorConfig = QuillEditorConfig(
      placeholder: widget.placeholder,
      padding: padding,
      minHeight: widget.autoGrow ? null : minHeight - padding.vertical,
      scrollable: !widget.autoGrow,
      customStyles: _editorStyles(context, widget.size, disabled: widget.disabled),
    );

    final editor = QuillEditor.basic(focusNode: _focusNode, controller: _controller, config: editorConfig);

    final editorPane = DefaultTextStyle(
      style: bodyStyle,
      child: widget.autoGrow
          ? ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: editor,
            )
          : SizedBox(height: minHeight, child: editor),
    );

    return Semantics(
      identifier: widget.id,
      textField: true,
      readOnly: widget.readOnly,
      enabled: !widget.disabled,
      child: Localizations(
        locale: Localizations.localeOf(context),
        delegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standardCurve,
          decoration: appInputDecoration(
            context,
            size: widget.size,
            invalid: widget.invalid,
            disabled: widget.disabled,
            readOnly: widget.readOnly,
            focused: _focused,
          ),
          clipBehavior: Clip.antiAlias,
          child: IgnorePointer(
            ignoring: !_enabled,
            child: Opacity(
              opacity: widget.disabled ? 0.55 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceSunken,
                      border: Border(bottom: BorderSide(color: colors.borderDefault)),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: QuillSimpleToolbar(controller: _controller, config: toolbarConfig),
                    ),
                  ),
                  editorPane,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
