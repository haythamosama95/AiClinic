import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';

/// Filters for the service catalog management list (`list_services`, 015 US6).
@immutable
class ServiceListFilters {
  const ServiceListFilters({this.query = '', this.globalStatus, this.branchId, this.page = 1, this.pageSize = 25});

  final String query;
  final GlobalStatus? globalStatus;
  final String? branchId;
  final int page;
  final int pageSize;

  int get offset => (page - 1) * pageSize;

  bool get hasActiveFilters =>
      query.trim().isNotEmpty || globalStatus != null || (branchId != null && branchId!.isNotEmpty);

  ServiceListFilters copyWith({
    String? query,
    GlobalStatus? globalStatus,
    bool clearGlobalStatus = false,
    String? branchId,
    bool clearBranchId = false,
    int? page,
    int? pageSize,
  }) {
    return ServiceListFilters(
      query: query ?? this.query,
      globalStatus: clearGlobalStatus ? null : (globalStatus ?? this.globalStatus),
      branchId: clearBranchId ? null : (branchId ?? this.branchId),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, dynamic> toRpcParams() {
    final params = <String, dynamic>{'p_limit': pageSize, 'p_offset': offset};
    final trimmedQuery = query.trim();
    if (trimmedQuery.isNotEmpty) {
      params['p_query'] = trimmedQuery;
    }
    if (globalStatus != null) {
      params['p_global_status'] = globalStatus!.wireValue;
    }
    if (branchId != null && branchId!.isNotEmpty) {
      params['p_branch_id'] = branchId;
    }
    return params;
  }
}
