import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/organization_repository.dart';

class FetchOrganizationProfile {
  const FetchOrganizationProfile(this._repository);
  final OrganizationRepository _repository;

  Future<OrganizationProfile?> call({required String organizationId}) {
    return _repository.fetchProfile(organizationId: organizationId);
  }
}
