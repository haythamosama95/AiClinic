import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/service_catalog/domain/service.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_branch_row.dart';

/// Service plus scoped branch configuration for the editor (Service Catalog 015).
@immutable
class ServiceDetail {
  const ServiceDetail({required this.service, required this.branches});

  final Service service;
  final List<ServiceBranchRow> branches;

  static ServiceDetail? fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }

    final serviceRaw = data['service'];
    if (serviceRaw is! Map) {
      return null;
    }

    final service = Service.fromRow(Map<String, dynamic>.from(serviceRaw));
    if (service == null) {
      return null;
    }

    final branchesRaw = data['branches'];
    final branches = <ServiceBranchRow>[];
    if (branchesRaw is List) {
      for (final item in branchesRaw) {
        if (item is Map<String, dynamic>) {
          final row = ServiceBranchRow.fromRow(item);
          if (row != null) {
            branches.add(row);
          }
        } else if (item is Map) {
          final row = ServiceBranchRow.fromRow(Map<String, dynamic>.from(item));
          if (row != null) {
            branches.add(row);
          }
        }
      }
    }

    return ServiceDetail(service: service, branches: branches);
  }
}
