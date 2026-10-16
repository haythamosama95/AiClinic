import 'package:ai_clinic/core/ai/context_registration.dart';
import 'package:ai_clinic/core/ai/context_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('Context Resolver', () {
    test('resolver_key_list_assembles_payload', () async {
      final port = FakeContextProviderPort();
      final resolver = ContextResolver(providerPort: port);

      final result = await resolver.resolve([visitChiefComplaintV1Key]);

      expect(result, isA<ContextResolveSuccess>());
      final payload = (result as ContextResolveSuccess).payload;
      expect(payload.keys, [visitChiefComplaintV1Key]);
      final chiefComplaint =
          payload[visitChiefComplaintV1Key]! as Map<String, Object?>;
      expect(chiefComplaint['visit_id'], isA<String>());
      expect(chiefComplaint['complaint'], isA<String>());
      expect(chiefComplaint['recorded_at'], isA<String>());
    });

    test('resolver_unknown_key_typed_failure', () async {
      final resolver = ContextResolver(
        providerPort: FakeContextProviderPort(),
      );

      final result = await resolver.resolve([
        visitChiefComplaintV1Key,
        'patient.demographics@v1',
      ]);

      expect(result, isA<ContextResolveFailure>());
      final failure = result as ContextResolveFailure;
      expect(failure.code, 'unknown_context_key');
      expect(failure.unknownKey, 'patient.demographics@v1');
      expect(failure.failedKey, isNull);
      expect(result, isNot(isA<ContextResolveSuccess>()));
    });

    test('resolver_port_throw_resolution_failed', () async {
      final resolver = ContextResolver(
        providerPort: ThrowingContextProviderPort(),
      );

      final result = await resolver.resolve([visitChiefComplaintV1Key]);

      expect(result, isA<ContextResolveFailure>());
      final failure = result as ContextResolveFailure;
      expect(failure.code, 'resolution_failed');
      expect(failure.failedKey, visitChiefComplaintV1Key);
      expect(failure.unknownKey, isNull);
      expect(result, isNot(isA<ContextResolveSuccess>()));
    });

    test('resolver_api_exposes_no_capability_id', () async {
      Future<ContextResolveResult> Function(List<String>) assertApiShape(
        Future<ContextResolveResult> Function(List<String>) resolve,
      ) =>
          resolve;

      final spy = ResolverSpy(providerPort: FakeContextProviderPort());
      final resolve = assertApiShape(spy.resolve);

      // Same key list as if supplied by two different capability manifests —
      // resolution must be invariant to which capability declared the keys.
      final first = await resolve([visitChiefComplaintV1Key]);
      final second = await resolve([visitChiefComplaintV1Key]);

      expect(first, isA<ContextResolveSuccess>());
      expect(second, isA<ContextResolveSuccess>());
      expect(
        (first as ContextResolveSuccess).payload,
        equals((second as ContextResolveSuccess).payload),
      );
      expect(spy.resolveCalls, [
        [visitChiefComplaintV1Key],
        [visitChiefComplaintV1Key],
      ]);
      for (final call in spy.resolveCalls) {
        expect(call, isA<List<String>>());
        expect(call, isNot(contains(isA<Map>())));
      }
      spy.dispose();
    });

    test('resolve_requests_passes_arguments_to_registration', () async {
      final port = FakeContextProviderPort();
      final resolver = ContextResolver(providerPort: port);

      final result = await resolver.resolveRequests([
        {
          'key': visitChiefComplaintV1Key,
          'arguments': <String, Object?>{'patient_hint': 'Ahmed'},
        },
      ]);

      expect(result, isA<ContextResolveSuccess>());
      final payload = (result as ContextResolveSuccess).payload;
      expect(payload.keys, [visitChiefComplaintV1Key]);
    });

    test('resolve_keys_wrapper_delegates_to_resolve_requests', () async {
      final spy = ResolverSpy(providerPort: FakeContextProviderPort());

      final result = await spy.resolve([visitChiefComplaintV1Key]);

      expect(result, isA<ContextResolveSuccess>());
      expect(spy.resolveRequestsCalls, hasLength(1));
      expect(spy.resolveRequestsCalls.single.single['key'], visitChiefComplaintV1Key);
      expect(spy.resolveCalls.single, [visitChiefComplaintV1Key]);
      spy.dispose();
    });

    test('resolver_cache_screen_scoped_discarded_on_dispose', () async {
      final port = FakeContextProviderPort();
      final resolver = ContextResolver(providerPort: port);

      await resolver.resolve([visitChiefComplaintV1Key]);
      expect(port.fetchVisitChiefComplaintCallCount, 1);

      await resolver.resolve([visitChiefComplaintV1Key]);
      expect(port.fetchVisitChiefComplaintCallCount, 1);

      resolver.dispose();

      await expectLater(
        resolver.resolve([visitChiefComplaintV1Key]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disposed'),
          ),
        ),
      );

      // Double-dispose must be safe (host + surface may both call dispose).
      resolver.dispose();

      // Independent instances with the same port do not share cache.
      final resolverA = ContextResolver(providerPort: port);
      final resolverB = ContextResolver(providerPort: port);
      await resolverA.resolve([visitChiefComplaintV1Key]);
      expect(port.fetchVisitChiefComplaintCallCount, 2);
      await resolverB.resolve([visitChiefComplaintV1Key]);
      expect(port.fetchVisitChiefComplaintCallCount, 3);

      resolverA.dispose();
      resolverB.dispose();
    });
  });
}
