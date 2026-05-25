/// Input for [manage_create_branch] RPC.
class CreateBranchInput {
  const CreateBranchInput({required this.name, this.code, this.address, this.phone, this.mapsUrl});

  final String name;
  final String? code;
  final String? address;
  final String? phone;
  final String? mapsUrl;
}
