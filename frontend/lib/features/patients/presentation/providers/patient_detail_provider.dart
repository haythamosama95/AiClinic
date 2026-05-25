import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/patient_rpc_messages.dart';

/// Loads a single patient profile for [PatientDetailPage] (US3).
final patientDetailProvider = FutureProvider.autoDispose.family<PatientDetail, String>((ref, patientId) async {
  final id = patientId.trim();
  if (id.isEmpty) {
    throw StateError('Patient id is required.');
  }

  try {
    return await ref.read(getPatientUseCaseProvider)(id);
  } on RpcFailure catch (failure) {
    throw StateError(patientMessageForRpc(failure));
  }
});
