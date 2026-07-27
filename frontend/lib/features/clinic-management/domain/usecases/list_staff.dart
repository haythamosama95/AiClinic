import 'package:ai_clinic/features/clinic-management/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_filter.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';

class ListStaff {
  const ListStaff(this._repository);
  final StaffAdminRepository _repository;

  Future<List<StaffListItem>> call({
    StaffListFilter filter = StaffListFilter.all,
  }) {
    return _repository.listStaff(filter: filter);
  }
}
