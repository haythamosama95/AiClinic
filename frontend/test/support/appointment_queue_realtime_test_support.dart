import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Captures realtime channel wiring for [SupabaseAppointmentQueueRealtimeClient] tests.
class FakeRealtimeChannel extends Fake implements RealtimeChannel {
  FakeRealtimeChannel(this.channelName);

  final String channelName;
<<<<<<< HEAD
  PostgresChangeCallback? postgresCallback;
=======
  void Function(PostgresChangePayload)? postgresCallback;
>>>>>>> master
  void Function(RealtimeSubscribeStatus status, Object? error)? subscribeCallback;
  int subscribeCallCount = 0;

  @override
  RealtimeChannel onPostgresChanges({
    required PostgresChangeEvent event,
<<<<<<< HEAD
    required String schema,
    required String table,
    PostgresChangeFilter? filter,
    required PostgresChangeCallback callback,
=======
    String? schema,
    String? table,
    PostgresChangeFilter? filter,
    List<PostgresChangeFilter>? filters,
    List<String>? select,
    required void Function(PostgresChangePayload payload) callback,
>>>>>>> master
  }) {
    postgresCallback = callback;
    return this;
  }

  @override
  RealtimeChannel subscribe([
    void Function(RealtimeSubscribeStatus status, Object? error)? callback,
<<<<<<< HEAD
=======
    Duration? timeout,
>>>>>>> master
  ]) {
    subscribeCallCount += 1;
    subscribeCallback = callback;
    return this;
  }
<<<<<<< HEAD

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
=======
>>>>>>> master
}

/// Minimal [SupabaseClient] fake for appointment queue realtime unit tests.
class FakeSupabaseClientForQueueRealtime extends Fake implements SupabaseClient {
  final Map<String, FakeRealtimeChannel> channelsByName = {};
  final List<RealtimeChannel> removedChannels = [];

  @override
  RealtimeChannel channel(String name, {RealtimeChannelConfig opts = const RealtimeChannelConfig()}) {
    final channel = FakeRealtimeChannel(name);
    channelsByName[name] = channel;
    return channel;
  }

  @override
  Future<String> removeChannel(RealtimeChannel channel) async {
    removedChannels.add(channel);
<<<<<<< HEAD
    return 'ok';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
=======
    channelsByName.removeWhere((_, value) => identical(value, channel));
    return 'ok';
  }
>>>>>>> master
}
