import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_form.dart';

/// Book a planned appointment at the active branch (`/appointments/book`).
class AppointmentBookingPage extends ConsumerWidget {
  const AppointmentBookingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const AppointmentBookingForm();
  }
}
