/// Result of atomic bootstrap setup (organization, branch, and staff created together).
class BootstrapFinishSetupResult {
  const BootstrapFinishSetupResult({
    required this.organizationId,
    required this.branchId,
    required this.staffMemberIds,
  });

  final String organizationId;
  final String branchId;
  final List<String> staffMemberIds;
}
