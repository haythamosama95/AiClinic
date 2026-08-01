import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_label.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BreadcrumbTrail', () {
    test('append adds entry to end', () {
      const trail = BreadcrumbTrail([]);
      final next = trail.append(BreadcrumbEntries.hubPatients());

      expect(trail.entries, isEmpty);
      expect(next.entries, hasLength(1));
      expect(next.entries.first.id, 'hub:patients');
    });

    test('updateLabel replaces label for matching entry id', () {
      final trail = BreadcrumbTrail([
        BreadcrumbEntries.hubPatients(),
        BreadcrumbEntries.patient('p1', name: 'Placeholder'),
      ]);

      final updated = trail.updateLabel('patient:p1', const BreadcrumbLabel.fixed('Sara Ali'));

      expect((updated.entries[1].label as FixedBreadcrumbLabel).text, 'Sara Ali');
      expect((trail.entries[1].label as FixedBreadcrumbLabel).text, 'Placeholder');
    });

    test('parent and current resolve stack ends', () {
      final trail = BreadcrumbTrail([
        BreadcrumbEntries.hubInvoices(),
        BreadcrumbEntries.invoice('inv-1', number: 'INV-1'),
        BreadcrumbEntries.visitDocument('visit-1'),
      ]);

      expect(trail.parent?.id, 'invoice:inv-1');
      expect(trail.current?.id, 'visit-doc:visit-1');
    });

    test('parent is null for single-segment trail', () {
      final trail = BreadcrumbTrail([BreadcrumbEntries.hubQueue()]);

      expect(trail.parent, isNull);
      expect(trail.current?.id, 'hub:queue');
    });

    test('isWeakVisitDocumentDefault matches calendar deep-link shape', () {
      final weak = BreadcrumbTrail([BreadcrumbEntries.hubCalendar(), BreadcrumbEntries.visitDocument('visit-1')]);
      final upgraded = weak.append(BreadcrumbEntries.appointment('apt-1', label: 'Pat · Jan 1, 2026'));

      expect(weak.isWeakVisitDocumentDefault, isTrue);
      expect(upgraded.isWeakVisitDocumentDefault, isFalse);
    });

    test('mergePreservedLabelsFrom keeps resolved labels over placeholders', () {
      final incoming = BreadcrumbTrail([BreadcrumbEntries.hubPatients(), BreadcrumbEntries.patient('p1', name: '…')]);
      final current = BreadcrumbTrail([
        BreadcrumbEntries.hubPatients(),
        BreadcrumbEntries.patient('p1', name: 'Sara Ali'),
      ]);

      final merged = incoming.mergePreservedLabelsFrom(current);

      expect((merged.entries[1].label as FixedBreadcrumbLabel).text, 'Sara Ali');
    });
  });
}
