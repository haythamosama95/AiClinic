import 'dart:convert';

/// Parsed response from PostgreSQL `public.rpc_result` composite type.
class RpcResult {
  const RpcResult({required this.success, this.data, this.errorCode, this.errorMessage});

  final bool success;
  final Map<String, dynamic>? data;
  final String? errorCode;
  final String? errorMessage;

  static RpcResult fromDynamic(dynamic raw) {
    if (raw is RpcResult) {
      return raw;
    }

    if (raw is Map) {
      return RpcResult(
        success: _readSuccess(raw['success']),
        data: _coerceData(raw['data']),
        errorCode: raw['error_code']?.toString() ?? raw['errorCode']?.toString(),
        errorMessage: raw['error_message']?.toString() ?? raw['errorMessage']?.toString(),
      );
    }

    if (raw is List && raw.length >= 4) {
      return RpcResult(
        success: _readSuccess(raw[0]),
        data: _coerceData(raw[1]),
        errorCode: raw[2]?.toString(),
        errorMessage: raw[3]?.toString(),
      );
    }

    throw FormatException('Unrecognized rpc_result payload: $raw');
  }

  static bool _readSuccess(dynamic value) {
    if (value == true) {
      return true;
    }
    if (value is String) {
      final normalized = value.toLowerCase();
      return normalized == 'true' || normalized == 't';
    }
    return false;
  }

  static Map<String, dynamic>? _coerceData(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } on FormatException {
        return null;
      }
    }
    return null;
  }
}

/// Thrown when an RPC returns `success = false`.
class RpcFailure implements Exception {
  RpcFailure(this.result);

  final RpcResult result;

  String get code => result.errorCode ?? 'RPC_ERROR';

  String get message => result.errorMessage ?? 'The clinic service rejected this request.';

  @override
  String toString() => 'RpcFailure($code): $message';
}
