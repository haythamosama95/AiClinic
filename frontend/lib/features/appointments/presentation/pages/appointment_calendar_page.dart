import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/dev_seed_doctors_button.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

class AppointmentCalendarPage extends ConsumerStatefulWidget {
  const AppointmentCalendarPage({super.key});

  @override
  ConsumerState<AppointmentCalendarPage> createState() => _AppointmentCalendarPageState();
}

class _AppointmentCalendarPageState extends ConsumerState<AppointmentCalendarPage> {
  int _doctorFilterReloadToken = 0;

  @override
  Widget build(BuildContext context) {
    final canAccess = ref.watch(permissionServiceProvider).canAccessAppointments();
    final state = ref.watch(appointmentCalendarProvider);
    final controller = ref.read(appointmentCalendarProvider.notifier);

    if (!canAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('Appointment calendar')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to view appointments.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointment calendar'),
        actions: [DevSeedDoctorsButton(onSeeded: _reloadDoctorFilter)],
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.nav.popOrHome(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<AppointmentCalendarMode>(
                  segments: const [
                    ButtonSegment(value: AppointmentCalendarMode.day, label: Text('Day')),
                    ButtonSegment(value: AppointmentCalendarMode.week, label: Text('Week')),
                  ],
                  selected: {state.mode},
                  onSelectionChanged: (selection) => controller.setMode(selection.first),
                ),
                OutlinedButton.icon(
                  key: const Key('appointments_calendar_prev'),
                  onPressed: controller.previousPeriod,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Previous'),
                ),
                OutlinedButton.icon(
                  key: const Key('appointments_calendar_next'),
                  onPressed: controller.nextPeriod,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next'),
                ),
                FilledButton.tonal(
                  key: const Key('appointments_calendar_today'),
                  onPressed: () => controller.setFocusDate(DateTime.now()),
                  child: const Text('Today'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_rangeLabel(context, state.focusDate, state.mode), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _DoctorFilter(
              selectedDoctorId: state.selectedDoctorId,
              onChanged: controller.setDoctorFilter,
              reloadToken: _doctorFilterReloadToken,
            ),
            const SizedBox(height: 16),
            if (state.loading) const Center(child: CircularProgressIndicator()),
            if (!state.loading && state.error != null) ...[
              Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: controller.refresh, child: const Text('Retry')),
            ],
            if (!state.loading && state.error == null && state.items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text('No appointments in this range.', textAlign: TextAlign.center),
              ),
            if (!state.loading && state.items.isNotEmpty) ...state.items.map((item) => _AppointmentTile(item: item)),
          ],
        ),
      ),
    );
  }

  void _reloadDoctorFilter() {
    setState(() => _doctorFilterReloadToken++);
  }

  String _rangeLabel(BuildContext context, DateTime focus, AppointmentCalendarMode mode) {
    final localizations = MaterialLocalizations.of(context);
    final day = DateTime(focus.year, focus.month, focus.day);
    if (mode == AppointmentCalendarMode.day) {
      return localizations.formatFullDate(day);
    }
    final start = day.subtract(Duration(days: day.weekday - 1));
    final end = start.add(const Duration(days: 6));
    return '${localizations.formatMediumDate(start)} - ${localizations.formatMediumDate(end)}';
  }
}

class _DoctorFilter extends ConsumerStatefulWidget {
  const _DoctorFilter({required this.selectedDoctorId, required this.onChanged, required this.reloadToken});
  final String? selectedDoctorId;
  final ValueChanged<String?> onChanged;
  final int reloadToken;

  @override
  ConsumerState<_DoctorFilter> createState() => _DoctorFilterState();
}

class _DoctorFilterState extends ConsumerState<_DoctorFilter> {
  late Future<List<StaffListItem>> _doctorsFuture = _loadDoctors();

  @override
  void didUpdateWidget(covariant _DoctorFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) {
      setState(() {
        _doctorsFuture = _loadDoctors();
      });
    }
  }

  Future<List<StaffListItem>> _loadDoctors() async {
    final staff = await ref.read(listStaffUseCaseProvider)(filter: StaffListFilter.active);
    return staff.where((item) => item.role == StaffRole.doctor && item.isActive).toList(growable: false)
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StaffListItem>>(
      future: _doctorsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const InputDecorator(
            decoration: InputDecoration(labelText: 'Doctor filter'),
            child: Text('Loading doctors...'),
          );
        }
        if (snapshot.hasError) {
          return const InputDecorator(
            decoration: InputDecoration(labelText: 'Doctor filter'),
            child: Text('Could not load doctors.'),
          );
        }
        final doctors = snapshot.data ?? const <StaffListItem>[];
        return DropdownButtonFormField<String?>(
          key: const Key('appointments_calendar_doctor_filter'),
          initialValue: widget.selectedDoctorId,
          decoration: const InputDecoration(labelText: 'Doctor filter'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('All doctors')),
            for (final doctor in doctors) DropdownMenuItem<String?>(value: doctor.id, child: Text(doctor.fullName)),
          ],
          onChanged: widget.onChanged,
        );
      },
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({required this.item});

  final AppointmentListItem item;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final start = item.startTime.toLocal();
    final end = item.endTime.toLocal();
    final startLabel = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(start));
    final endLabel = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(end));
    return Card(
      child: ListTile(
        onTap: () => context.nav.pushPatientDetail(item.patientId),
        title: Text(item.patientName),
        subtitle: Text('$startLabel - $endLabel  |  ${item.doctorDisplayName}'),
        trailing: Wrap(
          spacing: 8,
          children: [
            Chip(label: Text(_typeLabel(item.type))),
            Chip(label: Text(_statusLabel(item.status))),
          ],
        ),
      ),
    );
  }

  String _typeLabel(AppointmentType type) {
    return switch (type) {
      AppointmentType.planned => 'Planned',
      AppointmentType.walkIn => 'Walk-in',
    };
  }

  String _statusLabel(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.scheduled => 'Scheduled',
      AppointmentStatus.checkedIn => 'Checked in',
      AppointmentStatus.inProgress => 'In progress',
      AppointmentStatus.completed => 'Completed',
      AppointmentStatus.cancelled => 'Cancelled',
      AppointmentStatus.noShow => 'No-show',
    };
  }
}
