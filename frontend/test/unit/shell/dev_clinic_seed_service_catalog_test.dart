import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_service_catalog.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DevClinicSeedServiceCatalog', () {
    test('defines a consultation service used by billing seed scenarios', () {
      final consultation = DevClinicSeedServiceCatalog.services.firstWhere(
        (service) => service.name == DevClinicSeedServiceCatalog.consultationServiceName,
      );

      expect(consultation.defaultPrice, '100.00');
      expect(consultation.globalStatus, GlobalStatus.active);
      expect(consultation.assignAllBranches, isTrue);
    });

    test('includes active and inactive services with unique names', () {
      final names = DevClinicSeedServiceCatalog.services.map((service) => service.name).toList();

      expect(names.toSet().length, names.length);
      expect(names.length, greaterThanOrEqualTo(10));
      expect(
        DevClinicSeedServiceCatalog.services.where((service) => service.globalStatus == GlobalStatus.inactive),
        isNotEmpty,
      );
    });

    test('includes branch overrides and promotions for demo pricing', () {
      final followUp = DevClinicSeedServiceCatalog.services.firstWhere(
        (service) => service.name == 'Follow-up Consultation',
      );

      expect(followUp.branchConfigs, hasLength(2));
      expect(followUp.branchConfigs.any((config) => config.priceOverride != null), isTrue);
      expect(followUp.branchConfigs.any((config) => config.promotion != null), isTrue);
    });
  });
}
