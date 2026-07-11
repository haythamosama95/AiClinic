import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_dummy_data.dart';

/// Preset clinic layout for the dev "fill dummy data" action.
abstract final class DevClinicSeedSpec {
  static const organizationName = BootstrapDummyData.organizationName;
  static const currencyCode = BootstrapDummyData.currencyCode;
  static const timezone = BootstrapDummyData.timezone;
  static const defaultStaffPassword = 'DemoPass1';
  static const patientsPerBranch = 16;
  static const patientNamePrefix = 'Dev Seed ';

  static const branches = <DevClinicBranchSpec>[
    DevClinicBranchSpec(
      name: 'Downtown Clinic',
      code: 'DTWN',
      address: '10 Tahrir Square, Cairo',
      phone: '+20 100 111 0001',
      mapsUrl: 'https://maps.example.com/demo-downtown',
      scheduleKind: DevClinicBranchScheduleKind.dailyNineToNine,
      branchStaff: [
        DevClinicStaffSpec(
          username: 'dev_b1_doc',
          fullName: 'Dev Downtown Doctor',
          role: DevClinicStaffRole.doctor,
          phone: '1001110101',
        ),
        DevClinicStaffSpec(
          username: 'dev_b1_rec',
          fullName: 'Dev Downtown Receptionist',
          role: DevClinicStaffRole.receptionist,
          phone: '1001110102',
        ),
      ],
    ),
    DevClinicBranchSpec(
      name: 'Uptown Clinic',
      code: 'UPTN',
      address: '22 Heliopolis Ave, Cairo',
      phone: '+20 100 111 0002',
      mapsUrl: 'https://maps.example.com/demo-uptown',
      scheduleKind: DevClinicBranchScheduleKind.dailyNineToNine,
      branchStaff: [
        DevClinicStaffSpec(
          username: 'dev_b2_doc',
          fullName: 'Dev Uptown Doctor',
          role: DevClinicStaffRole.doctor,
          phone: '1001110201',
        ),
        DevClinicStaffSpec(
          username: 'dev_b2_rec',
          fullName: 'Dev Uptown Receptionist',
          role: DevClinicStaffRole.receptionist,
          phone: '1001110202',
        ),
      ],
    ),
    DevClinicBranchSpec(
      name: 'Waterfront Clinic',
      code: 'WTRF',
      address: '5 Corniche Road, Alexandria',
      phone: '+20 100 111 0003',
      mapsUrl: 'https://maps.example.com/demo-waterfront',
      scheduleKind: DevClinicBranchScheduleKind.dailyNineToNine,
      branchStaff: [
        DevClinicStaffSpec(
          username: 'dev_b3_doc',
          fullName: 'Dev Waterfront Doctor',
          role: DevClinicStaffRole.doctor,
          phone: '1001110301',
        ),
        DevClinicStaffSpec(
          username: 'dev_b3_rec',
          fullName: 'Dev Waterfront Receptionist',
          role: DevClinicStaffRole.receptionist,
          phone: '1001110302',
        ),
      ],
    ),
  ];

  static const allBranchStaff = <DevClinicStaffSpec>[
    DevClinicStaffSpec(
      username: 'dev_all_doc',
      fullName: 'Dev Multi-Branch Doctor',
      role: DevClinicStaffRole.doctor,
      phone: '1001110901',
    ),
    DevClinicStaffSpec(
      username: 'dev_all_rec',
      fullName: 'Dev Multi-Branch Receptionist',
      role: DevClinicStaffRole.receptionist,
      phone: '1001110902',
    ),
  ];

  static const branchOpenTime = '09:00';
  static const branchCloseTime = '21:00';

  static BranchWorkingSchedule workingScheduleFor(DevClinicBranchScheduleKind kind) {
    return switch (kind) {
      DevClinicBranchScheduleKind.dailyNineToNine => _dailyNineAmToNinePm(),
    };
  }

  static BranchWorkingSchedule branchWorkingSchedule() => _dailyNineAmToNinePm();

  static String patientFullName({required String branchCode, required int index}) {
    return '$patientNamePrefix$branchCode #${index.toString().padLeft(3, '0')}';
  }

  static String patientPhone({required int branchIndex, required int patientIndex}) {
    return '2018${branchIndex.toString().padLeft(2, '0')}${patientIndex.toString().padLeft(4, '0')}';
  }

  /// Whether [username] belongs to a dev-seed staff account.
  static bool isDevSeedStaffUsername(String? username) {
    final normalized = username?.trim();
    return normalized != null && normalized.isNotEmpty && normalized.startsWith('dev_');
  }

  /// Known initial password for dev-seed staff (not retrievable from the backend).
  static String? knownPasswordForDevSeedStaff(String? username) {
    if (!isDevSeedStaffUsername(username)) {
      return null;
    }
    return defaultStaffPassword;
  }

  static BranchWorkingSchedule _dailyNineAmToNinePm() {
    return BranchWorkingSchedule(
      BranchWeekday.values
          .map(
            (day) => BranchWorkingDayHours(
              day: day,
              isWorkingDay: true,
              openTime: branchOpenTime,
              closeTime: branchCloseTime,
            ),
          )
          .toList(growable: false),
    );
  }
}

enum DevClinicBranchScheduleKind { dailyNineToNine }

enum DevClinicStaffRole { doctor, receptionist }

class DevClinicBranchSpec {
  const DevClinicBranchSpec({
    required this.name,
    required this.code,
    required this.address,
    required this.phone,
    required this.mapsUrl,
    required this.scheduleKind,
    required this.branchStaff,
  });

  final String name;
  final String code;
  final String address;
  final String phone;
  final String mapsUrl;
  final DevClinicBranchScheduleKind scheduleKind;
  final List<DevClinicStaffSpec> branchStaff;
}

class DevClinicStaffSpec {
  const DevClinicStaffSpec({required this.username, required this.fullName, required this.role, required this.phone});

  final String username;
  final String fullName;
  final DevClinicStaffRole role;
  final String phone;
}
