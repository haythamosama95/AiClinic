import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/settings/presentation/screens/_empty_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return EmptySettingsScreen(
      icon: Icons.notifications,
      title: 'Notifications',
      description: 'Control how your team receives alerts and reminders.',
      body: AppCard(
        variant: CardVariant.flat,
        padding: CardPadding.lg,
        child: Center(
          child: Text(
            'Notification preferences will be configurable in a future release.',
            textAlign: TextAlign.center,
            style: AppTypography.body(context).copyWith(color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}
