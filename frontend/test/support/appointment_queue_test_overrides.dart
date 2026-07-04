import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
import 'package:flutter_riverpod/misc.dart';

/// No-op realtime client for integration tests.
class FakeAppointmentQueueRealtimeClient implements AppointmentQueueRealtimeClient {
  @override
  void subscribe({
    required String branchId,
    required AppointmentQueueRealtimeChangeCallback onAppointmentChange,
    required AppointmentQueueRealtimeStatusCallback onConnectionChanged,
  }) {}

  @override
  void unsubscribe() {}
}

/// Idle queue controller that skips network refresh and realtime subscriptions.
class TestIdleAppointmentQueueNotifier extends AppointmentQueueController {
  @override
  AppointmentQueueState build() => const AppointmentQueueState(items: []);
}

List<Override> appointmentQueueTestOverrides() => [
  appointmentQueueProvider.overrideWith(TestIdleAppointmentQueueNotifier.new),
  appointmentQueueRealtimeClientProvider.overrideWithValue(FakeAppointmentQueueRealtimeClient()),
  appointmentQueueShiftDoctorLookupProvider.overrideWith((ref) async => AppointmentQueueShiftDoctorLookup.empty),
];
