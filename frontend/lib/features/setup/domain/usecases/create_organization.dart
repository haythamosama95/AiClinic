import 'package:ai_clinic/features/setup/domain/bootstrap_organization_input.dart';
import 'package:ai_clinic/features/setup/domain/repositories/bootstrap_repository.dart';

class CreateOrganization {
  const CreateOrganization(this._repository);
  final BootstrapRepository _repository;

  Future<String> call(BootstrapOrganizationInput input) {
    return _repository.createOrganization(input);
  }
}
