// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'AiClinic';

  @override
  String get patients => 'Patients';

  @override
  String get settings => 'Settings';

  @override
  String get signOut => 'Sign out';

  @override
  String get home => 'Home';

  @override
  String get loading => 'Loading…';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get create => 'Create';

  @override
  String get search => 'Search';

  @override
  String get noResults => 'No results found';

  @override
  String get error => 'Error';

  @override
  String get discardChangesTitle => 'Discard changes?';

  @override
  String get discardChangesMessage =>
      'You have unsaved changes. Are you sure you want to leave?';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get discard => 'Discard';

  @override
  String get registerPatient => 'Register patient';

  @override
  String get patientDetail => 'Patient detail';

  @override
  String get editPatient => 'Edit patient';

  @override
  String get manageStaff => 'Manage staff';

  @override
  String get networkUnavailable =>
      'Unable to connect to the server. Please check your network connection.';

  @override
  String get operationTimedOut => 'The operation timed out. Please try again.';

  @override
  String get unexpectedError =>
      'An unexpected error occurred. Please try again or contact support.';

  @override
  String get genderMale => 'Male';

  @override
  String get genderFemale => 'Female';

  @override
  String get genderOther => 'Other';

  @override
  String get genderPreferNotToSay => 'Prefer not to say';

  @override
  String get genderUnknown => 'Unknown';

  @override
  String get genderNotSpecified => 'Not specified';
}
