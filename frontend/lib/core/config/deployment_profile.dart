import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:ai_clinic/core/errors/exceptions.dart';

/// Deployment modes supported by the checked-in bootstrap foundation.
enum DeploymentMode {
  local,
  // Reserved for future releases:
  // cloud,
  // hybrid,
}

extension DeploymentModeX on DeploymentMode {
  /// Returns the serialized value expected in the JSON profile.
  String get wireValue => switch (this) {
    DeploymentMode.local => 'local',
  };
}

/// Identifies whether the current machine is hosting or consuming the local stack.
enum SourceDeviceRole { serverNode, clientNode }

extension SourceDeviceRoleX on SourceDeviceRole {
  /// Parses the optional device role from profile JSON.
  static SourceDeviceRole? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();

    return switch (normalized) {
      null || '' => null,
      'server' || 'server-node' || 'server_node' => SourceDeviceRole.serverNode,
      'client' || 'client-node' || 'client_node' => SourceDeviceRole.clientNode,
      _ => null,
    };
  }

  /// Returns the serialized value expected in the JSON profile.
  String get wireValue => switch (this) {
    SourceDeviceRole.serverNode => 'server-node',
    SourceDeviceRole.clientNode => 'client-node',
  };
}

@immutable
/// Strongly typed view of the local deployment profile file.
class DeploymentProfile {
  const DeploymentProfile({
    required this.deploymentMode,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    this.aiServiceUrl,
    this.sourceDeviceRole,
    this.sourcePath,
  });

  final DeploymentMode deploymentMode;
  final Uri supabaseUrl;
  final String supabaseAnonKey;
  final Uri? aiServiceUrl;
  final SourceDeviceRole? sourceDeviceRole;
  final String? sourcePath;

  bool get isLocalOnly => deploymentMode == DeploymentMode.local;

  /// Decodes and validates a deployment profile from raw JSON text.
  static DeploymentProfile fromJsonString(String source, {String? sourcePath}) {
    final dynamic decoded;

    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw InvalidDeploymentProfileException('Deployment profile must be valid JSON.', details: error.message);
    }

    if (decoded is! Map) {
      throw const InvalidDeploymentProfileException('Deployment profile root must be a JSON object.');
    }

    return fromMap(Map<String, dynamic>.from(decoded), sourcePath: sourcePath);
  }

  /// Validates required fields and converts them into a typed profile model.
  static DeploymentProfile fromMap(Map<String, dynamic> values, {String? sourcePath}) {
    final deploymentModeValue = values['deployment_mode']?.toString().trim() ?? '';
    if (deploymentModeValue.isEmpty) {
      throw const InvalidDeploymentProfileException('The deployment profile is missing `deployment_mode`.');
    }

    if (deploymentModeValue != DeploymentMode.local.wireValue) {
      throw InvalidDeploymentProfileException(
        'Only "${DeploymentMode.local.wireValue}" deployment is supported. '
        'Received: "$deploymentModeValue".',
      );
    }

    final supabaseUrlValue = values['supabase_url']?.toString().trim() ?? '';
    if (supabaseUrlValue.isEmpty) {
      throw const InvalidDeploymentProfileException('The deployment profile is missing `supabase_url`.');
    }

    final parsedSupabaseUrl = _parseUri(supabaseUrlValue, fieldName: 'supabase_url');

    final anonKeyValue = values['supabase_anon_key']?.toString().trim() ?? '';
    if (anonKeyValue.isEmpty) {
      throw const InvalidDeploymentProfileException('The deployment profile is missing `supabase_anon_key`.');
    }

    final aiServiceUrlValue = values['ai_service_url']?.toString().trim();
    final sourceDeviceRoleValue = values['source_device_role']?.toString().trim();

    final parsedSourceDeviceRole = SourceDeviceRoleX.tryParse(sourceDeviceRoleValue);
    if ((sourceDeviceRoleValue?.isNotEmpty ?? false) && parsedSourceDeviceRole == null) {
      throw InvalidDeploymentProfileException(
        'The deployment profile contains an unsupported `source_device_role`.',
        details: sourceDeviceRoleValue,
      );
    }

    return DeploymentProfile(
      deploymentMode: DeploymentMode.local,
      supabaseUrl: parsedSupabaseUrl,
      supabaseAnonKey: anonKeyValue,
      aiServiceUrl: (aiServiceUrlValue == null || aiServiceUrlValue.isEmpty)
          ? null
          : _parseUri(aiServiceUrlValue, fieldName: 'ai_service_url'),
      sourceDeviceRole: parsedSourceDeviceRole,
      sourcePath: sourcePath,
    );
  }

  /// Serializes the profile back into the JSON shape used on disk.
  Map<String, dynamic> toJson() {
    return {
      'deployment_mode': deploymentMode.wireValue,
      'supabase_url': supabaseUrl.toString(),
      'supabase_anon_key': supabaseAnonKey,
      if (aiServiceUrl != null) 'ai_service_url': aiServiceUrl.toString(),
      if (sourceDeviceRole != null) 'source_device_role': sourceDeviceRole!.wireValue,
    };
  }

  /// Ensures URL fields are absolute HTTP(S) endpoints before startup uses them.
  static Uri _parseUri(String rawValue, {required String fieldName}) {
    final parsed = Uri.tryParse(rawValue);
    final isInvalid =
        parsed == null ||
        !parsed.hasScheme ||
        parsed.host.isEmpty ||
        (parsed.scheme != 'http' && parsed.scheme != 'https');

    if (isInvalid) {
      throw InvalidDeploymentProfileException(
        'The deployment profile contains an invalid `$fieldName` value.',
        details: rawValue,
      );
    }

    return parsed;
  }
}
