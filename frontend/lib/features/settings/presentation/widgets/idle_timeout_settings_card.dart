import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/application/idle_timeout_settings_notifier.dart';
import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_section_card.dart';

const _customTimeoutSentinel = -1;

/// Workstation idle sign-out duration: presets and custom minutes.
class IdleTimeoutSettingsCard extends ConsumerStatefulWidget {
  const IdleTimeoutSettingsCard({super.key});

  @override
  ConsumerState<IdleTimeoutSettingsCard> createState() => _IdleTimeoutSettingsCardState();
}

class _IdleTimeoutSettingsCardState extends ConsumerState<IdleTimeoutSettingsCard> {
  final _customMinutesController = TextEditingController();
  bool _customMode = false;

  static Map<String, int> get _timeoutItems => {
    for (final minutes in IdleTimeoutConfig.presetMinutes) '$minutes min': minutes,
    'Custom': _customTimeoutSentinel,
  };

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
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    ref.listen<AsyncValue<IdleTimeoutSettingsState>>(idleTimeoutSettingsProvider, (previous, next) {
      final value = next.value;
      if (value != null) {
        _syncCustomMode(value);
      }

      final saveMessage = value?.saveMessage;
      if (saveMessage != null && saveMessage != previous?.value?.saveMessage) {
        AppToast.success(context, message: saveMessage);
        ref.read(idleTimeoutSettingsProvider.notifier).clearSaveMessage();
      }
    });

    return SettingsSectionCard(
      title: 'Idle sign-out',
      child: settingsAsync.when(
        loading: () => const Center(
          child: Padding(padding: EdgeInsets.all(SpacingTokens.lg), child: CircularProgressIndicator()),
        ),
        error: (error, _) => Text(
          'Failed to load settings: $error',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.destructive),
        ),
        data: (settings) {
          final needsCustom = !IdleTimeoutConfig.presetMinutes.contains(settings.duration.inMinutes);
          if (needsCustom && !_customMode) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _syncCustomMode(settings);
            });
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Shared clinic workstations sign out automatically when there is no keyboard or mouse activity in the app window.',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
              ),
              const SizedBox(height: SpacingTokens.md),
              Text(
                'Current timeout: ${IdleTimeoutConfig.formatDuration(settings.duration)}',
                style: theme.textTheme.labelLarge?.copyWith(color: colors.foreground, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: SpacingTokens.lg),
              SettingsFieldsRow(
                children: [
                  AppSelect<int>(
                    label: 'Timeout',
                    items: _timeoutItems,
                    value: _dropdownValue(settings),
                    enabled: !settings.isSaving,
                    onChanged: settings.isSaving ? null : _onTimeoutChanged,
                  ),
                  if (_customMode)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTextInput(
                          label: 'Custom duration',
                          hintText:
                              'Between ${IdleTimeoutConfig.minMinutes} and ${IdleTimeoutConfig.maxMinutes} minutes',
                          controller: _customMinutesController,
                          keyboardType: TextInputType.number,
                          enabled: !settings.isSaving,
                        ),
                        if (settings.errorMessage != null) ...[
                          const SizedBox(height: SpacingTokens.xs),
                          Text(
                            settings.errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(color: colors.destructive),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
              if (_customMode) ...[
                const SizedBox(height: SpacingTokens.md),
                AppButton(
                  label: 'Save',
                  expand: true,
                  isLoading: settings.isSaving,
                  onPressed: settings.isSaving ? null : _saveCustom,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
