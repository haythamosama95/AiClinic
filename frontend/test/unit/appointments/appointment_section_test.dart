import 'package:ai_clinic/features/appointments/presentation/models/appointment_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentSection', () {
    test('trivial: byId resolves every valid section id', () {
      for (final section in AppointmentSection.values) {
        expect(AppointmentSection.byId(section.id), section);
      }
    });

    test('edge case: unknown id returns null', () {
      expect(AppointmentSection.byId('unknown'), isNull);
    });

    test('stupid usage: empty string returns null', () {
      expect(AppointmentSection.byId(''), isNull);
    });

    test('advanced: appointmentSections covers all enum values in order', () {
      expect(appointmentSections, AppointmentSection.values);
    });

    test('regression: section ids are unique and labels are non-empty', () {
      final ids = appointmentSections.map((section) => section.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(appointmentSections.every((section) => section.label.trim().isNotEmpty), isTrue);
    });
  });
}
