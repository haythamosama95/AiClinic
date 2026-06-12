import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/settings/presentation/providers/role_permissions_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/role_permissions_matrix.dart';

/// Role permission matrix: administrators edit grant toggles per role column.
class RolePermissionsPage extends ConsumerWidget {
  const RolePermissionsPage({this.embedded = false, super.key});

  /// When true, omits the page scaffold (for use inside the settings tab).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    final matrixAsync = ref.watch(rolePermissionsProvider);

    ref.listen<AsyncValue<RolePermissionsUiState>>(rolePermissionsProvider, (previous, next) {
      final saveMessage = next.value?.saveMessage;
      if (saveMessage != null && saveMessage != previous?.value?.saveMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saveMessage)));
        ref.read(rolePermissionsProvider.notifier).clearSaveMessage();
      }

      final errorMessage = next.value?.errorMessage;
      if (errorMessage != null && errorMessage != previous?.value?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    });

    final body = _RolePermissionsBody(
      canAccess: AuthRouteGuard.canAccessPermissionMatrix(auth),
      matrixAsync: matrixAsync,
    );

    if (embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Role permissions')),
      body: body,
    );
  }
}

class _RolePermissionsBody extends ConsumerWidget {
  const _RolePermissionsBody({required this.canAccess, required this.matrixAsync});

  final bool canAccess;
  final AsyncValue<RolePermissionsUiState> matrixAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canAccess) {
      return const _CenteredMessage('Role permissions are available only to clinic administrators.');
    }

    return matrixAsync.when(
      loading: () => const Center(child: AppCircularProgress()),
      error: (error, _) => _CenteredMessage('Could not load permission matrix: $error'),
      data: (ui) {
        if (ui.permissionDenied) {
          return const _CenteredMessage('Role permissions are available only to clinic administrators.');
        }

        if (ui.matrix.permissionKeys.isEmpty) {
          return const _CenteredMessage('No permission rows are configured for this clinic.');
        }

        return Padding(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          child: RolePermissionsMatrix(ui: ui),
        );
      },
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
