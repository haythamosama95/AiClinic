import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/expert_mode_scroll_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/visit_encounter_test_support.dart';

const _visitIdB = 'ffffffff-ffff-4fff-8fff-ffffffffffff';

void main() {
  group('ExpertModeScrollTargetNotifier', () {
    test('trivial: initial state is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(expertModeScrollTargetProvider(encounterTestVisitId)), isNull);
    });

    test('trivial: request sets the scroll target phase', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(expertModeScrollTargetProvider(encounterTestVisitId).notifier);

      notifier.request(EncounterPhase.objective);

      expect(container.read(expertModeScrollTargetProvider(encounterTestVisitId)), EncounterPhase.objective);
    });

    test('trivial: clear resets the target to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(expertModeScrollTargetProvider(encounterTestVisitId).notifier);

      notifier.request(EncounterPhase.plan);
      notifier.clear();

      expect(container.read(expertModeScrollTargetProvider(encounterTestVisitId)), isNull);
    });

    test('advanced: consecutive requests overwrite the previous target', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(expertModeScrollTargetProvider(encounterTestVisitId).notifier);

      notifier.request(EncounterPhase.subjective);
      notifier.request(EncounterPhase.review);

      expect(container.read(expertModeScrollTargetProvider(encounterTestVisitId)), EncounterPhase.review);
    });

    test('edge case: target persists until clear (no automatic consumption)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(expertModeScrollTargetProvider(encounterTestVisitId).notifier);

      notifier.request(EncounterPhase.plan);

      expect(container.read(expertModeScrollTargetProvider(encounterTestVisitId)), EncounterPhase.plan);
      expect(container.read(expertModeScrollTargetProvider(encounterTestVisitId)), EncounterPhase.plan);
    });

    test('edge case: family instances are independent per visit id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(expertModeScrollTargetProvider(encounterTestVisitId).notifier).request(EncounterPhase.objective);
      container.read(expertModeScrollTargetProvider(_visitIdB).notifier).request(EncounterPhase.billing);

      expect(container.read(expertModeScrollTargetProvider(encounterTestVisitId)), EncounterPhase.objective);
      expect(container.read(expertModeScrollTargetProvider(_visitIdB)), EncounterPhase.billing);
    });
  });
}
