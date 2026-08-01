import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/settings/application/idle_timeout_settings_notifier.dart';
import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';
import 'package:ai_clinic/features/settings/presentation/components/settings_screen_primitives.dart';

/// Workstation security preferences (web `SecurityScreen`).
class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idleState = ref.watch(idleTimeoutSettingsProvider);
    final colors = context.appColors;

    return SettingsScreenScaffold(
      header: const SettingsScreenHeader(
        icon: Icons.shield_outlined,
        title: 'Security',
        description: 'Protect this workstation when you step away from the desk.',
      ),
      panel: idleState.when(
        data: (state) {
          final minutes = state.duration.inMinutes;
          return SettingsContentPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(Icons.schedule_outlined, size: 20, color: colors.textLink),
                      ),
                      const SizedBox(width: AppSpacing.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Idle sign-out duration',
                              style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
                            ),
                            const SizedBox(height: AppSpacing.space1),
                            Text(
                              'Applies to this browser workstation.',
                              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space6),
                  Wrap(
                    spacing: AppSpacing.space2,
                    runSpacing: AppSpacing.space2,
                    children: [
                      for (final preset in IdleTimeoutConfig.presetMinutes)
                        _IdleTimeoutPresetButton(
                          minutes: preset,
                          selected: minutes == preset,
                          onPressed: state.isSaving
                              ? null
                              : () => ref.read(idleTimeoutSettingsProvider.notifier).selectPresetMinutes(preset),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space6),
                  Text.rich(
                    TextSpan(
                      style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                      children: [
                        const TextSpan(text: 'Current setting: '),
                        TextSpan(
                          text: '$minutes minutes',
                          style: AppTypography.caption(context).copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.textSecondary,
                          ),
                        ),
                        const TextSpan(text: ' of inactivity before sign-out.'),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
        loading: () => const SettingsContentPanel(child: Center(child: CircularProgressIndicator.adaptive())),
        error: (_, _) => const SettingsContentPanel(
          child: Text('Unable to load security settings.'),
        ),
      ),
    );
  }
}

class _IdleTimeoutPresetButton extends StatefulWidget {
  const _IdleTimeoutPresetButton({required this.minutes, required this.selected, this.onPressed});

  final int minutes;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  State<_IdleTimeoutPresetButton> createState() => _IdleTimeoutPresetButtonState();
}

class _IdleTimeoutPresetButtonState extends State<_IdleTimeoutPresetButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selected = widget.selected;
    final enabled = widget.onPressed != null;

    final borderColor = selected
        ? colors.actionPrimary
        : (_hovered && enabled ? colors.textTertiary : colors.borderDefault);
    final background = selected ? colors.actionPrimary.withValues(alpha: 0.1) : Colors.transparent;
    final foreground = selected
        ? colors.textLink
        : (_hovered && enabled ? colors.textPrimary : colors.textSecondary);

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '${widget.minutes} minutes',
      child: MouseRegion(
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space2),
              decoration: BoxDecoration(
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                '${widget.minutes} min',
                style: AppTypography.bodySm(context).copyWith(fontWeight: FontWeight.w500, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
