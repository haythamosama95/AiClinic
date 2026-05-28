import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';

/// Input for [manage_create_branch] RPC.
class CreateBranchInput {
  const CreateBranchInput({
    required this.name,
    required this.workingSchedule,
    this.code,
    this.address,
    this.phone,
    this.mapsUrl,
  });

  final String name;
  final BranchWorkingSchedule workingSchedule;
  final String? code;
  final String? address;
  final String? phone;
  final String? mapsUrl;
}
