// Test-only helpers; not imported by production code.
// ignore_for_file: depend_on_referenced_packages

import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';

/// Standard test branch for consistent test data.
BranchListItem sampleBranch({
  String id = '44444444-4444-4444-8444-444444444444',
  String name = 'Test Branch',
  bool isActive = true,
  String? code = 'TB',
  String? address = '123 Test St',
  String? phone,
}) {
  return BranchListItem(
    id: id,
    name: name,
    isActive: isActive,
    code: code,
    address: address,
    phone: phone,
  );
}

/// Standard test organization profile.
OrganizationProfile sampleOrganizationProfile({
  String id = '20202020-2020-4020-8020-202020202020',
  String name = 'Test Clinic',
  String? currencyCode,
  String? timezone,
}) {
  return OrganizationProfile(
    id: id,
    name: name,
    currencyCode: currencyCode,
    timezone: timezone,
  );
}
