import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart';

class SignIn {
  const SignIn(this._repository);
  final AuthRepository _repository;

  Future<void> call({required String username, required String password}) {
    return _repository.signIn(username: username, password: password);
  }
}
