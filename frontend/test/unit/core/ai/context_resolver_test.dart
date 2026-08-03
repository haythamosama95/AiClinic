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
      expect(result, isNot(isA<ContextResolveSuccess>()));
    });

    test('resolver_api_exposes_no_capability_id', () {
      Future<ContextResolveResult> assertApiShape(
        Future<ContextResolveResult> Function(List<String>) resolve,
      ) =>
          resolve(['visit.chief_complaint@v1']);

      final resolver = ContextResolver(
        providerPort: FakeContextProviderPort(),
      );

      expect(assertApiShape(resolver.resolve), completes);
    });

    test('resolver_cache_screen_scoped_discarded_on_dispose', () async {
      final port = FakeContextProviderPort();
      final resolver = ContextResolver(providerPort: port);

      await resolver.resolve([visitChiefComplaintV1Key]);
      expect(port.fetchVisitChiefComplaintCallCount, 1);

      await resolver.resolve([visitChiefComplaintV1Key]);
      expect(port.fetchVisitChiefComplaintCallCount, 1);

      resolver.dispose();

      final freshResolver = ContextResolver(providerPort: port);
      await freshResolver.resolve([visitChiefComplaintV1Key]);
      expect(port.fetchVisitChiefComplaintCallCount, 2);
      freshResolver.dispose();
    });
  });
}
