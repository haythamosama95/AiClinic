import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/appointment_rpc_test_client.dart';
import '../../support/fake_postgrest_rpc.dart';

class _StatusFailAfterUpdateClient extends AppointmentRpcTestClient {
  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'update_appointment_status') {
      rpcLog.add(fn);
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
      return FakePostgrestRpc({'success': false, 'error_code': 'DOCTOR_ALREADY_IN_PROGRESS', 'error_message': 'busy'})
          as PostgrestFilterBuilder<T>;
    }
    return super.rpc(fn, params: params, get: get);
  }
}

void main() {
  group('BUG-004 doctor assignment rollback contract', () {
    test('updateAppointment can be called again to restore the previous doctor after status failure', () async {
      final client = _StatusFailAfterUpdateClient();
      final repository = AppointmentRepository(client);
      const appointmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

      await repository.updateAppointment(
        appointmentId: appointmentId,
        patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        doctorId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        startTime: DateTime.utc(2026, 6, 4, 10),
        endTime: DateTime.utc(2026, 6, 4, 10, 30),
      );

      expect(
        () => repository.updateAppointmentStatus(appointmentId: appointmentId, newStatus: AppointmentStatus.inProgress),
        throwsA(isA<RpcFailure>()),
      );

      await repository.updateAppointment(
        appointmentId: appointmentId,
        patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        doctorId: 'original-doctor-id',
        startTime: DateTime.utc(2026, 6, 4, 10),
        endTime: DateTime.utc(2026, 6, 4, 10, 30),
      );

      expect(client.rpcCallCounts['update_appointment'], 2);
      expect(client.rpcCallCounts['update_appointment_status'], 1);
    });
  });
}
