import 'package:flutter/material.dart';

import 'package:ai_clinic/core/widgets/app_loading_state.dart';
import 'package:ai_clinic/features/startup/presentation/widgets/startup_scaffold.dart';

/// Splash-like page shown while configuration and connectivity are being checked.
class StartupCheckPage extends StatelessWidget {
  const StartupCheckPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const StartupScaffold(
      title: 'Starting clinic-local bootstrap',
      subtitle: 'AiClinic is validating the local deployment profile and probing shared backend services.',
      child: AppLoadingState(
        title: 'Checking startup requirements',
        message:
            'This safe pre-auth stage keeps protected routes blocked until configuration and connectivity are known.',
      ),
    );
  }
}
