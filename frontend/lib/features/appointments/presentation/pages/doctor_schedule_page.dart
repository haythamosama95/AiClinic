import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

/// Doctor-focused calendar view for `/appointments/schedule/:doctorId`.
class DoctorSchedulePage extends ConsumerStatefulWidget {
  const DoctorSchedulePage({required this.doctorId, super.key});

  final String doctorId;

  @override
  ConsumerState<DoctorSchedulePage> createState() => _DoctorSchedulePageState();
}

class _DoctorSchedulePageState extends ConsumerState<DoctorSchedulePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = widget.doctorId.trim();
      ref.read(appointmentCalendarProvider.notifier).setDoctorFilter(id.isEmpty ? null : id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final doctors = ref.watch(appointmentCalendarDoctorsProvider).maybeWhen(
      data: (items) => items,
      orElse: () => const <StaffListItem>[],
    );
    final doctorName = doctors
        .where((doctor) => doctor.id == widget.doctorId)
        .map((doctor) => doctor.fullName)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.s6,
            end: AppSpacing.s6,
            top: AppSpacing.s4,
          ),
          child: AppPageHeader(
            title: doctorName ?? 'Doctor schedule',
            description: 'Appointments filtered to this doctor.',
          ),
        ),
        const Expanded(child: AppointmentCalendarPage()),
      ],
    );
  }
}
