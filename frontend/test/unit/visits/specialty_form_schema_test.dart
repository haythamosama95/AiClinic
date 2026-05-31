import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/visits/domain/specialty_form_schema.dart';

void main() {
  group('SpecialtyFormSchema', () {
    test('trivial: parses properties with labels and required flags', () {
      final schema = SpecialtyFormSchema.parse({
        'type': 'object',
        'properties': {
          'pain_score': {'type': 'number', 'title': 'Pain score'},
          'notes': {'type': 'string'},
        },
        'required': ['pain_score'],
      });

      expect(schema.fields, hasLength(2));
      final pain = schema.fields.firstWhere((f) => f.key == 'pain_score');
      expect(pain.label, 'Pain score');
      expect(pain.required, isTrue);
      expect(schema.fields.firstWhere((f) => f.key == 'notes').required, isFalse);
    });

    test('advanced: validateValues flags missing required and unknown keys', () {
      final schema = SpecialtyFormSchema.parse({
        'properties': {
          'pain_score': {'type': 'number'},
        },
        'required': ['pain_score'],
      });

      final missingRequired = SpecialtyFormSchema.validateValues({'notes': 'x'}, schema);
      expect(missingRequired['pain_score'], isNotNull);

      final unknown = SpecialtyFormSchema.validateValues({'pain_score': 1, 'extra': 2}, schema);
      expect(unknown['extra'], 'Unknown field.');
    });

    test('edge case: encodeForSave omits empty strings and unknown keys', () {
      final schema = SpecialtyFormSchema.parse({
        'properties': {
          'pain_score': {'type': 'number'},
          'notes': {'type': 'string'},
        },
      });

      final encoded = schema.encodeForSave({'pain_score': '5', 'notes': '  ', 'other': 'x'});
      expect(encoded['pain_score'], 5);
      expect(encoded.containsKey('notes'), isFalse);
      expect(encoded.containsKey('other'), isFalse);
    });

    test('trivial: parse derives label from key and reads enum options', () {
      final schema = SpecialtyFormSchema.parse({
        'properties': {
          'pain_score': {'type': 'number'},
          'body_site': {
            'type': 'string',
            'enum': ['arm', 'leg'],
          },
        },
      });

      expect(schema.fields.firstWhere((f) => f.key == 'body_site').label, 'Body Site');
      expect(schema.fields.firstWhere((f) => f.key == 'body_site').enumValues, ['arm', 'leg']);
      expect(schema.fields.firstWhere((f) => f.key == 'body_site').isSelect, isTrue);
    });

    test('edge case: parse returns empty schema when properties missing', () {
      expect(SpecialtyFormSchema.parse({}).fields, isEmpty);
      expect(SpecialtyFormSchema.parse({'properties': 'not-a-map'}).fields, isEmpty);
    });

    test('invalid state: validateValues rejects bad number, boolean, and select', () {
      final schema = SpecialtyFormSchema.parse({
        'properties': {
          'pain_score': {'type': 'number', 'title': 'Pain score'},
          'follow_up': {'type': 'boolean', 'title': 'Follow up'},
          'site': {
            'type': 'string',
            'title': 'Site',
            'enum': ['arm', 'leg'],
          },
        },
      });

      final numberError = SpecialtyFormSchema.validateValues({'pain_score': 'not-a-number'}, schema);
      expect(numberError['pain_score'], 'Pain score must be a number.');

      final boolError = SpecialtyFormSchema.validateValues({'follow_up': 'maybe'}, schema);
      expect(boolError['follow_up'], 'Follow up must be yes or no.');

      final selectError = SpecialtyFormSchema.validateValues({'site': 'torso'}, schema);
      expect(selectError['site'], 'Choose a valid option.');
    });

    test('invalid state: validateValues flags null required fields', () {
      final schema = SpecialtyFormSchema.parse({
        'properties': {
          'pain_score': {'type': 'number', 'title': 'Pain score'},
        },
        'required': ['pain_score'],
      });

      final errors = SpecialtyFormSchema.validateValues({'pain_score': null}, schema);
      expect(errors['pain_score'], 'Pain score is required.');
    });

    test('advanced: encodeForSave coerces booleans and keeps select values', () {
      final schema = SpecialtyFormSchema.parse({
        'properties': {
          'follow_up': {'type': 'boolean'},
          'site': {
            'type': 'string',
            'enum': ['arm', 'leg'],
          },
          'pain_score': {'type': 'integer'},
        },
      });

      final encoded = schema.encodeForSave({'follow_up': 'true', 'site': 'arm', 'pain_score': '7'});

      expect(encoded['follow_up'], isTrue);
      expect(encoded['site'], 'arm');
      expect(encoded['pain_score'], 7);
    });

    test('edge case: validateValues returns no errors for empty schema', () {
      const schema = SpecialtyFormSchema();
      expect(SpecialtyFormSchema.validateValues({'anything': 1}, schema), isEmpty);
    });
  });
}
