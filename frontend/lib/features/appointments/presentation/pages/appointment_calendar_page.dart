import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/features/appointments/presentation/controllers/appointment_calendar_fullscreen_controller.dart';
import 'package:ai_clinic/features/appointments/presentation/controllers/appointment_calendar_reschedule_controller.dart';
import 'package:ai_clinic/features/appointments/presentation/controllers/appointment_calendar_reveal_controller.dart';
import 'package:ai_clinic/features/appointments/presentation/controllers/appointment_calendar_sync_controller.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_permission_denied.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_view.dart';

/// Branch appointment calendar with day, week, month, schedule, and doctor timeline views.
class AppointmentCalendarPage extends ConsumerStatefulWidget {
  const AppointmentCalendarPage({super.key});

  @override
  ConsumerState<AppointmentCalendarPage> createState() => _AppointmentCalendarPageState();
}

class _AppointmentCalendarPageState extends ConsumerState<AppointmentCalendarPage> {
  late final AppointmentCalendarSyncController _sync;
  late final AppointmentCalendarRevealController _reveal;
  late final AppointmentCalendarFullscreenController _fullscreen;
  late final AppointmentCalendarRescheduleController _reschedule;

  Color _evenResourceRowColor = Colors.transparent;
  Color _oddResourceRowColor = Colors.transparent;
  Brightness _brightness = Brightness.light;

  @override
  void initState() {
    super.initState();
    _sync = AppointmentCalendarSyncController();
    _reveal = AppointmentCalendarRevealController();
    _fullscreen = AppointmentCalendarFullscreenController();
    _reschedule = AppointmentCalendarRescheduleController(sync: _sync, onChanged: _notifyChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colors = context.appColors;
    _evenResourceRowColor = colors.surfaceCanvas;
    _oddResourceRowColor = colors.surfaceMuted.withValues(alpha: 0.3);
    _brightness = Theme.of(context).brightness;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        (_hostKey.currentState)?.syncFromCurrentState();
      }
    });
  }

  @override
  void dispose() {
    _reveal.dispose();
    _fullscreen.dispose();
    _sync.dispose();
    super.dispose();
  }

  final GlobalKey<AppointmentCalendarPageHostState> _hostKey = GlobalKey();

  void _notifyChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessAppointmentHub(auth)) {
      return const AppointmentCalendarPermissionDenied();
    }

    return AppointmentCalendarPageHost(
      key: _hostKey,
      sync: _sync,
      reveal: _reveal,
      fullscreen: _fullscreen,
      reschedule: _reschedule,
      evenResourceRowColor: _evenResourceRowColor,
      oddResourceRowColor: _oddResourceRowColor,
      brightness: _brightness,
      onChanged: _notifyChanged,
    );
  }
}
