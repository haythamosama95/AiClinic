import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/settings/application/idle_timeout_settings_notifier.dart';
import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';

const _customTimeoutSentinel = -1;

/// Workstation idle sign-out duration on `/settings/idle-timeout`.
class IdleTimeoutSettingsPage extends ConsumerStatefulWidget {
  const IdleTimeoutSettingsPage({super.key});

  @override
  ConsumerState<IdleTimeoutSettingsPage> createState() => _IdleTimeoutSettingsPageState();
}

class _IdleTimeoutSettingsPageState extends ConsumerState<IdleTimeoutSettingsPage> {
  final _customMinutesController = TextEditingController();
  var _customMode = false;

  static List<AppSelectOption<int>> get _presetOptions => [
    for (final minutes in IdleTimeoutConfig.presetMinutes)
      AppSelectOption(value: minutes, label: '$minutes min'),
    const AppSelectOption(value: _customTimeoutSentinel, label: 'Custom'),
  ];

  @override
  void dispose() {
    _customMinutesController.dispose();
    super.dispose();
  }

  Future<void> _saveCustom() async {
    await ref.read(idleTimeoutSettingsProvider.notifier).saveCustomMinutes(_customMinutesController.text);
  }

  void _syncCustomMode(IdleTimeoutSettingsState settings) {
    final minutes = settings.duration.inMinutes;
    final isCustomDuration = !IdleTimeoutConfig.presetMinutes.contains(minutes);

    if (isCustomDuration) {
      final text = '$minutes';
      if (_customMinutesController.text != text) {
        _customMinutesController.text = text;
      }
      if (!_customMode) {
        setState(() => _customMode = true);
      }
      return;
    }

    if (_customMode) {
      setState(() => _customMode = false);
    }
  }

  int _dropdownValue(IdleTimeoutSettingsState settings) {
    if (_customMode || !IdleTimeoutConfig.presetMinutes.contains(settings.duration.inMinutes)) {
      return _customTimeoutSentinel;
    }
    return settings.duration.inMinutes;
  }

  void _onTimeoutChanged(int? value) {
    if (value == null || value == _customTimeoutSentinel) {
      setState(() => _customMode = true);
      return;
    }

    setState(() => _customMode = false);
    ref.read(idleTimeoutSettingsProvider.notifier).selectPresetMinutes(value);
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(idleTimeoutSettingsProvider);
    final colors = context.colors;
    final typography = context.typography;

    ref.listen<AsyncValue<IdleTimeoutSettingsState>>(idleTimeoutSettingsProvider, (previous, next) {
      final value = next.value;
      if (value != null) {
        _syncCustomMode(value);
      }

      final saveMessage = value?.saveMessage;
      if (saveMessage != null && saveMessage != previous?.value?.saveMessage) {
        ref.showAppToast(message: saveMessage, variant: AppToastVariant.success);
        ref.read(idleTimeoutSettingsProvider.notifier).clearSaveMessage();
      }
    });

    return ColoredBox(
      color: colors.surfaceCanvas,
      child: settingsAsync.when(
        loading: () => const Center(child: AppSpinner()),
        error: (error, _) => Center(
          child: AppErrorState(
            message: 'Failed to load settings: $error',
            onRetry: () => ref.invalidate(idleTimeoutSettingsProvider),
          ),
        ),
        data: (settings) {
          final needsCustom = !IdleTimeoutConfig.presetMinutes.contains(settings.duration.inMinutes);
          if (needsCustom && !_customMode) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _syncCustomMode(settings);
            });
          }

          return EditorFormPattern(
            title: 'Idle sign-out',
            description:
                'This workstation signs out automatically when there is no keyboard or mouse activity in the app window.',
            breadcrumb: AppBreadcrumb(
              items: [
                AppBreadcrumbItem(label: 'Settings', onTap: () => context.nav.goSettings()),
                const AppBreadcrumbItem(label: 'Idle sign-out'),
              ],
            ),
            summaryAlert: settings.errorMessage == null
                ? null
                : AppAlert(variant: AppAlertVariant.danger, title: settings.errorMessage!),
            sections: [
              EditorFormSection(
                title: 'Timeout duration',
                description: 'The timeout applies only on this device.',
                fields: [
                  Text(
                    'Current timeout: ${IdleTimeoutConfig.formatDuration(settings.duration)}',
                    style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  AppFormField(
                    label: 'Timeout',
                    child: AppSelect<int>(
                      options: _presetOptions,
                      value: _dropdownValue(settings),
                      disabled: settings.isSaving,
                      onChanged: settings.isSaving ? null : _onTimeoutChanged,
                    ),
                  ),
                  if (_customMode) ...[
                    const SizedBox(height: AppSpacing.s4),
                    AppFormField(
                      label: 'Custom duration',
                      hint:
                          'Between ${IdleTimeoutConfig.minMinutes} and ${IdleTimeoutConfig.maxMinutes} minutes',
                      child: AppTextField(
                        controller: _customMinutesController,
                        hintText: 'Minutes',
                        disabled: settings.isSaving,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            footer: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton(
                  label: 'Back to settings',
                  variant: AppButtonVariant.secondary,
                  disabled: settings.isSaving,
                  onPressed: () => context.nav.goSettings(),
                ),
                if (_customMode) ...[
                  const SizedBox(width: AppSpacing.s3),
                  AppButton(
                    label: 'Save',
                    loading: settings.isSaving,
                    onPressed: settings.isSaving ? null : _saveCustom,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
