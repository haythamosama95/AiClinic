import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/app.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';

/// Boots the app inside Riverpod's global provider scope.staff_form_page.dartW
void main() {
  ensureAppointmentTimezonesInitialized();
  runApp(const ProviderScope(child: AiClinicApp()));
}
