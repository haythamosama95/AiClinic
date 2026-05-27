import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/update_organization_input.dart';

/// Abstract organization profile reads and updates.
abstract class OrganizationRepository {
  Future<OrganizationProfile?> fetchProfile({required String organizationId});
  Future<String> updateOrganization(UpdateOrganizationInput input);
}
