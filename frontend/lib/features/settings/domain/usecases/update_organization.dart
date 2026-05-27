import 'package:ai_clinic/features/settings/domain/repositories/organization_repository.dart';
import 'package:ai_clinic/features/settings/domain/update_organization_input.dart';

class UpdateOrganization {
  const UpdateOrganization(this._repository);
  final OrganizationRepository _repository;

  Future<String> call(UpdateOrganizationInput input) {
    return _repository.updateOrganization(input);
  }
}
