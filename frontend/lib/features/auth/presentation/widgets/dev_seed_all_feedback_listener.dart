import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/auth/presentation/dev/dev_seed_all_runner.dart';

/// Shows a snackbar when [devSeedAllFeedbackProvider] is set (e.g. after bootstrap redirect).
class DevSeedAllFeedbackListener extends ConsumerWidget {
  const DevSeedAllFeedbackListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<DevSeedAllOutcome?>(devSeedAllFeedbackProvider, (previous, next) {
      if (next == null || !context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next.summaryLines.join('\n')),
          duration: next.isSuccess ? const Duration(seconds: 6) : const Duration(seconds: 4),
        ),
      );
      ref.read(devSeedAllFeedbackProvider.notifier).clear();
    });

    return child;
  }
}
