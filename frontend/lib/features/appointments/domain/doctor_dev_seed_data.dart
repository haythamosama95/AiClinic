/// One doctor account row for local dev seeding.
class DoctorDevSeedSpec {
  const DoctorDevSeedSpec({required this.username, required this.fullName});

  final String username;
  final String fullName;

  static const devNamePrefix = '[Dev] ';
}

/// Demo doctors for appointment screens and schedule filtering.
abstract final class DoctorDevSeedData {
  static const String defaultPassword = 'DevDoctor123!';

  static const List<DoctorDevSeedSpec> doctors = [
    DoctorDevSeedSpec(username: 'dev_doc_01', fullName: '${DoctorDevSeedSpec.devNamePrefix}Dr Sara Nabil'),
    DoctorDevSeedSpec(username: 'dev_doc_02', fullName: '${DoctorDevSeedSpec.devNamePrefix}Dr Omar Adel'),
    DoctorDevSeedSpec(username: 'dev_doc_03', fullName: '${DoctorDevSeedSpec.devNamePrefix}Dr Lina Youssef'),
    DoctorDevSeedSpec(username: 'dev_doc_04', fullName: '${DoctorDevSeedSpec.devNamePrefix}Dr Karim Fathy'),
    DoctorDevSeedSpec(username: 'dev_doc_05', fullName: '${DoctorDevSeedSpec.devNamePrefix}Dr Mariam Sameh'),
  ];
}
