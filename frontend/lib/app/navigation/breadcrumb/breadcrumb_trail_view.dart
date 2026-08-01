import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_provider.dart';
import 'package:ai_clinic/core/ui/components/app_breadcrumb.dart';

/// Shell vs in-page breadcrumb rendering mode.
enum BreadcrumbViewMode { shell, inPage }

/// Renders the current [breadcrumbTrailProvider] trail via [AppBreadcrumb].
class BreadcrumbTrailView extends ConsumerWidget {
  const BreadcrumbTrailView({super.key, this.mode = BreadcrumbViewMode.inPage});

  final BreadcrumbViewMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trail = ref.watch(breadcrumbTrailProvider);
    if (trail.entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return AppBreadcrumb(items: _resolveItems(context, trail));
  }

  List<AppBreadcrumbItem> _resolveItems(BuildContext context, BreadcrumbTrail trail) {
    final currentId = trail.current?.id;
    return [
      for (final entry in trail.entries)
        AppBreadcrumbItem(
          label: entry.label.resolve(context),
          onTap: entry.id == currentId ? null : () => _navigateEntry(context, entry),
        ),
    ];
  }

  void _navigateEntry(BuildContext context, BreadcrumbEntry entry) {
    if (entry.onNavigate != null) {
      entry.onNavigate!(context);
      return;
    }
    final location = entry.targetLocation;
    if (location != null) {
      context.go(location);
    }
  }
}
