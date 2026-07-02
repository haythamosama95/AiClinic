import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';

/// One-shot scroll target for expert-mode section navigation from the summary page.
final expertModeScrollTargetProvider = NotifierProvider.autoDispose
    .family<ExpertModeScrollTargetNotifier, EncounterPhase?, String>(ExpertModeScrollTargetNotifier.new);

class ExpertModeScrollTargetNotifier extends Notifier<EncounterPhase?> {
  ExpertModeScrollTargetNotifier(String _);

  @override
  EncounterPhase? build() => null;

  void request(EncounterPhase phase) {
    state = phase;
  }

  void clear() {
    state = null;
  }
}
