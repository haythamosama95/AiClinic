import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';

/// Loads patient-level safety context for the encounter workspace (014 US6).
final patientSafetyProvider = AsyncNotifierProvider.autoDispose
    .family<PatientSafetyNotifier, PatientSafetyContext, String>(PatientSafetyNotifier.new);

class PatientSafetyNotifier extends AsyncNotifier<PatientSafetyContext> {
  PatientSafetyNotifier(this._patientId);

  final String _patientId;

  @override
  Future<PatientSafetyContext> build() async {
    return _load();
  }

  Future<PatientSafetyContext> _load() async {
    final patientId = _patientId.trim();
    if (patientId.isEmpty) {
      throw StateError('Patient id is required.');
    }
    return ref.read(visitRepositoryProvider).getPatientSafetyContext(patientId: patientId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _load());
  }
}
