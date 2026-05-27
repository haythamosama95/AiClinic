/// Input for [update_branch] RPC.
class UpdateBranchInput {
  const UpdateBranchInput({
    required this.branchId,
    required this.name,
    this.code,
    this.address,
    this.phone,
    this.mapsUrl,
  });

  final String branchId;
  final String name;
  final String? code;
  final String? address;
  final String? phone;
  final String? mapsUrl;
}
