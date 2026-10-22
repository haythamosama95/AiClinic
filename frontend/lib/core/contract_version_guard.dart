import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';

/// R2-C3 (RM37, step 2): sender-side validation of response versions.
///
/// A versioned reply is trusted only when it echoes the version this client
/// sent. The sent version must be known: the current version or the immediately
/// previous one (N-1), which the platform still accepts. Replies that are
/// missing a version, carry an unknown or mismatched version, or refuse the
/// version are never decoded into DTOs, cached, or treated as success.
bool isKnownContractVersion(int version, {required int current}) {
  return version >= 0 && (version == current || version == current - 1);
}

/// Validates an RPC reply against the sent version. Throws
/// [ContractVersionUnsupportedException] on any mismatch or missing version.
void requireEchoedRpcContractVersion(
  RpcResult result, {
  required int sent,
  required int current,
}) {
  if (!isKnownContractVersion(sent, current: current) || result.contractVersion != sent) {
    throw const ContractVersionUnsupportedException();
  }
}

/// True when the HTTP [headers] echo [sent] under [headerName] (case-insensitive)
/// and, when [body] carries a `contract_version`, that field echoes [sent] too.
/// When [bodyRequired] is set, [body] must carry the field.
bool echoesContractVersion({
  required Map<String, String> headers,
  required String headerName,
  required int sent,
  required int current,
  Map<String, Object?>? body,
  bool bodyRequired = false,
}) {
  if (!isKnownContractVersion(sent, current: current)) {
    return false;
  }
  final wanted = headerName.toLowerCase();
  String? headerValue;
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == wanted) {
      headerValue = entry.value;
      break;
    }
  }
  if (_parseVersion(headerValue) != sent) {
    return false;
  }
  if (body == null) {
    return !bodyRequired;
  }
  if (!body.containsKey('contract_version')) {
    return !bodyRequired;
  }
  return _parseVersion(body['contract_version']) == sent;
}

int? _parseVersion(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}
