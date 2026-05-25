import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/update_organization_input.dart';
import 'package:ai_clinic/features/settings/presentation/settings_rpc_messages.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

@immutable
class OrganizationSettingsUiState {
  const OrganizationSettingsUiState({
    this.profile,
    this.isSaving = false,
    this.permissionDenied = false,
    this.errorMessage,
    this.saveMessage,
    this.fieldErrors = const {},
  });

  final OrganizationProfile? profile;
  final bool isSaving;
  final bool permissionDenied;
  final String? errorMessage;
  final String? saveMessage;
  final Map<String, String> fieldErrors;

  OrganizationSettingsUiState copyWith({
    OrganizationProfile? profile,
    bool? isSaving,
    bool? permissionDenied,
    String? errorMessage,
    String? saveMessage,
    Map<String, String>? fieldErrors,
    bool clearError = false,
    bool clearSaveMessage = false,
    bool clearFieldErrors = false,
  }) {
    return OrganizationSettingsUiState(
      profile: profile ?? this.profile,
      isSaving: isSaving ?? this.isSaving,
      permissionDenied: permissionDenied ?? this.permissionDenied,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      saveMessage: clearSaveMessage ? null : (saveMessage ?? this.saveMessage),
      fieldErrors: clearFieldErrors ? const {} : (fieldErrors ?? this.fieldErrors),
    );
  }
}

final organizationSettingsProvider = AsyncNotifierProvider<OrganizationSettingsNotifier, OrganizationSettingsUiState>(
  OrganizationSettingsNotifier.new,
);

class OrganizationSettingsNotifier extends AsyncNotifier<OrganizationSettingsUiState> {
  @override
  Future<OrganizationSettingsUiState> build() async {
    final auth = ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessOrganizationSettings(auth)) {
      return const OrganizationSettingsUiState(permissionDenied: true);
    }

    final orgId = auth.context!.organizationId;
    if (orgId == null || orgId.isEmpty) {
      throw StateError('Missing organization id in session');
    }
    final profile = await ref.read(fetchOrganizationProfileUseCaseProvider)(organizationId: orgId);
    if (profile == null) {
      throw StateError('Organization profile not found for $orgId');
    }

    return OrganizationSettingsUiState(profile: profile);
  }

  void clearSaveMessage() {
    final current = state.value;
    if (current == null || current.saveMessage == null) {
      return;
    }
    state = AsyncData(current.copyWith(clearSaveMessage: true));
  }

  Future<bool> save({required String name, String? logoUrl, String? currencyCode, String? timezone}) async {
    final current = state.value;
    if (current == null || current.permissionDenied) {
      return false;
    }

    final normalizedName = OrganizationProfile.normalizeName(name);
    if (normalizedName == null) {
      state = AsyncData(
        current.copyWith(
          fieldErrors: {'name': 'Organization name is required.'},
          clearError: true,
          clearSaveMessage: true,
        ),
      );
      return false;
    }

    state = AsyncData(
      current.copyWith(isSaving: true, clearError: true, clearSaveMessage: true, clearFieldErrors: true),
    );
    AppLog.info('settings.organization.save.start');

    try {
      await ref.read(updateOrganizationUseCaseProvider)(
        UpdateOrganizationInput(
          name: normalizedName,
          logoUrl: logoUrl?.trim().isEmpty ?? true ? null : logoUrl!.trim(),
          currencyCode: currencyCode,
          timezone: timezone,
          settingsJson: current.profile?.settingsJson,
        ),
      );

      final refreshed = await ref.read(fetchOrganizationProfileUseCaseProvider)(
        organizationId: current.profile!.id,
      );

      state = AsyncData(
        OrganizationSettingsUiState(
          profile: refreshed ?? current.profile!.copyWith(name: normalizedName),
          saveMessage: 'Organization settings saved.',
        ),
      );
      AppLog.info('settings.organization.save.ok');
      return true;
    } on RpcFailure catch (error) {
      AppLog.warning('settings.organization.save.rpc_failed code=${error.code}');
      final fieldErrors = error.code == 'INVALID_INPUT' ? _fieldErrorsFromMessage(error.message) : <String, String>{};
      state = AsyncData(
        current.copyWith(isSaving: false, errorMessage: organizationMessageForRpc(error), fieldErrors: fieldErrors),
      );
      return false;
    } catch (error) {
      AppLog.warning('settings.organization.save.failed reason=${error.runtimeType}');
      state = AsyncData(
        current.copyWith(
          isSaving: false,
          errorMessage: 'Unable to save organization settings. Check connectivity and try again.',
        ),
      );
      return false;
    }
  }

  static Map<String, String> _fieldErrorsFromMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('currency')) {
      return {'currencyCode': message};
    }
    if (lower.contains('timezone')) {
      return {'timezone': message};
    }
    if (lower.contains('name')) {
      return {'name': message};
    }
    return {};
  }
}
