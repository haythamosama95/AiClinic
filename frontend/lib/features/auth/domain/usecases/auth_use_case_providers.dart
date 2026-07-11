import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/data/permission_repository.dart';
import 'package:ai_clinic/features/auth/domain/usecases/clear_persisted_session.dart';
import 'package:ai_clinic/features/auth/domain/usecases/load_granted_permissions.dart';
import 'package:ai_clinic/features/auth/domain/usecases/refresh_session.dart';
import 'package:ai_clinic/features/auth/domain/usecases/sign_in.dart';
import 'package:ai_clinic/features/auth/domain/usecases/sign_out.dart';

final signInUseCaseProvider = Provider((ref) => SignIn(ref.watch(authRepositoryProvider)));
final signOutUseCaseProvider = Provider((ref) => SignOut(ref.watch(authRepositoryProvider)));
final refreshSessionUseCaseProvider = Provider((ref) => RefreshSession(ref.watch(authRepositoryProvider)));
final clearPersistedSessionUseCaseProvider = Provider(
  (ref) => ClearPersistedSession(ref.watch(authRepositoryProvider)),
);
final loadGrantedPermissionsUseCaseProvider = Provider(
  (ref) => LoadGrantedPermissions(ref.watch(permissionRepositoryProvider)),
);
