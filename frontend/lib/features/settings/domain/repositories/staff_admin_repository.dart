import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';

/// Abstract staff administration reads and lifecycle RPCs.
abstract class StaffAdminRepository {
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all});
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId);
  Future<String> updateStaffMember(UpdateStaffMemberInput input);
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive});
}
