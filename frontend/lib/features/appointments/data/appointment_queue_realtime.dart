import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';

/// Realtime connection state for today's queue (FR-016).
enum AppointmentQueueRealtimeConnection { connecting, live, degraded }

typedef AppointmentQueueRealtimeStatusCallback = void Function(AppointmentQueueRealtimeConnection connection);

/// Subscribes to appointment postgres changes for queue refresh (V1-4 US4).
abstract class AppointmentQueueRealtimeClient {
  void subscribe({
    required String branchId,
    required VoidCallback onAppointmentChange,
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
    required VoidCallback onAppointmentChange,
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
          callback: (_) => onAppointmentChange(),
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
