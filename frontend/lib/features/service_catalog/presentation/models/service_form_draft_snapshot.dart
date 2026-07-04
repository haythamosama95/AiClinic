import 'package:flutter/foundation.dart';

/// Live service-form values needed to render draft branch configuration during create.
@immutable
class ServiceFormDraftSnapshot {
  const ServiceFormDraftSnapshot({
    required this.defaultPrice,
    required this.assignAllBranches,
    required this.selectedBranchIds,
  });

  final String defaultPrice;
  final bool assignAllBranches;
  final Set<String> selectedBranchIds;
}
