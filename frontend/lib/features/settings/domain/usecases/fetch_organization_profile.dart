import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/repositories/organization_repository.dart';

class FetchOrganizationProfile {
  const FetchOrganizationProfile(this._repository);
  final OrganizationRepository _repository;

  Future<OrganizationProfile?> call({required String organizationId}) {
    return _repository.fetchProfile(organizationId: organizationId);
  }
}
