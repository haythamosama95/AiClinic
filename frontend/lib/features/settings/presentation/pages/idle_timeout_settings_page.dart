import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';
import 'package:ai_clinic/features/settings/presentation/providers/idle_timeout_settings_notifier.dart';

/// Configures how long the app waits before idle sign-out on this workstation.
class IdleTimeoutSettingsPage extends ConsumerStatefulWidget {
  const IdleTimeoutSettingsPage({super.key});

  @override
  ConsumerState<IdleTimeoutSettingsPage> createState() => _IdleTimeoutSettingsPageState();
}

class _IdleTimeoutSettingsPageState extends ConsumerState<IdleTimeoutSettingsPage> {
  final _customMinutesController = TextEditingController();

  @override
  void dispose() {
    ref.read(idleTimeoutSettingsProvider.notifier).clearSaveMessage();
    _customMinutesController.dispose();
    super.dispose();
  }

  Future<void> _saveCustom() async {
    await ref.read(idleTimeoutSettingsProvider.notifier).saveCustomMinutes(_customMinutesController.text);
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(idleTimeoutSettingsProvider);

    ref.listen<AsyncValue<IdleTimeoutSettingsState>>(idleTimeoutSettingsProvider, (previous, next) {
      final value = next.value;
      if (value?.saveMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value!.saveMessage!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Idle sign-out'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.settings)),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load settings: $error')),
        data: (settings) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Shared clinic workstations sign out automatically when there is no keyboard or mouse activity in the app window.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Current timeout: ${IdleTimeoutConfig.formatDuration(settings.duration)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 24),
                Text('Quick presets', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final minutes in IdleTimeoutConfig.presetMinutes)
                      ChoiceChip(
                        label: Text('$minutes min'),
                        selected: settings.duration.inMinutes == minutes,
                        onSelected: settings.isSaving
                            ? null
                            : (_) => ref.read(idleTimeoutSettingsProvider.notifier).selectPresetMinutes(minutes),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Custom duration', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _customMinutesController,
                  decoration: InputDecoration(
                    labelText: 'Minutes',
                    helperText: 'Between ${IdleTimeoutConfig.minMinutes} and ${IdleTimeoutConfig.maxMinutes} minutes',
                    border: const OutlineInputBorder(),
                    errorText: settings.errorMessage,
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !settings.isSaving,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: settings.isSaving ? null : _saveCustom,
                  child: settings.isSaving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save custom timeout'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
