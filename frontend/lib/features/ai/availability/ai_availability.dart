/// Clinic-side AI availability model and injectable ports (§4.2).
class AiAvailability {
  const AiAvailability({
    required this.enrolled,
    this.platformBaseUrl,
  });

  final bool enrolled;
  final String? platformBaseUrl;

  factory AiAvailability.fromJson(Map<String, dynamic> json) {
    return AiAvailability(
      enrolled: json['enrolled'] as bool? ?? false,
      platformBaseUrl: json['platform_base_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'enrolled': enrolled,
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
