/// Organization fields for first-time clinic bootstrap.
class BootstrapOrganizationInput {
  const BootstrapOrganizationInput({
    required this.name,
    this.logoUrl,
    this.currencyCode,
    this.timezone,
    this.settingsJson = const {},
  });

  final String name;
  final String? logoUrl;
  final String? currencyCode;
  final String? timezone;
  final Map<String, dynamic> settingsJson;
}
