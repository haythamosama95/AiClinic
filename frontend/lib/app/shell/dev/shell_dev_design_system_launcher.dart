import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';

/// Debug-only floating entry point to the design-system showcase (web-reference "Dev" nav).
///
/// Rendered from [MaterialApp.router]'s builder (above the navigator), so it must not use
/// [GoRouter.of], [Tooltip], or [FloatingActionButton] — those require an [Overlay].
class ShellDevDesignSystemLauncher extends ConsumerWidget {
  const ShellDevDesignSystemLauncher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }

    final router = ref.watch(appRouterProvider);
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) {
        if (router.state.matchedLocation == AppRoutes.foundationDemo) {
          return const SizedBox.shrink();
        }

        return Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: Semantics(
              button: true,
              label: 'Open design system showcase',
              child: Material(
                elevation: 4,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(16),
                color: theme.colorScheme.primary,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => router.go(AppRoutes.foundationDemo),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.science_outlined, color: theme.colorScheme.onPrimary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Design System',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
