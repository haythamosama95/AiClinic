import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';

/// Optional per-branch configuration applied after a seeded service is created.
class DevClinicServiceBranchConfigSpec {
  const DevClinicServiceBranchConfigSpec({
    required this.branchIndex,
    this.status = 'active',
    this.priceOverride,
    this.promotion,
  });

  /// Zero-based index into [DevClinicSeedSpec.branches].
  final int branchIndex;
  final String status;
  final String? priceOverride;
  final DevClinicServicePromotionSeedSpec? promotion;
}

/// Time-boxed promotion applied to a seeded branch row.
class DevClinicServicePromotionSeedSpec {
  const DevClinicServicePromotionSeedSpec({
    required this.price,
    required this.startOffsetDays,
    required this.endOffsetDays,
  });

  final String price;
  final int startOffsetDays;
  final int endOffsetDays;
}

/// Service definition for dev clinic dummy data.
class DevClinicServiceSeedSpec {
  const DevClinicServiceSeedSpec({
    required this.name,
    required this.defaultPrice,
    this.globalStatus = GlobalStatus.active,
    this.assignAllBranches = true,
    this.branchConfigs = const [],
  });

  final String name;
  final String defaultPrice;
  final GlobalStatus globalStatus;
  final bool assignAllBranches;
  final List<DevClinicServiceBranchConfigSpec> branchConfigs;
}

/// Deterministic service catalog entries for dev clinic seeding.
abstract final class DevClinicSeedServiceCatalog {
  static const consultationServiceName = 'Dev Seed Consultation';

  static const services = <DevClinicServiceSeedSpec>[
    DevClinicServiceSeedSpec(name: consultationServiceName, defaultPrice: '100.00'),
    DevClinicServiceSeedSpec(
      name: 'Follow-up Consultation',
      defaultPrice: '75.00',
      branchConfigs: [
        DevClinicServiceBranchConfigSpec(branchIndex: 0, priceOverride: '65.00'),
        DevClinicServiceBranchConfigSpec(
          branchIndex: 1,
          promotion: DevClinicServicePromotionSeedSpec(price: '55.00', startOffsetDays: -7, endOffsetDays: 30),
        ),
      ],
    ),
    DevClinicServiceSeedSpec(name: 'Blood Pressure Monitoring', defaultPrice: '50.00'),
    DevClinicServiceSeedSpec(name: 'ECG (12-lead)', defaultPrice: '150.00'),
    DevClinicServiceSeedSpec(name: 'Complete Blood Count (CBC)', defaultPrice: '120.00'),
    DevClinicServiceSeedSpec(name: 'Urinalysis', defaultPrice: '80.00'),
    DevClinicServiceSeedSpec(name: 'Chest X-Ray', defaultPrice: '200.00'),
    DevClinicServiceSeedSpec(name: 'Abdominal Ultrasound', defaultPrice: '350.00'),
    DevClinicServiceSeedSpec(name: 'Wound Dressing', defaultPrice: '60.00'),
    DevClinicServiceSeedSpec(name: 'IV Fluid Administration', defaultPrice: '90.00'),
    DevClinicServiceSeedSpec(name: 'Vaccination (routine)', defaultPrice: '45.00'),
    DevClinicServiceSeedSpec(name: 'Minor Suturing', defaultPrice: '180.00'),
    DevClinicServiceSeedSpec(name: 'Dental Cleaning', defaultPrice: '250.00', globalStatus: GlobalStatus.inactive),
  ];
}
