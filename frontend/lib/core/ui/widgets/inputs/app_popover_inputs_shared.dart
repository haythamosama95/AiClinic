import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Resolves `ar-EG` or `en-GB` for house date/time formatting.
String appInputIntlLocale(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  return code == 'ar' ? 'ar-EG' : 'en-GB';
}

/// Whether the ambient locale is Arabic.
bool appInputIsArabic(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'ar';
}

/// Scrollable scaffold for popover option lists (select, autocomplete, time).
class AppPopoverListPanel extends StatelessWidget {
  const AppPopoverListPanel({
    required this.child,
    this.maxHeight = 240,
    this.padding = const EdgeInsets.symmetric(vertical: AppSpacing.s1),
    super.key,
  });

  final Widget child;
  final double maxHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: padding,
        child: child,
      ),
    );
  }
}

/// Shared row for single-select and combobox option lists.
class AppPopoverOptionRow extends StatelessWidget {
  const AppPopoverOptionRow({
    required this.label,
    required this.onTap,
    this.highlighted = false,
    this.selected = false,
    this.showCheck = false,
    this.disabled = false,
    this.disabledReason,
    this.icon,
    this.meta,
    this.avatarUrl,
    this.initials,
    this.labelWidget,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool selected;
  final bool showCheck;
  final bool disabled;
  final String? disabledReason;
  final IconData? icon;
  final String? meta;
  final String? avatarUrl;
  final String? initials;
  final Widget? labelWidget;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    final textColor = disabled ? colors.textDisabled : colors.textPrimary;

    return AppPressable.builder(
      enabled: !disabled,
      onTap: onTap,
      semanticLabel: label,
      borderRadius: AppRadii.mdAll,
      builder: (context, states, _) {
        final hovered = states.contains(WidgetState.hovered);
        final bg = selected
            ? colors.surfaceSelected
            : highlighted || hovered
            ? colors.surfaceHover
            : Colors.transparent;

        return AnimatedContainer(
          duration: AppDurations.instant,
          curve: AppEasings.standard,
          color: bg,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.s3,
              vertical: AppSpacing.s2,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  AppIcon(
                    icon: icon!,
                    size: AppIconSize.sm,
                    color: colors.iconMuted,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                ],
                if (avatarUrl != null || initials != null) ...[
                  _AvatarBadge(
                    avatarUrl: avatarUrl,
                    initials: initials,
                  ),
                  const SizedBox(width: AppSpacing.s3),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DefaultTextStyle(
                        style: typography.bodyStrong.copyWith(color: textColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: labelWidget ?? Text(label),
                      ),
                      if (meta != null)
                        Text(
                          meta!,
                          style: typography.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (disabled && disabledReason != null)
                        Text(
                          disabledReason!,
                          style: typography.caption.copyWith(
                            color: colors.statusWarningFg,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (showCheck && selected)
                  AppIcon(
                    icon: LucideIcons.check,
                    size: AppIconSize.sm,
                    color: colors.actionPrimary,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({
    this.avatarUrl,
    this.initials,
  });

  final String? avatarUrl;
  final String? initials;

  static const double _size = AppSpacing.s8;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return ClipOval(
      child: Container(
        width: _size,
        height: _size,
        color: colors.surfaceMuted,
        alignment: Alignment.center,
        child: avatarUrl != null
            ? Image.network(
                avatarUrl!,
                width: _size,
                height: _size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Text(
                  initials ?? '',
                  style: typography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              )
            : Text(
                initials ?? '',
                style: typography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
      ),
    );
  }
}

/// Highlights the first case-insensitive match of [query] inside [text].
class AppHighlightMatch extends StatelessWidget {
  const AppHighlightMatch({
    required this.text,
    required this.query,
    required this.style,
    super.key,
  });

  final String text;
  final String query;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return Text(text, style: style);

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final idx = lowerText.indexOf(lowerQuery);
    if (idx < 0) return Text(text, style: style);

    final colors = context.colors;
    final highlightStyle = style.copyWith(
      backgroundColor: colors.surfaceSelected,
      color: colors.textPrimary,
    );

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(text: text.substring(idx, idx + query.length), style: highlightStyle),
          TextSpan(text: text.substring(idx + query.length)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Empty-state message centered inside a popover list.
class AppPopoverListMessage extends StatelessWidget {
  const AppPopoverListMessage({
    required this.message,
    this.semanticLive = false,
    super.key,
  });

  final String message;
  final bool semanticLive;

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s6,
      ),
      child: Center(
        child: Semantics(
          liveRegion: semanticLive,
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: typography.bodySm.copyWith(color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// Link-styled action row at the top of multi-select lists.
class AppPopoverListAction extends StatelessWidget {
  const AppPopoverListAction({
    required this.label,
    required this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return AppPressable.builder(
      onTap: onTap,
      borderRadius: AppRadii.mdAll,
      semanticLabel: label,
      builder: (context, states, _) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: AppDurations.instant,
          color: hovered ? context.colors.surfaceHover : Colors.transparent,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s2,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              label,
              style: typography.body.copyWith(color: colors.textLink),
            ),
          ),
        );
      },
    );
  }
}

/// Chevron that rotates when a popover is open.
class AppPopoverChevron extends StatelessWidget {
  const AppPopoverChevron({
    required this.open,
    super.key,
  });

  final bool open;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: open ? 0.5 : 0,
      duration: AppMotion.reduced(context) ? AppDurations.instant : AppDurations.fast,
      curve: AppEasings.standard,
      child: AppIcon(
        icon: LucideIcons.chevronDown,
        size: AppIconSize.sm,
        color: context.colors.iconMuted,
      ),
    );
  }
}
