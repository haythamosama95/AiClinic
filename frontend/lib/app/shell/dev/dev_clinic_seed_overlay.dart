import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_notifier.dart';

/// Dev-only overlay hook; blocks interaction while seeding without custom chrome.
class DevClinicSeedOverlay extends ConsumerWidget {
  const DevClinicSeedOverlay({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = ref.watch(devClinicSeedProvider);
    if (!seed.inProgress) {
      return child;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        AbsorbPointer(absorbing: true, child: child),
        const ColoredBox(
          color: Color(0xB3000000),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}
