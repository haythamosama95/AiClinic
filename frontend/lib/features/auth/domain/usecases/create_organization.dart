import 'package:ai_clinic/features/auth/domain/bootstrap_organization_input.dart';
import 'package:ai_clinic/features/auth/domain/repositories/bootstrap_repository.dart';

class CreateOrganization {
  const CreateOrganization(this._repository);
  final BootstrapRepository _repository;

  Future<String> call(BootstrapOrganizationInput input) {
    return _repository.createOrganization(input);
  }
}
