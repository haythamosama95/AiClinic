import 'package:ai_clinic/features/billing/domain/money.dart';

/// Pure validation helpers for the service editor form (Service Catalog 015).
abstract final class ServiceFormValidation {
  static String? validateName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Service name is required.';
    }
    if (trimmed.length > 200) {
      return 'Service name cannot exceed 200 characters.';
    }
    return null;
  }

  static String? validateDefaultPrice(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Default price is required.';
    }
    if (trimmed.contains(',')) {
      return 'Use a dot as the decimal separator.';
    }
    final parsed = Money.tryParse(trimmed);
    if (parsed == null) {
      return 'Enter a valid price with at most two decimal places.';
    }
    if (parsed.isNegative) {
      return 'Price must be zero or greater.';
    }
    return null;
  }

  static String? validateBranchSelection({required bool assignAllBranches, required Set<String> selectedBranchIds}) {
    if (assignAllBranches) {
      return null;
    }
    if (selectedBranchIds.isEmpty) {
      return 'Select at least one branch or assign to all branches.';
    }
    return null;
  }
}
