/// One doctor account row for local dev seeding.
class DevDoctorSeedSpec {
  const DevDoctorSeedSpec({required this.username, required this.fullName});

  final String username;
  final String fullName;

  static const devNamePrefix = '[Dev] ';
}

/// Demo doctors for appointment screens and schedule filtering.
abstract final class DevDoctorSeedData {
  static const String defaultPassword = 'DevDoctor123!';

  static const List<DevDoctorSeedSpec> doctors = [
    DevDoctorSeedSpec(username: 'dev_doc_01', fullName: '${DevDoctorSeedSpec.devNamePrefix}Dr Sara Nabil'),
    DevDoctorSeedSpec(username: 'dev_doc_02', fullName: '${DevDoctorSeedSpec.devNamePrefix}Dr Omar Adel'),
    DevDoctorSeedSpec(username: 'dev_doc_03', fullName: '${DevDoctorSeedSpec.devNamePrefix}Dr Lina Youssef'),
    DevDoctorSeedSpec(username: 'dev_doc_04', fullName: '${DevDoctorSeedSpec.devNamePrefix}Dr Karim Fathy'),
    DevDoctorSeedSpec(username: 'dev_doc_05', fullName: '${DevDoctorSeedSpec.devNamePrefix}Dr Mariam Sameh'),
  ];
}
