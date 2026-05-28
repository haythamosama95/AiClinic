import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';

/// Doctor-focused calendar view for `/appointments/schedule/:doctorId`.
class DoctorSchedulePage extends ConsumerStatefulWidget {
  const DoctorSchedulePage({required this.doctorId, super.key});

  final String? doctorId;

  @override
  ConsumerState<DoctorSchedulePage> createState() => _DoctorSchedulePageState();
}

class _DoctorSchedulePageState extends ConsumerState<DoctorSchedulePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = widget.doctorId?.trim();
      ref.read(appointmentCalendarProvider.notifier).setDoctorFilter((id == null || id.isEmpty) ? null : id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const AppointmentCalendarPage();
  }
}
