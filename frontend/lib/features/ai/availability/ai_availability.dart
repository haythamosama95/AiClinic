/// Clinic-side AI availability model and injectable ports (§4.2).

/// One notice record from `get_ai_status` `notices[]`.
class AiStatusNotice {
  const AiStatusNotice({
    required this.code,
    required this.audience,
    required this.channel,
    this.graceDaysLeft,
  });

  final String code;
  final String audience;
  final String channel;
  final int? graceDaysLeft;

  factory AiStatusNotice.fromJson(Map<String, dynamic> json) {
    return AiStatusNotice(
      code: json['code'] as String,
      audience: json['audience'] as String,
      channel: json['channel'] as String,
      graceDaysLeft: json['grace_days_left'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'audience': audience,
        'channel': channel,
        if (graceDaysLeft != null) 'grace_days_left': graceDaysLeft,
      };
}

/// Platform denial wire codes that refresh `get_ai_status` (04 §3.4; P6.1 escalations).
const kCoverageDenialWireCodes = <String>{
  'allowance_exhausted',
  'coverage_lapsed',
  'coverage_unknown',
};

bool isCoverageDenialWireCode(String? wireCode) =>
    wireCode != null && kCoverageDenialWireCodes.contains(wireCode);

/// Thrown when an RPC answers `CONTRACT_VERSION_UNSUPPORTED`.
class ContractVersionUnsupportedException implements Exception {
  const ContractVersionUnsupportedException();

  @override
  String toString() => 'ContractVersionUnsupportedException';
}

class AiAvailability {
  const AiAvailability({
    required this.enrolled,
    this.state,
    this.reason,
    this.daysLeft,
    this.band,
    this.notices = const [],
    this.nextChangeAt,
    this.asOf,
    this.stale,
    this.platformBaseUrl,
  }) : available = enrolled;

  /// Legacy gate field; `fromJson` sets this from `available`.
  final bool enrolled;

  /// Consumed `get_ai_status` availability; mirrors [enrolled] for the gate.
  final bool available;
  final String? state;
  final String? reason;
  final int? daysLeft;
  final String? band;
  final List<AiStatusNotice> notices;
  final DateTime? nextChangeAt;
  final DateTime? asOf;
  final bool? stale;
  final String? platformBaseUrl;

  factory AiAvailability.fromJson(Map<String, dynamic> json) {
    final available = json['available'] as bool? ?? json['enrolled'] as bool? ?? false;
    final noticesRaw = json['notices'];
    final notices = noticesRaw is List
        ? noticesRaw
            .map((entry) => AiStatusNotice.fromJson(Map<String, dynamic>.from(entry as Map)))
            .toList(growable: false)
        : const <AiStatusNotice>[];

    return AiAvailability(
      enrolled: available,
      state: json['state'] as String?,
      reason: json['reason'] as String?,
      daysLeft: json['days_left'] as int?,
      band: json['band'] as String?,
      notices: notices,
      nextChangeAt: _parseDateTime(json['next_change_at']),
      asOf: _parseDateTime(json['as_of']),
      stale: json['stale'] as bool?,
      platformBaseUrl: json['platform_base_url'] as String?,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.parse(value);
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'available': available,
        'enrolled': enrolled,
        if (state != null) 'state': state,
        if (reason != null) 'reason': reason,
        if (daysLeft != null) 'days_left': daysLeft,
        if (band != null) 'band': band,
        'notices': notices.map((notice) => notice.toJson()).toList(growable: false),
        if (nextChangeAt != null) 'next_change_at': nextChangeAt!.toIso8601String(),
        if (asOf != null) 'as_of': asOf!.toIso8601String(),
        if (stale != null) 'stale': stale,
        'platform_base_url': platformBaseUrl,
      };

  static const nonEnrolled = AiAvailability(enrolled: false);
}

/// Reads enrollment + platform base URL from the clinic store only (FR-008/009).
abstract class AiAvailabilityReader {
  Future<AiAvailability> read();
}

/// Enrolled-only reachability probe against A1 `/health` (FR-012).
abstract class PlatformReachabilityPort {
  Future<bool> isReachable(String platformBaseUrl);
}
