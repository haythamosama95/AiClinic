<<<<<<< HEAD
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
=======
import 'package:ai_clinic/features/queue/data/queue_realtime_apply.dart';
import 'package:ai_clinic/features/queue/data/queue_realtime.dart';
>>>>>>> master
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/appointment_queue_realtime_test_support.dart';

void main() {
  group('SupabaseAppointmentQueueRealtimeClient', () {
    late FakeSupabaseClientForQueueRealtime client;
    late SupabaseAppointmentQueueRealtimeClient realtime;

    setUp(() {
      client = FakeSupabaseClientForQueueRealtime();
      realtime = SupabaseAppointmentQueueRealtimeClient(client);
    });

    test('trivial: subscribe emits connecting immediately', () {
      final statuses = <AppointmentQueueRealtimeConnection>[];

      realtime.subscribe(
        branchId: 'branch-1',
        onAppointmentChange: (_) {},
        onConnectionChanged: statuses.add,
      );

      expect(statuses.first, AppointmentQueueRealtimeConnection.connecting);
    });

    test('advanced: subscribe maps subscribed status to live', () {
      final statuses = <AppointmentQueueRealtimeConnection>[];

      realtime.subscribe(
        branchId: 'branch-1',
        onAppointmentChange: (_) {},
        onConnectionChanged: statuses.add,
      );

      final channel = client.channelsByName['appointments-queue-branch-1']!;
      channel.subscribeCallback?.call(RealtimeSubscribeStatus.subscribed, null);

      expect(statuses, contains(AppointmentQueueRealtimeConnection.live));
    });

    test('advanced: subscribe maps channelError to degraded', () {
      final statuses = <AppointmentQueueRealtimeConnection>[];

      realtime.subscribe(
        branchId: 'branch-1',
        onAppointmentChange: (_) {},
        onConnectionChanged: statuses.add,
      );

      final channel = client.channelsByName['appointments-queue-branch-1']!;
      channel.subscribeCallback?.call(RealtimeSubscribeStatus.channelError, 'boom');

      expect(statuses, contains(AppointmentQueueRealtimeConnection.degraded));
    });

    test('advanced: subscribe maps timedOut to degraded', () {
      final statuses = <AppointmentQueueRealtimeConnection>[];

      realtime.subscribe(
        branchId: 'branch-1',
        onAppointmentChange: (_) {},
        onConnectionChanged: statuses.add,
      );

      client.channelsByName['appointments-queue-branch-1']!
          .subscribeCallback
          ?.call(RealtimeSubscribeStatus.timedOut, null);

      expect(statuses, contains(AppointmentQueueRealtimeConnection.degraded));
    });

    test('advanced: subscribe maps closed to degraded', () {
      final statuses = <AppointmentQueueRealtimeConnection>[];

      realtime.subscribe(
        branchId: 'branch-1',
        onAppointmentChange: (_) {},
        onConnectionChanged: statuses.add,
      );

      client.channelsByName['appointments-queue-branch-1']!
          .subscribeCallback
          ?.call(RealtimeSubscribeStatus.closed, null);

      expect(statuses, contains(AppointmentQueueRealtimeConnection.degraded));
    });

    test('advanced: postgres callback converts empty records to null', () {
      AppointmentQueueRealtimeChange? captured;

      realtime.subscribe(
        branchId: 'branch-1',
        onAppointmentChange: (change) => captured = change,
        onConnectionChanged: (_) {},
      );

      final channel = client.channelsByName['appointments-queue-branch-1']!;
      channel.postgresCallback?.call(
        PostgresChangePayload(
          schema: 'public',
          table: 'appointments',
          commitTimestamp: DateTime.utc(2026, 6, 4),
          eventType: PostgresChangeEvent.update,
          newRecord: const {},
          oldRecord: const {},
          errors: null,
        ),
      );

      expect(captured, isNotNull);
      expect(captured!.oldRecord, isNull);
      expect(captured!.newRecord, isNull);
    });

    test('advanced: postgres callback copies populated records', () {
      AppointmentQueueRealtimeChange? captured;

      realtime.subscribe(
        branchId: 'branch-1',
        onAppointmentChange: (change) => captured = change,
        onConnectionChanged: (_) {},
      );

      final channel = client.channelsByName['appointments-queue-branch-1']!;
      channel.postgresCallback?.call(
        PostgresChangePayload(
          schema: 'public',
          table: 'appointments',
          commitTimestamp: DateTime.utc(2026, 6, 4),
          eventType: PostgresChangeEvent.update,
          newRecord: const {'id': 'a1', 'status': 'confirmed'},
          oldRecord: const {'id': 'a1', 'status': 'scheduled'},
          errors: null,
        ),
      );

      expect(captured!.newRecord, {'id': 'a1', 'status': 'confirmed'});
      expect(captured!.oldRecord, {'id': 'a1', 'status': 'scheduled'});
      expect(captured!.newRecord, isNot(same(captured!.oldRecord)));
    });

    test('regression: re-subscribe unsubscribes previous channel first', () {
      realtime.subscribe(
        branchId: 'branch-1',
        onAppointmentChange: (_) {},
        onConnectionChanged: (_) {},
      );
      final firstChannel = client.channelsByName['appointments-queue-branch-1'];

      realtime.subscribe(
        branchId: 'branch-2',
        onAppointmentChange: (_) {},
        onConnectionChanged: (_) {},
      );

      expect(client.removedChannels, contains(firstChannel));
      expect(client.channelsByName.containsKey('appointments-queue-branch-2'), isTrue);
    });

    test('trivial: unsubscribe removes active channel', () {
      realtime.subscribe(
        branchId: 'branch-1',
        onAppointmentChange: (_) {},
        onConnectionChanged: (_) {},
      );
      final channel = client.channelsByName['appointments-queue-branch-1'];

      realtime.unsubscribe();

      expect(client.removedChannels, contains(channel));
      expect(client.channelsByName, isEmpty);
    });

    test('edge case: unsubscribe with no active channel is a no-op', () {
      realtime.unsubscribe();

      expect(client.removedChannels, isEmpty);
    });
  });
}
