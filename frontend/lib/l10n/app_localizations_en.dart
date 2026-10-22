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

  @override
  String get breadcrumbCalendar => 'Calendar';

  @override
  String get breadcrumbQueue => 'Queue';

  @override
  String get breadcrumbInvoices => 'Invoices';

  @override
  String get breadcrumbVisitDocumentation => 'Visit documentation';

  @override
  String get breadcrumbVisitChronicle => 'Visit chronicle';

  @override
  String get breadcrumbVisitBilling => 'Billing';

  @override
  String get breadcrumbNotFound => 'Not found';

  @override
  String get aiBillingOffersTitle => 'AI coverage';

  @override
  String get aiBillingOffersDescription =>
      'Manage your clinic’s plan, payments and support details.';

  @override
  String get aiBillingOffersEmpty =>
      'There are no plans available to purchase right now. Contact support and share your clinic reference if you need help.';

  @override
  String get aiBillingOffersEmptyTitle => 'No plans available';

  @override
  String get aiBillingOffersUnavailable => 'Plans could not be loaded';

  @override
  String get aiBillingOffersUnavailableDescription =>
      'Check your connection, then try again.';

  @override
  String get aiBillingRefreshPlans => 'Refresh plans';

  @override
  String get aiBillingCurrentCoverage => 'Current coverage';

  @override
  String get aiBillingAvailablePlans => 'Available plans';

  @override
  String get aiBillingNoActivePlan => 'No active plan';

  @override
  String get aiBillingNoActivePlanDescription =>
      'AI coverage is not active for this clinic. Choose an available plan below to get started.';

  @override
  String get aiBillingPlanActiveDescription =>
      'This plan is active for your clinic.';

  @override
  String get aiBillingRenewsOrEnds => 'Ends';

  @override
  String get aiBillingStarted => 'Started';

  @override
  String get aiBillingGraceEnds => 'Grace period ends';

  @override
  String get aiBillingCreditsIncluded => 'Credits included';

  @override
  String get aiBillingCreditsUsed => 'Credits used';

  @override
  String get aiBillingSupportReference => 'Clinic support reference';

  @override
  String get aiBillingSupportReferenceDescription =>
      'Give this reference to support when asking about billing.';

  @override
  String get aiBillingStatusUnavailable =>
      'Coverage details could not be loaded. Check your connection and try again.';

  @override
  String get aiBillingEndedReversed =>
      'A recent plan ending was reversed. Contact support if your coverage looks incorrect.';

  @override
  String get aiBillingPaymentHistory => 'Payment history';

  @override
  String get aiBillingNoPayments => 'No payments yet';

  @override
  String get aiBillingNoPaymentsDescription =>
      'Completed payments for this clinic will appear here.';

  @override
  String get aiBillingPaymentHistoryUnavailable =>
      'Payment history could not be loaded. Check your connection and try again.';

  @override
  String get aiBillingPaymentsLoadMore => 'Load more payments';

  @override
  String get aiBillingBrowsePlans => 'Browse plans';

  @override
  String get aiBillingTermsTitle => 'Terms of service';

  @override
  String get aiBillingAcceptTerms => 'I accept the current terms';

  @override
  String get aiBillingContinue => 'Continue';

  @override
  String get aiBillingContactTitle => 'Billing contact';

  @override
  String get aiBillingContactName => 'Name';

  @override
  String get aiBillingContactEmail => 'Email';

  @override
  String get aiBillingContactPhone => 'Phone';

  @override
  String get aiBillingContactSave => 'Save contact';

  @override
  String get aiBillingCheckoutTitle => 'Checkout';

  @override
  String get aiBillingCheckoutSubmit => 'Pay now';

  @override
  String get aiBillingCheckoutWaiting => 'Waiting';

  @override
  String get aiBillingCheckoutFailed => 'Failed';

  @override
  String get aiBillingCheckoutPaid => 'Paid';

  @override
  String get aiBillingCheckoutActive => 'Active';

  @override
  String get aiBillingCheckoutAbandoned => 'Abandoned';

  @override
  String get aiBillingStartsAfterCurrentTerm => 'starts after the current term';

  @override
  String get aiBillingErrorOfferUnavailable =>
      'This offer is no longer available. Review the updated price before paying.';

  @override
  String get aiBillingErrorBillingContactRequired =>
      'Add a billing contact before checkout.';

  @override
  String get aiBillingErrorTermsNotAccepted =>
      'Accept the current terms before checkout.';

  @override
  String get aiBillingErrorProviderUnavailable =>
      'The payment provider is unavailable. Try again later.';

  @override
  String get aiBillingErrorRateLimited =>
      'Too many billing requests. Try again later.';

  @override
  String get aiBillingRefresh => 'Refresh billing';

  @override
  String get aiBillingProjectionPending =>
      'Coverage update requested. Your plan and credits may take a few minutes to appear. Refresh to check again.';

  @override
  String get aiBillingProjectionPullFailed =>
      'Coverage update could not be requested. Refresh to try again.';

  @override
  String get aiBillingNoticeDuplicatePayment =>
      'A payment for this clinic looks like a duplicate and is under review. Contact support if you were charged twice.';

  @override
  String get aiBillingNoticeLatePaymentHonoured =>
      'A payment arrived after its checkout window and was honoured.';

  @override
  String get aiBillingNoticePaymentWithheld =>
      'A payment is withheld because its details did not match. Contact support to resolve it.';

  @override
  String get aiBillingNoticeReversalRecorded =>
      'A payment reversal was recorded for this clinic. Check coverage and contact support if it looks wrong.';

  @override
  String get aiBillingNoticeTermsHeld =>
      'Some subscription terms are on hold and will not take effect until they are released.';

  @override
  String get aiNoticeUnavailable =>
      'Status information is unavailable right now.';

  @override
  String get aiNoticeAskAdministrator => 'ask your administrator';

  @override
  String get aiNoticeEndsSoonAdmin =>
      'Your AI coverage ends soon. Renew to avoid an interruption.';

  @override
  String get aiNoticeEndsSoonStaff => 'AI coverage ends soon.';

  @override
  String aiNoticeInGraceAdmin(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: '1 day left',
      zero: 'less than one day left',
    );
    return 'Your AI coverage is in its grace period: $_temp0. Renew to keep AI available.';
  }

  @override
  String aiNoticeInGraceStaff(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: '1 day left',
      zero: 'less than one day left',
    );
    return 'AI coverage is in its grace period: $_temp0.';
  }

  @override
  String get aiNoticeAllowanceLowAdmin =>
      'Most of this clinic\'s AI credits are used. Renew or add credits before they run out.';

  @override
  String get aiNoticeAllowanceLowStaff => 'AI credits are running low.';

  @override
  String get aiNoticeAllowanceExhaustedAdmin =>
      'This clinic\'s AI credits are used up. Renew to keep using AI.';

  @override
  String get aiNoticeAllowanceExhaustedStaff =>
      'AI credits for this clinic are used up.';

  @override
  String get aiNoticeLapsedAdmin =>
      'AI coverage has lapsed. Renew to use AI again.';

  @override
  String get aiNoticeLapsedStaff => 'AI coverage has lapsed.';

  @override
  String get aiNoticeEndedReversedAdmin =>
      'AI coverage ended after a plan ending was reversed. Contact support if it looks wrong.';

  @override
  String get aiNoticeEndedReversedStaff =>
      'AI coverage changed after a plan ending was reversed.';

  @override
  String get aiNoticeSuspendedAdmin =>
      'AI access is suspended for this clinic. Contact support to restore it.';

  @override
  String get aiNoticeSuspendedStaff =>
      'AI access is suspended for this clinic.';

  @override
  String get aiNoticeStatusStaleAdmin =>
      'AI status could not be confirmed recently, so the coverage shown may be out of date.';

  @override
  String get aiNoticeStatusStaleStaff => 'AI status may be out of date.';
}
