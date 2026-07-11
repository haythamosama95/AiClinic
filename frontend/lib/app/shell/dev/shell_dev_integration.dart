import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_notifier.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_overlay.dart';

/// Single integration surface for debug-only shell tooling.
///
/// Production code should import only this file from `lib/app/shell/dev/`.
///
/// **Removal:** delete the entire `lib/app/shell/dev/` directory, then remove:
/// - [ShellDevShellWrapper] in [AuthenticatedShell]
/// - [shellDevListenForRouterRefresh] and [shellDevSuppressAuthRedirect] in [appRouterProvider]
/// - [ShellDevNavFooter] call site in [ShellNav] (and dev entries in [ShellNavConfig])
abstract final class ShellDevIntegration {
  const ShellDevIntegration._();
}

/// Wraps authenticated shell content with dev-only blocking overlays (debug builds).
class ShellDevShellWrapper extends ConsumerWidget {
  const ShellDevShellWrapper({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) {
      return child;
    }

    return DevClinicSeedOverlay(child: child);
  }
}

/// Subscribes router refresh to dev seed progress (no-op outside debug builds).
void shellDevListenForRouterRefresh(Ref ref, VoidCallback onChanged) {
  if (!kDebugMode) {
    return;
  }

  ref.listen<DevClinicSeedState>(devClinicSeedProvider, (_, _) => onChanged());
}

/// When true, auth redirects are suppressed so in-place dev seeding is not interrupted.
bool shellDevSuppressAuthRedirect(Ref ref, AuthSessionState auth) {
  if (!kDebugMode || !auth.isAuthenticated) {
    return false;
  }

  return ref.read(devClinicSeedProvider).inProgress;
}
