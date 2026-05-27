import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart';

class RefreshSession {
  const RefreshSession(this._repository);
  final AuthRepository _repository;

  Future<void> call() => _repository.refreshSession();
}
