import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';

/// Branch fields for first-time clinic bootstrap.
class BootstrapBranchInput {
  const BootstrapBranchInput({
    required this.organizationId,
    required this.name,
    this.code,
    this.address,
    this.phone,
    this.mapsUrl,
    this.workingSchedule,
  });

  final String organizationId;
  final String name;
  final String? code;
  final String? address;
  final String? phone;
  final String? mapsUrl;
  final BranchWorkingSchedule? workingSchedule;
}
