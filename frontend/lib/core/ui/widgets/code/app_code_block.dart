import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/_button_shared.dart';

/// Sunken mono block for IDs, raw payloads, and AI output with copy support.
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
  static const _copiedResetDelay = Duration(seconds: 2);

  bool _copied = false;

  Future<void> _handleCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(_copiedResetDelay);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: colors.borderDefault),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.language != null) _LanguageHeader(label: widget.language!),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      widget.code,
                      style: typography.mono.copyWith(color: colors.textPrimary),
                    ),
                  ),
                ),
              ),
            ],
          ),
          PositionedDirectional(
            end: AppSpacing.s2,
            top: AppSpacing.s2,
            child: _CopyButton(copied: _copied, onPressed: _handleCopy),
          ),
        ],
      ),
    );
  }
}

class _LanguageHeader extends StatelessWidget {
  const _LanguageHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s2,
        ),
        child: Text(
          label,
          style: typography.caption.copyWith(color: colors.textTertiary),
        ),
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({
    required this.copied,
    required this.onPressed,
  });

  final bool copied;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = copied ? 'Copied' : 'Copy';
    final semanticLabel = copied ? 'Copied' : 'Copy code';

    return AppPressable.builder(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      borderRadius: AppRadii.mdAll,
      builder: (context, states, _) {
        final background = AppButtonShared.background(
          colors,
          AppButtonVariant.ghost,
          states,
          disabled: false,
        );
        final foreground = AppButtonShared.foreground(
          colors,
          AppButtonVariant.ghost,
          states,
          disabled: false,
        );

        return AnimatedContainer(
          duration: AppDurations.instant,
          curve: AppEasings.standard,
          height: AppButtonShared.height(AppButtonSize.sm),
          padding: AppButtonShared.padding(AppButtonSize.sm, AppButtonVariant.ghost),
          decoration: AppButtonShared.decoration(
            background: background,
            borderRadius: AppRadii.mdAll,
            colors: colors,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppFadeScale(
                key: ValueKey<bool>(copied),
                child: AppIcon(
                  icon: copied ? LucideIcons.check : LucideIcons.copy,
                  dimension: AppButtonShared.iconDimension(AppButtonSize.sm),
                  color: foreground,
                ),
              ),
              SizedBox(width: AppButtonShared.gap(AppButtonSize.sm)),
              Text(
                label,
                style: AppButtonShared.textStyle(context, AppButtonSize.sm)
                    .copyWith(color: foreground),
              ),
            ],
          ),
        );
      },
    );
  }
}
