import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

class ListStaff {
  const ListStaff(this._repository);
  final StaffAdminRepository _repository;

  Future<List<StaffListItem>> call({
    StaffListFilter filter = StaffListFilter.all,
  }) {
    return _repository.listStaff(filter: filter);
  }
}
