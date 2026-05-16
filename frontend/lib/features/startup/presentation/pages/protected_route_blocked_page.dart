import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_routes.dart';
import '../providers/startup_notifier.dart';
import '../widgets/connection_status_card.dart';
import '../widgets/startup_scaffold.dart';

/// Explanation screen used when someone tries to open a protected route too early.
class ProtectedRouteBlockedPage extends ConsumerWidget {
  const ProtectedRouteBlockedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupNotifierProvider);
    final notifier = ref.read(startupNotifierProvider.notifier);

    return StartupScaffold(
      title: 'Protected route blocked',
      subtitle: 'Navigation guards are active: protected destinations cannot open before authenticated context exists.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConnectionStatusCard(
            title: 'Why you were redirected',
            lines: [
              startup.blockedReason ?? 'Protected routes stay unavailable until authenticated flows are implemented.',
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              notifier.acknowledgeProtectedRouteBlock();
              context.go(AppRoutes.startupEntry);
            },
            child: const Text('Return to startup'),
          ),
        ],
      ),
    );
  }
}
