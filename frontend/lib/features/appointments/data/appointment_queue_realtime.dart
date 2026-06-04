import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime_apply.dart';

/// Realtime connection state for today's queue (FR-016).
enum AppointmentQueueRealtimeConnection { connecting, live, degraded }

typedef AppointmentQueueRealtimeStatusCallback = void Function(AppointmentQueueRealtimeConnection connection);

typedef AppointmentQueueRealtimeChangeCallback = void Function(AppointmentQueueRealtimeChange change);

/// Subscribes to appointment postgres changes for queue refresh (V1-4 US4).
abstract class AppointmentQueueRealtimeClient {
  void subscribe({
    required String branchId,
    required AppointmentQueueRealtimeChangeCallback onAppointmentChange,
    required AppointmentQueueRealtimeStatusCallback onConnectionChanged,
  });

  void unsubscribe();
}

class SupabaseAppointmentQueueRealtimeClient implements AppointmentQueueRealtimeClient {
  SupabaseAppointmentQueueRealtimeClient(this._client);

  final SupabaseClient _client;
  RealtimeChannel? _channel;

  @override
  void subscribe({
    required String branchId,
    required AppointmentQueueRealtimeChangeCallback onAppointmentChange,
    required AppointmentQueueRealtimeStatusCallback onConnectionChanged,
  }) {
    unsubscribe();
    onConnectionChanged(AppointmentQueueRealtimeConnection.connecting);

    final channel = _client.channel('appointments-queue-$branchId');
    _channel = channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'appointments',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'branch_id', value: branchId),
          callback: (payload) {
            onAppointmentChange(
              AppointmentQueueRealtimeChange(
                eventType: payload.eventType,
                oldRecord: payload.oldRecord.isEmpty ? null : Map<String, dynamic>.from(payload.oldRecord),
                newRecord: payload.newRecord.isEmpty ? null : Map<String, dynamic>.from(payload.newRecord),
              ),
            );
          },
        )
        .subscribe((status, error) {
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              onConnectionChanged(AppointmentQueueRealtimeConnection.live);
            case RealtimeSubscribeStatus.channelError:
            case RealtimeSubscribeStatus.timedOut:
            case RealtimeSubscribeStatus.closed:
              onConnectionChanged(AppointmentQueueRealtimeConnection.degraded);
          }
        });
  }

  @override
  void unsubscribe() {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(_client.removeChannel(channel));
    }
  }
}

final appointmentQueueRealtimeClientProvider = Provider<AppointmentQueueRealtimeClient>((ref) {
  return SupabaseAppointmentQueueRealtimeClient(ref.watch(supabaseClientProvider));
});
