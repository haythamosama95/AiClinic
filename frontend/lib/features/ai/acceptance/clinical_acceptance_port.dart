import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// Injectable port for clinic-side AI acceptance recording (F2).
abstract class ClinicalAcceptancePort {
  Future<RpcResult> recordAcceptance({
    required String requestReference,
    required String targetKey,
    required Map<String, dynamic> targetArgs,
  });
}
