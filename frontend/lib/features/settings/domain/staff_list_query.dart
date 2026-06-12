import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

/// Client-side search and filter state for the staff administration list.
class StaffListQuery {
  const StaffListQuery({this.searchText = '', this.roles = const {}, this.branchIds = const {}});

  final String searchText;
  final Set<StaffRole> roles;
  final Set<String> branchIds;

  bool get hasActiveFilters => roles.isNotEmpty || branchIds.isNotEmpty;

  int get activeFilterCount => roles.length + branchIds.length;

  StaffListQuery copyWith({String? searchText, Set<StaffRole>? roles, Set<String>? branchIds}) {
    return StaffListQuery(
      searchText: searchText ?? this.searchText,
      roles: roles ?? this.roles,
      branchIds: branchIds ?? this.branchIds,
    );
  }

  bool matches(StaffListItem member) {
    if (roles.isNotEmpty && !roles.contains(member.role)) {
      return false;
    }

    if (branchIds.isNotEmpty && !member.branches.any((branch) => branchIds.contains(branch.id))) {
      return false;
    }

    final query = searchText.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }

    if (member.fullName.toLowerCase().contains(query)) {
      return true;
    }

    final username = member.username?.toLowerCase();
    if (username != null && username.contains(query)) {
      return true;
    }

    final phone = member.phone;
    if (phone != null) {
      final queryDigits = _digitsOnly(query);
      if (queryDigits.isNotEmpty) {
        final phoneDigits = _digitsOnly(phone);
        if (phoneDigits.contains(queryDigits)) {
          return true;
        }
      } else if (phone.toLowerCase().contains(query)) {
        return true;
      }
    }

    return false;
  }

  static String _digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');
}
