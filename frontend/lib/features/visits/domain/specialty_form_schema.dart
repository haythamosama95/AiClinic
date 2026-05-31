import 'package:flutter/foundation.dart';

/// Parsed org specialty JSON Schema subset for visit documentation (V1-5 US3).
@immutable
class SpecialtyFormFieldDef {
  const SpecialtyFormFieldDef({
    required this.key,
    required this.type,
    required this.label,
    this.enumValues = const [],
    this.required = false,
  });

  final String key;
  final String type;
  final String label;
  final List<String> enumValues;
  final bool required;

  bool get isSelect => enumValues.isNotEmpty;
}

@immutable
class SpecialtyFormSchema {
  const SpecialtyFormSchema({this.fields = const []});

  final List<SpecialtyFormFieldDef> fields;

  bool get hasFields => fields.isNotEmpty;

  static SpecialtyFormSchema parse(Map<String, dynamic> schemaJson) {
    final properties = schemaJson['properties'];
    if (properties is Map<String, dynamic>) {
      return _parseFromProperties(properties, schemaJson['required']);
    }
    if (properties is Map) {
      return _parseFromProperties(Map<String, dynamic>.from(properties), schemaJson['required']);
    }
    return const SpecialtyFormSchema();
  }

  static SpecialtyFormSchema _parseFromProperties(Map<String, dynamic> properties, Object? requiredRaw) {
    final requiredKeys = <String>{};
    if (requiredRaw is List) {
      for (final item in requiredRaw) {
        if (item is String && item.isNotEmpty) {
          requiredKeys.add(item);
        }
      }
    }

    final fields = <SpecialtyFormFieldDef>[];
    for (final entry in properties.entries) {
      final key = entry.key;
      final def = entry.value;
      if (key.isEmpty || def is! Map) {
        continue;
      }
      final defMap = def is Map<String, dynamic> ? def : Map<String, dynamic>.from(def);
      final type = defMap['type']?.toString() ?? 'string';
      final title = defMap['title']?.toString().trim();
      final label = title == null || title.isEmpty ? _labelFromKey(key) : title;

      final enumRaw = defMap['enum'];
      final enumValues = <String>[];
      if (enumRaw is List) {
        for (final value in enumRaw) {
          final text = value?.toString();
          if (text != null && text.isNotEmpty) {
            enumValues.add(text);
          }
        }
      }

      fields.add(
        SpecialtyFormFieldDef(
          key: key,
          type: type,
          label: label,
          enumValues: enumValues,
          required: requiredKeys.contains(key),
        ),
      );
    }

    fields.sort((a, b) => a.key.compareTo(b.key));
    return SpecialtyFormSchema(fields: fields);
  }

  static String _labelFromKey(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  /// Client-side validation before RPC; mirrors backend required/unknown-key rules.
  static Map<String, String> validateValues(Map<String, dynamic> values, SpecialtyFormSchema schema) {
    final errors = <String, String>{};
    if (!schema.hasFields) {
      return errors;
    }

    final allowedKeys = schema.fields.map((f) => f.key).toSet();

    for (final key in values.keys) {
      if (!allowedKeys.contains(key)) {
        errors[key] = 'Unknown field.';
      }
    }

    for (final field in schema.fields) {
      if (!values.containsKey(field.key)) {
        if (field.required) {
          errors[field.key] = '${field.label} is required.';
        }
        continue;
      }

      final value = values[field.key];
      if (value == null) {
        if (field.required) {
          errors[field.key] = '${field.label} is required.';
        }
        continue;
      }

      switch (field.type) {
        case 'number':
        case 'integer':
          if (value is! num && int.tryParse(value.toString()) == null && double.tryParse(value.toString()) == null) {
            errors[field.key] = '${field.label} must be a number.';
          }
        case 'boolean':
          if (value is! bool && value.toString() != 'true' && value.toString() != 'false') {
            errors[field.key] = '${field.label} must be yes or no.';
          }
        case 'string':
          if (field.isSelect && value is String && !field.enumValues.contains(value)) {
            errors[field.key] = 'Choose a valid option.';
          }
      }
    }

    return errors;
  }

  /// Values sent to `save_soap_note` (only defined schema keys).
  Map<String, dynamic> encodeForSave(Map<String, dynamic> draft) {
    if (!hasFields) {
      return const {};
    }

    final encoded = <String, dynamic>{};
    for (final field in fields) {
      if (!draft.containsKey(field.key)) {
        continue;
      }
      final raw = draft[field.key];
      if (raw == null) {
        continue;
      }

      switch (field.type) {
        case 'number':
        case 'integer':
          if (raw is num) {
            encoded[field.key] = raw;
          } else {
            final parsed = num.tryParse(raw.toString());
            if (parsed != null) {
              encoded[field.key] = parsed;
            }
          }
        case 'boolean':
          if (raw is bool) {
            encoded[field.key] = raw;
          } else {
            encoded[field.key] = raw.toString() == 'true';
          }
        default:
          final text = raw.toString().trim();
          if (text.isNotEmpty) {
            encoded[field.key] = text;
          }
      }
    }
    return encoded;
  }
}
