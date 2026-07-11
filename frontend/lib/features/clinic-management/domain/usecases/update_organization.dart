import 'package:ai_clinic/features/clinic-management/domain/repositories/organization_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_organization_input.dart';

class UpdateOrganization {
  const UpdateOrganization(this._repository);
  final OrganizationRepository _repository;

  Future<String> call(UpdateOrganizationInput input) {
    return _repository.updateOrganization(input);
  }
}
