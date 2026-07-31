import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Captures realtime channel wiring for [SupabaseAppointmentQueueRealtimeClient] tests.
class FakeRealtimeChannel extends Fake implements RealtimeChannel {
  FakeRealtimeChannel(this.channelName);

  final String channelName;
  void Function(PostgresChangePayload)? postgresCallback;
  void Function(RealtimeSubscribeStatus status, Object? error)? subscribeCallback;
  int subscribeCallCount = 0;

  @override
  RealtimeChannel onPostgresChanges({
    required PostgresChangeEvent event,
    String? schema,
    String? table,
    PostgresChangeFilter? filter,
    List<PostgresChangeFilter>? filters,
    List<String>? select,
    required void Function(PostgresChangePayload payload) callback,
  }) {
    postgresCallback = callback;
    return this;
  }

  @override
  RealtimeChannel subscribe([
    void Function(RealtimeSubscribeStatus status, Object? error)? callback,
    Duration? timeout,
  ]) {
    subscribeCallCount += 1;
    subscribeCallback = callback;
    return this;
  }
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
    channelsByName.removeWhere((_, value) => identical(value, channel));
    return 'ok';
  }
}
