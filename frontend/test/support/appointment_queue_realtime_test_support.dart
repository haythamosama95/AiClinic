import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Captures realtime channel wiring for [SupabaseAppointmentQueueRealtimeClient] tests.
class FakeRealtimeChannel extends Fake implements RealtimeChannel {
  FakeRealtimeChannel(this.channelName);

  final String channelName;
  PostgresChangeCallback? postgresCallback;
  void Function(RealtimeSubscribeStatus status, Object? error)? subscribeCallback;
  int subscribeCallCount = 0;

  @override
  RealtimeChannel onPostgresChanges({
    required PostgresChangeEvent event,
    required String schema,
    required String table,
    PostgresChangeFilter? filter,
    required PostgresChangeCallback callback,
  }) {
    postgresCallback = callback;
    return this;
  }

  @override
  RealtimeChannel subscribe([
    void Function(RealtimeSubscribeStatus status, Object? error)? callback,
  ]) {
    subscribeCallCount += 1;
    subscribeCallback = callback;
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    return 'ok';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
