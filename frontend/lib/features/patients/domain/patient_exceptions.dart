/// Thrown when a patient has been archived and cannot be viewed/edited.
class PatientArchivedException implements Exception {
  const PatientArchivedException([this.message = 'This patient is archived and is not available.']);

  final String message;

  @override
  String toString() => message;
}
