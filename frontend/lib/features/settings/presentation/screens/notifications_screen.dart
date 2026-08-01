import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_switch.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/settings/application/notification_preferences_notifier.dart';
import 'package:ai_clinic/features/settings/domain/notification_preferences.dart';
import 'package:ai_clinic/features/settings/presentation/components/settings_screen_primitives.dart';

/// Notification preference toggles (web `NotificationsScreen`).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static const _items = <({NotificationPreferenceKey key, String title, String description})>[
    (
      key: NotificationPreferenceKey.appointmentReminders,
      title: 'Appointment reminders',
      description: 'Upcoming visits, confirmations, and no-show follow-ups.',
    ),
    (
      key: NotificationPreferenceKey.billingAlerts,
      title: 'Billing alerts',
      description: 'Overdue invoices, payment receipts, and claim status updates.',
    ),
    (
      key: NotificationPreferenceKey.labResults,
      title: 'Lab results',
      description: 'New results ready for review or patient notification.',
    ),
    (
      key: NotificationPreferenceKey.shiftHandoffs,
      title: 'Shift handoffs',
      description: 'End-of-shift summaries and open task reminders.',
    ),
    (
      key: NotificationPreferenceKey.productUpdates,
      title: 'Product updates',
      description: 'New features, maintenance windows, and release notes.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPreferencesProvider);
    final colors = context.appColors;

    return SettingsScreenScaffold(
      header: const SettingsScreenHeader(
        icon: Icons.notifications_outlined,
        title: 'Notifications',
        description: 'Choose which alerts you receive on this workstation. Applies to your account only.',
      ),
      panel: prefs.when(
        data: (state) => SettingsContentPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsDividedRows(
                children: [
                  for (final item in _items)
                    SettingsSettingRow(
                      title: item.title,
                      description: item.description,
                      control: AppSwitch(
                        value: _valueFor(state, item.key),
                        onChanged: (checked) =>
                            ref.read(notificationPreferencesProvider.notifier).setPreference(item.key, checked),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.space6),
              Text(
                'Email and SMS delivery channels will be available when connected to your clinic\'s notification service.',
                style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
        loading: () => const SettingsContentPanel(child: Center(child: CircularProgressIndicator.adaptive())),
        error: (_, _) => const SettingsContentPanel(
          child: Text('Unable to load notification preferences.'),
        ),
      ),
    );
  }

  bool _valueFor(NotificationPreferences prefs, NotificationPreferenceKey key) => switch (key) {
    NotificationPreferenceKey.appointmentReminders => prefs.appointmentReminders,
    NotificationPreferenceKey.billingAlerts => prefs.billingAlerts,
    NotificationPreferenceKey.labResults => prefs.labResults,
    NotificationPreferenceKey.shiftHandoffs => prefs.shiftHandoffs,
    NotificationPreferenceKey.productUpdates => prefs.productUpdates,
  };
}
