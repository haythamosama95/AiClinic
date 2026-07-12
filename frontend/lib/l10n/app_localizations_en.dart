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

  @override
  String get patientDetailBreadcrumb => 'Not found';

  @override
  String get patientNotFound => 'Patient not found';

  @override
  String get patientNotFoundDescription =>
      'The patient record you requested does not exist or has been removed.';

  @override
  String get backToPatients => 'Back to patients';

  @override
  String get pastVisits => 'Past visits';

  @override
  String get upcoming => 'Upcoming';

  @override
  String get visits => 'Visits';

  @override
  String get documents => 'Documents';

  @override
  String get billing => 'Billing';

  @override
  String get noVisitsYet => 'No visits yet';

  @override
  String get noVisitsYetDescription => 'This patient has no recorded visits.';

  @override
  String get noUpcomingAppointments => 'No upcoming appointments';

  @override
  String get noUpcomingAppointmentsDescription =>
      'This patient has no scheduled appointments.';

  @override
  String get noDocuments => 'No documents';

  @override
  String get noDocumentsDescription =>
      'No documents have been uploaded for this patient yet.';

  @override
  String get noInvoices => 'No invoices';

  @override
  String get noInvoicesDescription => 'No billing records for this patient.';

  @override
  String get billingNoAccess => 'You don\'t have access to billing records.';

  @override
  String get attendingPhysician => 'Attending physician';

  @override
  String get linkedVisit => 'Linked visit';

  @override
  String get patientFile => 'Patient file';

  @override
  String get downloadFile => 'Download file';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get editingPatient => 'Editing patient';

  @override
  String get editPatientDescription =>
      'Update the patient\'s demographic and clinical information.';

  @override
  String get registeredAt => 'Registered at';

  @override
  String get newRecordMrsAssignedOnSave => 'New record · MRN assigned on save';

  @override
  String get editingSuffix => 'Editing';

  @override
  String get invoiceBalance => 'Balance';

  @override
  String get invoiceIssued => 'Issued';

  @override
  String get invoicePayments => 'Payments';

  @override
  String get invoicePaid => 'Paid';

  @override
  String get invoiceNoPayments => 'No payments yet';

  @override
  String get invoiceInsuranceCovered => 'Insurance covered';

  @override
  String get invoicePaymentRefund => 'Refund';

  @override
  String get paymentMethodCash => 'Cash';

  @override
  String get paymentMethodCard => 'Card';

  @override
  String get paymentMethodBankTransfer => 'Bank transfer';

  @override
  String get paymentMethodInsuranceSettlement => 'Insurance';

  @override
  String get invoiceStatusDraft => 'Draft';

  @override
  String get invoiceStatusIssued => 'Issued';

  @override
  String get invoiceStatusPartiallyPaid => 'Partially paid';

  @override
  String get invoiceStatusPaid => 'Paid';

  @override
  String get invoiceStatusVoided => 'Voided';

  @override
  String get recordChangedTitle => 'Record changed';

  @override
  String get recordChangedDescription =>
      'This record was modified by someone else. Reload and discard your edits?';

  @override
  String get reload => 'Reload';

  @override
  String get registeringAt => 'Registering at ';

  @override
  String get yourActiveBranch => 'your active branch';

  @override
  String get patientDetailsSectionTitle => 'Patient details';

  @override
  String get patientDetailsSectionDescription =>
      'Core information used to identify the patient and reach them for care.';

  @override
  String get fullNameLabel => 'Full name';

  @override
  String get fullNameHint => 'Legal name as it appears on government ID.';

  @override
  String get fullNamePlaceholder => 'e.g. Sara Hassan Ibrahim';

  @override
  String get dateOfBirthLabel => 'Date of birth';

  @override
  String get dateOfBirthHint => 'Used with name for duplicate detection.';

  @override
  String get selectDate => 'Select date';

  @override
  String get genderLabel => 'Gender';

  @override
  String get genderHint => 'Optional. Shown on the patient profile.';

  @override
  String get selectGender => 'Select gender';

  @override
  String get mobileNumberLabel => 'Mobile number';

  @override
  String get mobileNumberHint => 'Used for reminders and duplicate checks.';

  @override
  String get maritalStateLabel => 'Marital state';

  @override
  String get maritalStateHint => 'Optional. Shown on the patient profile.';

  @override
  String get selectMaritalState => 'Select marital state';

  @override
  String get clinicalNotesSectionTitle => 'Clinical notes';

  @override
  String get clinicalNotesSectionDescription =>
      'Optional context visible to staff on the patient profile.';

  @override
  String get notesLabel => 'Notes';

  @override
  String get notesHelperText =>
      'Allergies, referral source, or front-desk remarks.';

  @override
  String get notesPlaceholder =>
      'e.g. Referred by Dr. Nabil. Penicillin allergy noted verbally.';

  @override
  String get maritalStatusSingle => 'Single';

  @override
  String get maritalStatusMarried => 'Married';

  @override
  String get maritalStatusDivorced => 'Divorced';

  @override
  String get maritalStatusWidowed => 'Widowed';
}
