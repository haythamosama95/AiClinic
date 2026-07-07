import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/app.dart';
import 'package:ai_clinic/core/utils/intl_date_formatting.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';

/// Boots the app inside Riverpod's global provider scope.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ensureAppointmentTimezonesInitialized();
  await ensureIntlDateFormattingInitialized();
  runApp(const ProviderScope(child: AiClinicApp()));
}
