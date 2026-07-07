import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_divider.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Bordered list container (web `List`).
class AppList extends StatelessWidget {
  const AppList({
    required this.children,
    this.divided = true,
    this.ariaLabel,
    super.key,
  });

  final List<Widget> children;
  final bool divided;
  final String? ariaLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      container: true,
      label: ariaLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          border: Border.all(color: colors.borderDefault),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (divided && i > 0) const AppDivider(),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Row inside [AppList] (web `ListItem`).
class AppListItem extends StatelessWidget {
  const AppListItem({
    required this.primary,
    this.leading,
    this.secondary,
    this.trailing,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final Widget? leading;
  final Widget primary;
  final Widget? secondary;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final interactive = onTap != null;

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space3,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            Semantics(container: true, child: leading!),
            const SizedBox(width: AppSpacing.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle(
                  style: AppTypography.body(context).copyWith(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: primary,
                ),
                if (secondary != null) ...[
                  const SizedBox(height: AppSpacing.space05),
                  DefaultTextStyle(
                    style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: secondary!,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.space3),
            Semantics(container: true, child: trailing!),
          ],
        ],
      ),
    );

    if (!interactive) {
      return Semantics(
        container: true,
        selected: selected,
        child: ColoredBox(
          color: selected ? colors.surfaceSelected : Colors.transparent,
          child: content,
        ),
      );
    }

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            onTap?.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Material(
          color: selected ? colors.surfaceSelected : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: colors.surfaceHover,
            focusColor: colors.surfaceHover,
            child: content,
          ),
        ),
      ),
    );
  }
}
