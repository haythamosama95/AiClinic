import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/presentation/placeholder_page.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_reset_notifier.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_notifier.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_overlay.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_nav.dart';
import 'package:ai_clinic/app/shell/navigation/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/navigation/shell_route_meta.dart';

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
  ref.listen<DevClinicResetState>(devClinicResetProvider, (_, _) => onChanged());
}

/// Returns [authenticatedPage] when signed in; otherwise a static shell placeholder
/// during debug scaffold preview so feature pages that assume a session never build.
Widget shellDevGatedPage(BuildContext context, GoRouterState state, {required Widget authenticatedPage}) {
  final auth = ProviderScope.containerOf(context).read(authSessionProvider);
  final location = state.uri.path;
  if (!auth.isAuthenticated &&
      ShellDevNav.isEnabled &&
      ShellNavConfig.shouldUseUnauthenticatedPreviewPlaceholder(location)) {
    final itemId = ShellNavConfig.itemIdForLocation(location) ?? 'home';
    return PlaceholderPage(
      key: ValueKey(location),
      title: ShellRouteMeta.titleFor(itemId),
      description: ShellRouteMeta.descriptionFor(itemId),
    );
  }
  return authenticatedPage;
}

/// When true, auth redirects are suppressed so in-place dev seeding is not interrupted.
bool shellDevSuppressAuthRedirect(Ref ref, AuthSessionState auth) {
  if (!kDebugMode) {
    return false;
  }

  if (ref.read(devClinicResetProvider).inProgress) {
    return true;
  }

  if (!auth.isAuthenticated) {
    return false;
  }

  return ref.read(devClinicSeedProvider).inProgress;
}
