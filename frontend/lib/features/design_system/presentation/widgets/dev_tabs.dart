import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_signal.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/dev_section.dart';

/// Underline tabs for the design system dev page (web `Tabs` default variant).
class DevTabs extends StatelessWidget {
  const DevTabs({required this.value, required this.onChanged, super.key});

  final DevSection value;
  final ValueChanged<DevSection> onChanged;

  static const _sections = DevSection.values;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }

        final currentIndex = _sections.indexOf(value);
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          final next = _sections[(currentIndex + 1) % _sections.length];
          onChanged(next);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          final next = _sections[(currentIndex - 1 + _sections.length) % _sections.length];
          onChanged(next);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.borderSubtle))),
        child: Row(
          children: [
            for (final section in _sections) _DevTabItem(section: section, selected: section == value, onTap: () => onChanged(section)),
          ],
        ),
      ),
    );
  }
}

class _DevTabItem extends StatelessWidget {
  const _DevTabItem({required this.section, required this.selected, required this.onTap});

  final DevSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.surfaceHover.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.space4, AppSpacing.space2, AppSpacing.space4, AppSpacing.space3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                section.label,
                style: AppTypography.body(context).copyWith(
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: selected ? colors.textPrimary : colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.space2),
              SizedBox(
                width: 96,
                height: 2,
                child: selected ? const AppSignal(orientation: Axis.horizontal) : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
