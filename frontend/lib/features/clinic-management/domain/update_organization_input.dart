/// Input for steady-state [update_organization] RPC.
class UpdateOrganizationInput {
  const UpdateOrganizationInput({
    required this.name,
    this.logoUrl,
    this.currencyCode,
    this.timezone,
    this.settingsJson,
  });

  final String name;
  final String? logoUrl;
  final String? currencyCode;
  final String? timezone;
  final Map<String, dynamic>? settingsJson;
}
