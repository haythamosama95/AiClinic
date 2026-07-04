import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/shifts/presentation/providers/shift_calendar_provider.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_calendar_panel.dart';

/// Branch shift calendar (`/shifts/calendar`) — week and month views (V1-7 US2).
class ShiftCalendarPage extends ConsumerStatefulWidget {
  const ShiftCalendarPage({super.key});

  @override
  ConsumerState<ShiftCalendarPage> createState() => _ShiftCalendarPageState();
}

class _ShiftCalendarPageState extends ConsumerState<ShiftCalendarPage> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final firstDayOfWeekIndex = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(shiftCalendarProvider.notifier).setFirstDayOfWeekIndex(firstDayOfWeekIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessShiftCalendar(auth)) {
      return const AppEmptyState(
        key: Key('shift_calendar_permission_denied'),
        variant: AppEmptyStateVariant.noAccess,
        title: 'Shift calendar',
        description: 'You must be assigned to a branch to view the shift calendar.',
      );
    }

    final canManage = ref.watch(permissionServiceProvider).canManageShifts();

    return CalendarQueuePattern(
      view: CalendarQueueView.calendar,
      onViewChanged: (_) {},
      viewSwitchSemanticLabel: 'Shift schedule view',
      toolbarStart: const AppPageHeader(
        title: 'Shift calendar',
        description: 'Weekly and monthly views for branch shift coverage.',
      ),
      toolbarEnd: canManage
          ? AppButton(
              key: const Key('shift_calendar_create_fab'),
              label: 'Create shift',
              leadingIcon: LucideIcons.plus,
              size: AppButtonSize.sm,
              onPressed: () async {
                await context.push(AppRoutes.shiftsNew);
                if (!context.mounted) {
                  return;
                }
                unawaited(ref.read(shiftCalendarProvider.notifier).refresh());
              },
            )
          : null,
      calendarHeader: const SizedBox.shrink(),
      calendar: ShiftCalendarPanel(
        onCreateTap: canManage
            ? () async {
                await context.push(AppRoutes.shiftsNew);
                if (!context.mounted) {
                  return;
                }
                unawaited(ref.read(shiftCalendarProvider.notifier).refresh());
              }
            : null,
      ),
      queueColumns: const [],
    );
  }
}
