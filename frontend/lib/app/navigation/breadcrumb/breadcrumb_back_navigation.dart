import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_provider.dart';

/// Back navigation aligned with breadcrumb parent segments.
extension BreadcrumbBackNavigation on BuildContext {
  /// Pops if possible; else navigates to breadcrumb parent; else [fallback].
  void navigateBack({VoidCallback? fallback}) {
    if (canPop()) {
      pop();
      return;
    }

    final trail = ProviderScope.containerOf(this).read(breadcrumbTrailProvider);
    final parent = trail.parent;
    if (parent != null) {
      if (parent.onNavigate != null) {
        parent.onNavigate!(this);
        return;
      }
      final location = parent.targetLocation;
      if (location != null) {
        go(location);
        return;
      }
    }

    fallback?.call();
  }
}
