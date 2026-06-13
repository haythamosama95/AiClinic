import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_notifier.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Full-screen blocking overlay shown while dev dummy clinic data is being seeded.
class DevClinicSeedOverlay extends ConsumerWidget {
  const DevClinicSeedOverlay({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = ref.watch(devClinicSeedProvider);
    if (!seed.inProgress) {
      return child;
    }

    final colors = context.semanticColors;

    return Stack(
      fit: StackFit.expand,
      children: [
        AbsorbPointer(absorbing: true, child: child),
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ColoredBox(color: colors.background.withValues(alpha: 0.72)),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(SpacingTokens.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: SpacingTokens.md),
                        Text(
                          'Filling dummy clinic data',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        if (seed.progressMessage case final message?) ...[
                          const SizedBox(height: SpacingTokens.sm),
                          Text(
                            message,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
