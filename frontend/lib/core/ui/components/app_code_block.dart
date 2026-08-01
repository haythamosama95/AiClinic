import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Syntax-highlighted-style code panel with language header and copy action (web `CodeBlock`).
class AppCodeBlock extends StatefulWidget {
  const AppCodeBlock({
    required this.code,
    this.language,
    super.key,
  });

  final String code;
  final String? language;

  @override
  State<AppCodeBlock> createState() => _AppCodeBlockState();
}

class _AppCodeBlockState extends State<AppCodeBlock> {
  var _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final codeStyle = AppTypography.mono(context).copyWith(color: colors.textPrimary);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colors.borderDefault),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.language != null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colors.borderSubtle)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.space4,
                      vertical: AppSpacing.space2,
                    ),
                    child: Text(
                      widget.language!,
                      style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                    ),
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.space4),
                  child: appWrapMaterialInput(
                    SelectableText(
                      widget.code,
                      style: codeStyle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        PositionedDirectional(
          end: AppSpacing.space2,
          top: AppSpacing.space2,
          child: Semantics(
            button: true,
            label: _copied ? 'Copied' : 'Copy code',
            child: AppButton(
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: _handleCopy,
              leadingIcon: Icon(_copied ? Icons.check : Icons.content_copy, size: 14),
              child: Text(_copied ? 'Copied' : 'Copy'),
            ),
          ),
        ),
      ],
    );
  }
}
