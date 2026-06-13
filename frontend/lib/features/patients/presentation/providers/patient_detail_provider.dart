import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';

/// Loads a full patient profile for the detail view (`get_patient` RPC).
final patientDetailProvider = FutureProvider.autoDispose.family<PatientDetail, String>((ref, patientId) async {
  final canAccess = ref.watch(authSessionProvider.select(AuthRouteGuard.canAccessPatientDetail));
  if (!canAccess) {
    throw StateError('You do not have permission to view this patient.');
  }

  return ref.read(getPatientUseCaseProvider)(patientId);
});
