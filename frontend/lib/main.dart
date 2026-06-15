import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/app.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';

/// Syncfusion community/commercial license (v32+ does not require runtime registration).
const syncfusionLicenseKey = 'Ngo9BigBOggjGyl/VkV+XU9AclRDX3xKf0x/TGpQb19xflBPallYVBYiSV9jS3hTcERmWXxceXBVRmBaUU91XA==';

/// Boots the app inside Riverpod's global provider scope.
void main() {
  ensureAppointmentTimezonesInitialized();
  runApp(const ProviderScope(child: AiClinicApp()));
}
