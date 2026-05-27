import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart';

class SignOut {
  const SignOut(this._repository);
  final AuthRepository _repository;

  Future<void> call() => _repository.signOut();
}
