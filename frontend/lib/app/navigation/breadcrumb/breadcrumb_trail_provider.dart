import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_label.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_resolver.dart';

class BreadcrumbTrailNotifier extends Notifier<BreadcrumbTrail> {
  String? _lastSyncedLocation;

  @override
  BreadcrumbTrail build() => BreadcrumbTrail.empty;

  bool needsSyncForLocation(String location) => _lastSyncedLocation != location;

  void syncFromRoute(GoRouterState routerState) {
    final location = routerState.uri.path;
    if (!needsSyncForLocation(location)) {
      return;
    }
    _lastSyncedLocation = location;

    final fromExtra = BreadcrumbTrailResolver.fromExtra(routerState.extra);
    final resolved = fromExtra ?? BreadcrumbTrailResolver.canonicalFor(location, uri: routerState.uri);
    state = resolved.mergePreservedLabelsFrom(state);
  }

  void setTrail(BreadcrumbTrail trail, {String? syncedLocation}) {
    state = trail;
    if (syncedLocation != null) {
      _lastSyncedLocation = syncedLocation;
    }
  }

  void updateEntryLabel(String entryId, BreadcrumbLabel label) {
    state = state.updateLabel(entryId, label);
  }
}

final breadcrumbTrailProvider = NotifierProvider<BreadcrumbTrailNotifier, BreadcrumbTrail>(BreadcrumbTrailNotifier.new);

/// Syncs the breadcrumb notifier from the current [GoRouterState].
void syncBreadcrumbFromRoute(GoRouterState state, WidgetRef ref) {
  final notifier = ref.read(breadcrumbTrailProvider.notifier);
  if (!notifier.needsSyncForLocation(state.uri.path)) {
    return;
  }

  SchedulerBinding.instance.scheduleFrameCallback((_) {
    ref.read(breadcrumbTrailProvider.notifier).syncFromRoute(state);
  });
}

/// Defers breadcrumb mutations until after the current frame (safe from [build]).
void scheduleBreadcrumbEntryLabelUpdate(WidgetRef ref, String entryId, BreadcrumbLabel label) {
  SchedulerBinding.instance.scheduleFrameCallback((_) {
    ref.read(breadcrumbTrailProvider.notifier).updateEntryLabel(entryId, label);
  });
}

/// Defers breadcrumb trail replacement until after the current frame (safe from [build]).
void scheduleBreadcrumbTrailUpdate(WidgetRef ref, BreadcrumbTrail trail, {String? syncedLocation}) {
  SchedulerBinding.instance.scheduleFrameCallback((_) {
    ref.read(breadcrumbTrailProvider.notifier).setTrail(trail, syncedLocation: syncedLocation);
  });
}
