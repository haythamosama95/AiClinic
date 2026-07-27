import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'AiClinic'**
  String get appTitle;

  /// No description provided for @patients.
  ///
  /// In en, this message translates to:
  /// **'Patients'**
  String get patients;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResults;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @discardChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChangesTitle;

  /// No description provided for @discardChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. Are you sure you want to leave?'**
  String get discardChangesMessage;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @registerPatient.
  ///
  /// In en, this message translates to:
  /// **'Register patient'**
  String get registerPatient;

  /// No description provided for @patientDetail.
  ///
  /// In en, this message translates to:
  /// **'Patient detail'**
  String get patientDetail;

  /// No description provided for @editPatient.
  ///
  /// In en, this message translates to:
  /// **'Edit patient'**
  String get editPatient;

  /// No description provided for @manageStaff.
  ///
  /// In en, this message translates to:
  /// **'Manage staff'**
  String get manageStaff;

  /// No description provided for @networkUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unable to connect to the server. Please check your network connection.'**
  String get networkUnavailable;

  /// No description provided for @operationTimedOut.
  ///
  /// In en, this message translates to:
  /// **'The operation timed out. Please try again.'**
  String get operationTimedOut;

  /// No description provided for @unexpectedError.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred. Please try again or contact support.'**
  String get unexpectedError;

  /// No description provided for @genderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get genderMale;

  /// No description provided for @genderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get genderFemale;

  /// No description provided for @genderOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get genderOther;

  /// No description provided for @genderPreferNotToSay.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get genderPreferNotToSay;

  /// No description provided for @genderUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get genderUnknown;

  /// No description provided for @genderNotSpecified.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get genderNotSpecified;

  /// No description provided for @patientDetailBreadcrumb.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get patientDetailBreadcrumb;

  /// No description provided for @patientNotFound.
  ///
  /// In en, this message translates to:
  /// **'Patient not found'**
  String get patientNotFound;

  /// No description provided for @patientNotFoundDescription.
  ///
  /// In en, this message translates to:
  /// **'The patient record you requested does not exist or has been removed.'**
  String get patientNotFoundDescription;

  /// No description provided for @backToPatients.
  ///
  /// In en, this message translates to:
  /// **'Back to patients'**
  String get backToPatients;

  /// No description provided for @pastVisits.
  ///
  /// In en, this message translates to:
  /// **'Past visits'**
  String get pastVisits;

  /// No description provided for @upcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcoming;

  /// No description provided for @visits.
  ///
  /// In en, this message translates to:
  /// **'Visits'**
  String get visits;

  /// No description provided for @documents.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documents;

  /// No description provided for @billing.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get billing;

  /// No description provided for @noVisitsYet.
  ///
  /// In en, this message translates to:
  /// **'No visits yet'**
  String get noVisitsYet;

  /// No description provided for @noVisitsYetDescription.
  ///
  /// In en, this message translates to:
  /// **'This patient has no recorded visits.'**
  String get noVisitsYetDescription;

  /// No description provided for @noUpcomingAppointments.
  ///
  /// In en, this message translates to:
  /// **'No upcoming appointments'**
  String get noUpcomingAppointments;

  /// No description provided for @noUpcomingAppointmentsDescription.
  ///
  /// In en, this message translates to:
  /// **'This patient has no scheduled appointments.'**
  String get noUpcomingAppointmentsDescription;

  /// No description provided for @noDocuments.
  ///
  /// In en, this message translates to:
  /// **'No documents'**
  String get noDocuments;

  /// No description provided for @noDocumentsDescription.
  ///
  /// In en, this message translates to:
  /// **'No documents have been uploaded for this patient yet.'**
  String get noDocumentsDescription;

  /// No description provided for @noInvoices.
  ///
  /// In en, this message translates to:
  /// **'No invoices'**
  String get noInvoices;

  /// No description provided for @noInvoicesDescription.
  ///
  /// In en, this message translates to:
  /// **'No billing records for this patient.'**
  String get noInvoicesDescription;

  /// No description provided for @billingNoAccess.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have access to billing records.'**
  String get billingNoAccess;

  /// No description provided for @attendingPhysician.
  ///
  /// In en, this message translates to:
  /// **'Attending physician'**
  String get attendingPhysician;

  /// No description provided for @linkedVisit.
  ///
  /// In en, this message translates to:
  /// **'Linked visit'**
  String get linkedVisit;

  /// No description provided for @patientFile.
  ///
  /// In en, this message translates to:
  /// **'Patient file'**
  String get patientFile;

  /// No description provided for @downloadFile.
  ///
  /// In en, this message translates to:
  /// **'Download file'**
  String get downloadFile;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @editingPatient.
  ///
  /// In en, this message translates to:
  /// **'Editing patient'**
  String get editingPatient;

  /// No description provided for @editPatientDescription.
  ///
  /// In en, this message translates to:
  /// **'Update the patient\'s demographic and clinical information.'**
  String get editPatientDescription;

  /// No description provided for @registeredAt.
  ///
  /// In en, this message translates to:
  /// **'Registered at'**
  String get registeredAt;

  /// No description provided for @newRecordMrsAssignedOnSave.
  ///
  /// In en, this message translates to:
  /// **'New record · MRN assigned on save'**
  String get newRecordMrsAssignedOnSave;

  /// No description provided for @editingSuffix.
  ///
  /// In en, this message translates to:
  /// **'Editing'**
  String get editingSuffix;

  /// No description provided for @invoiceBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get invoiceBalance;

  /// No description provided for @invoiceIssued.
  ///
  /// In en, this message translates to:
  /// **'Issued'**
  String get invoiceIssued;

  /// No description provided for @invoicePayments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get invoicePayments;

  /// No description provided for @invoicePaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get invoicePaid;

  /// No description provided for @invoiceNoPayments.
  ///
  /// In en, this message translates to:
  /// **'No payments yet'**
  String get invoiceNoPayments;

  /// No description provided for @invoiceInsuranceCovered.
  ///
  /// In en, this message translates to:
  /// **'Insurance covered'**
  String get invoiceInsuranceCovered;

  /// No description provided for @invoicePaymentRefund.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get invoicePaymentRefund;

  /// No description provided for @paymentMethodCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentMethodCash;

  /// No description provided for @paymentMethodCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get paymentMethodCard;

  /// No description provided for @paymentMethodBankTransfer.
  ///
  /// In en, this message translates to:
  /// **'Bank transfer'**
  String get paymentMethodBankTransfer;

  /// No description provided for @paymentMethodInsuranceSettlement.
  ///
  /// In en, this message translates to:
  /// **'Insurance'**
  String get paymentMethodInsuranceSettlement;

  /// No description provided for @invoiceStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get invoiceStatusDraft;

  /// No description provided for @invoiceStatusIssued.
  ///
  /// In en, this message translates to:
  /// **'Issued'**
  String get invoiceStatusIssued;

  /// No description provided for @invoiceStatusPartiallyPaid.
  ///
  /// In en, this message translates to:
  /// **'Partially paid'**
  String get invoiceStatusPartiallyPaid;

  /// No description provided for @invoiceStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get invoiceStatusPaid;

  /// No description provided for @invoiceStatusVoided.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get invoiceStatusVoided;

  /// No description provided for @recordChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'Record changed'**
  String get recordChangedTitle;

  /// No description provided for @recordChangedDescription.
  ///
  /// In en, this message translates to:
  /// **'This record was modified by someone else. Reload and discard your edits?'**
  String get recordChangedDescription;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @registeringAt.
  ///
  /// In en, this message translates to:
  /// **'Registering at '**
  String get registeringAt;

  /// No description provided for @yourActiveBranch.
  ///
  /// In en, this message translates to:
  /// **'your active branch'**
  String get yourActiveBranch;

  /// No description provided for @patientDetailsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Patient details'**
  String get patientDetailsSectionTitle;

  /// No description provided for @patientDetailsSectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Core information used to identify the patient and reach them for care.'**
  String get patientDetailsSectionDescription;

  /// No description provided for @fullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullNameLabel;

  /// No description provided for @fullNameHint.
  ///
  /// In en, this message translates to:
  /// **'Legal name as it appears on government ID.'**
  String get fullNameHint;

  /// No description provided for @fullNamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. Sara Hassan Ibrahim'**
  String get fullNamePlaceholder;

  /// No description provided for @dateOfBirthLabel.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get dateOfBirthLabel;

  /// No description provided for @dateOfBirthHint.
  ///
  /// In en, this message translates to:
  /// **'Used with name for duplicate detection.'**
  String get dateOfBirthHint;

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get selectDate;

  /// No description provided for @genderLabel.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get genderLabel;

  /// No description provided for @genderHint.
  ///
  /// In en, this message translates to:
  /// **'Optional. Shown on the patient profile.'**
  String get genderHint;

  /// No description provided for @selectGender.
  ///
  /// In en, this message translates to:
  /// **'Select gender'**
  String get selectGender;

  /// No description provided for @mobileNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get mobileNumberLabel;

  /// No description provided for @mobileNumberHint.
  ///
  /// In en, this message translates to:
  /// **'Used for reminders and duplicate checks.'**
  String get mobileNumberHint;

  /// No description provided for @maritalStateLabel.
  ///
  /// In en, this message translates to:
  /// **'Marital state'**
  String get maritalStateLabel;

  /// No description provided for @maritalStateHint.
  ///
  /// In en, this message translates to:
  /// **'Optional. Shown on the patient profile.'**
  String get maritalStateHint;

  /// No description provided for @selectMaritalState.
  ///
  /// In en, this message translates to:
  /// **'Select marital state'**
  String get selectMaritalState;

  /// No description provided for @clinicalNotesSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Clinical notes'**
  String get clinicalNotesSectionTitle;

  /// No description provided for @clinicalNotesSectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Optional context visible to staff on the patient profile.'**
  String get clinicalNotesSectionDescription;

  /// No description provided for @notesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesLabel;

  /// No description provided for @notesHelperText.
  ///
  /// In en, this message translates to:
  /// **'Allergies, referral source, or front-desk remarks.'**
  String get notesHelperText;

  /// No description provided for @notesPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. Referred by Dr. Nabil. Penicillin allergy noted verbally.'**
  String get notesPlaceholder;

  /// No description provided for @maritalStatusSingle.
  ///
  /// In en, this message translates to:
  /// **'Single'**
  String get maritalStatusSingle;

  /// No description provided for @maritalStatusMarried.
  ///
  /// In en, this message translates to:
  /// **'Married'**
  String get maritalStatusMarried;

  /// No description provided for @maritalStatusDivorced.
  ///
  /// In en, this message translates to:
  /// **'Divorced'**
  String get maritalStatusDivorced;

  /// No description provided for @maritalStatusWidowed.
  ///
  /// In en, this message translates to:
  /// **'Widowed'**
  String get maritalStatusWidowed;

  /// No description provided for @patientTableColumnPatient.
  ///
  /// In en, this message translates to:
  /// **'Patient'**
  String get patientTableColumnPatient;

  /// No description provided for @patientTableColumnPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get patientTableColumnPhone;

  /// No description provided for @patientTableColumnDob.
  ///
  /// In en, this message translates to:
  /// **'DOB'**
  String get patientTableColumnDob;

  /// No description provided for @patientTableColumnLastVisit.
  ///
  /// In en, this message translates to:
  /// **'Last visit'**
  String get patientTableColumnLastVisit;

  /// No description provided for @patientTableColumnNextVisit.
  ///
  /// In en, this message translates to:
  /// **'Next visit'**
  String get patientTableColumnNextVisit;

  /// No description provided for @patientPickerLabel.
  ///
  /// In en, this message translates to:
  /// **'Patient'**
  String get patientPickerLabel;

  /// No description provided for @patientPickerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name, MRN, email, or phone.'**
  String get patientPickerSearchHint;

  /// No description provided for @patientPickerSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search patients by name, MRN, email, or phone…'**
  String get patientPickerSearchPlaceholder;

  /// No description provided for @patientPickerSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not search patients.'**
  String get patientPickerSearchFailed;

  /// No description provided for @patientPickerClear.
  ///
  /// In en, this message translates to:
  /// **'Clear patient'**
  String get patientPickerClear;

  /// No description provided for @emDash.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get emDash;

  /// No description provided for @patientRowActionOpenDetails.
  ///
  /// In en, this message translates to:
  /// **'Open patient details'**
  String get patientRowActionOpenDetails;

  /// No description provided for @patientRowActionBookAppointment.
  ///
  /// In en, this message translates to:
  /// **'Book appointment'**
  String get patientRowActionBookAppointment;

  /// No description provided for @patientRowActionDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get patientRowActionDeactivate;

  /// No description provided for @patientRowActionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Patient actions'**
  String get patientRowActionsLabel;

  /// No description provided for @patientDeactivatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'{fullName} deactivated.'**
  String patientDeactivatedSuccess(String fullName);

  /// No description provided for @archivePatientDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Deactivate patient?'**
  String get archivePatientDialogTitle;

  /// No description provided for @archivePatientDialogDescription.
  ///
  /// In en, this message translates to:
  /// **'Deactivate {fullName}? They will be hidden from active lists but their records are preserved.'**
  String archivePatientDialogDescription(String fullName);

  /// No description provided for @archivePatientDialogConfirm.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get archivePatientDialogConfirm;

  /// No description provided for @patientsListTitle.
  ///
  /// In en, this message translates to:
  /// **'Patients'**
  String get patientsListTitle;

  /// No description provided for @patientsListDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage patient records, profiles, and medical history.'**
  String get patientsListDescription;

  /// No description provided for @patientsListAddPatient.
  ///
  /// In en, this message translates to:
  /// **'Add patient'**
  String get patientsListAddPatient;

  /// No description provided for @patientsListEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No patients yet'**
  String get patientsListEmptyTitle;

  /// No description provided for @patientsListEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'Add your first patient to start building records.'**
  String get patientsListEmptyDescription;

  /// No description provided for @patientsListNoAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'You do not have access to patient records'**
  String get patientsListNoAccessTitle;

  /// No description provided for @patientsListNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'No patients match'**
  String get patientsListNoMatchTitle;

  /// No description provided for @patientsListNoMatchDescription.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term or clear your filters.'**
  String get patientsListNoMatchDescription;

  /// No description provided for @patientsListClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get patientsListClearFilters;

  /// No description provided for @patientsListSearchChip.
  ///
  /// In en, this message translates to:
  /// **'Search: {query}'**
  String patientsListSearchChip(String query);

  /// No description provided for @patientsListLastVisitChip.
  ///
  /// In en, this message translates to:
  /// **'Last visit: {label}'**
  String patientsListLastVisitChip(String label);

  /// No description provided for @patientsListSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search patients by name, MRN, email, or phone…'**
  String get patientsListSearchPlaceholder;

  /// No description provided for @patientsListSearchAriaLabel.
  ///
  /// In en, this message translates to:
  /// **'Search patients'**
  String get patientsListSearchAriaLabel;

  /// No description provided for @patientsListSortAriaLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort patients'**
  String get patientsListSortAriaLabel;

  /// No description provided for @patientsListLastVisitSection.
  ///
  /// In en, this message translates to:
  /// **'Last visit'**
  String get patientsListLastVisitSection;

  /// No description provided for @patientsListSortNameAsc.
  ///
  /// In en, this message translates to:
  /// **'Name (A → Z)'**
  String get patientsListSortNameAsc;

  /// No description provided for @patientsListSortNameDesc.
  ///
  /// In en, this message translates to:
  /// **'Name (Z → A)'**
  String get patientsListSortNameDesc;

  /// No description provided for @patientsListSortLastVisitNewest.
  ///
  /// In en, this message translates to:
  /// **'Last visit (newest)'**
  String get patientsListSortLastVisitNewest;

  /// No description provided for @patientsListSortLastVisitOldest.
  ///
  /// In en, this message translates to:
  /// **'Last visit (oldest)'**
  String get patientsListSortLastVisitOldest;

  /// No description provided for @patientsListLastVisitAny.
  ///
  /// In en, this message translates to:
  /// **'Any time'**
  String get patientsListLastVisitAny;

  /// No description provided for @patientsListLastVisit30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get patientsListLastVisit30Days;

  /// No description provided for @patientsListLastVisit90Days.
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get patientsListLastVisit90Days;

  /// No description provided for @patientsListLastVisitOver90Days.
  ///
  /// In en, this message translates to:
  /// **'Over 90 days'**
  String get patientsListLastVisitOver90Days;

  /// No description provided for @patientsListLastVisitNever.
  ///
  /// In en, this message translates to:
  /// **'Never visited'**
  String get patientsListLastVisitNever;

  /// No description provided for @patientNameFallback.
  ///
  /// In en, this message translates to:
  /// **'Patient'**
  String get patientNameFallback;

  /// No description provided for @patientSectionsAriaLabel.
  ///
  /// In en, this message translates to:
  /// **'Patient sections'**
  String get patientSectionsAriaLabel;

  /// No description provided for @addPatientDescription.
  ///
  /// In en, this message translates to:
  /// **'Register a new patient at your active branch.'**
  String get addPatientDescription;

  /// No description provided for @duplicatePatientDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Possible duplicate found'**
  String get duplicatePatientDialogTitle;

  /// No description provided for @duplicatePatientDialogDescription.
  ///
  /// In en, this message translates to:
  /// **'A patient with similar details already exists. Review the matches below before creating a new record.'**
  String get duplicatePatientDialogDescription;

  /// No description provided for @duplicatePatientGoBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get duplicatePatientGoBack;

  /// No description provided for @duplicatePatientRegisterAnyway.
  ///
  /// In en, this message translates to:
  /// **'Register anyway'**
  String get duplicatePatientRegisterAnyway;

  /// No description provided for @duplicatePatientOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get duplicatePatientOpen;

  /// No description provided for @duplicatePatientMatchCountOne.
  ///
  /// In en, this message translates to:
  /// **'1 existing patient matches the details you entered.'**
  String get duplicatePatientMatchCountOne;

  /// No description provided for @duplicatePatientMatchCountMany.
  ///
  /// In en, this message translates to:
  /// **'{count} existing patients match the details you entered.'**
  String duplicatePatientMatchCountMany(int count);

  /// No description provided for @duplicatePatientDobLabel.
  ///
  /// In en, this message translates to:
  /// **'DOB {date}'**
  String duplicatePatientDobLabel(String date);

  /// No description provided for @patientsListFilteredBy.
  ///
  /// In en, this message translates to:
  /// **'Filtered by'**
  String get patientsListFilteredBy;

  /// No description provided for @patientsListClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get patientsListClearAll;

  /// No description provided for @patientFormSelectBranchBeforeRegister.
  ///
  /// In en, this message translates to:
  /// **'Select an active branch before registering a patient.'**
  String get patientFormSelectBranchBeforeRegister;

  /// No description provided for @patientFormCouldNotRegister.
  ///
  /// In en, this message translates to:
  /// **'Could not register the patient. Try again.'**
  String get patientFormCouldNotRegister;

  /// No description provided for @patientFormDetailsStillLoading.
  ///
  /// In en, this message translates to:
  /// **'Patient details are still loading. Try again.'**
  String get patientFormDetailsStillLoading;

  /// No description provided for @patientFormCouldNotUpdate.
  ///
  /// In en, this message translates to:
  /// **'Could not update the patient. Try again.'**
  String get patientFormCouldNotUpdate;

  /// No description provided for @patientFormRegisteredAtBranch.
  ///
  /// In en, this message translates to:
  /// **'{fullName} registered at {branchName}.'**
  String patientFormRegisteredAtBranch(String fullName, String branchName);

  /// No description provided for @patientFormPatientUpdated.
  ///
  /// In en, this message translates to:
  /// **'{fullName} updated.'**
  String patientFormPatientUpdated(String fullName);

  /// No description provided for @patientFormFullNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the patient\'s full name.'**
  String get patientFormFullNameRequired;

  /// No description provided for @patientFormFullNameMinLength.
  ///
  /// In en, this message translates to:
  /// **'Full name must be at least 2 characters.'**
  String get patientFormFullNameMinLength;

  /// No description provided for @patientFormMobileRequired.
  ///
  /// In en, this message translates to:
  /// **'Mobile number is required.'**
  String get patientFormMobileRequired;

  /// No description provided for @patientFormMobileDigitsOnly.
  ///
  /// In en, this message translates to:
  /// **'Only numbers are allowed.'**
  String get patientFormMobileDigitsOnly;

  /// No description provided for @patientFormMobileLength.
  ///
  /// In en, this message translates to:
  /// **'Mobile number must be 8 to 15 digits.'**
  String get patientFormMobileLength;

  /// No description provided for @patientRpcNotFound.
  ///
  /// In en, this message translates to:
  /// **'Patient was not found or you do not have access.'**
  String get patientRpcNotFound;

  /// No description provided for @patientRpcDuplicateWarning.
  ///
  /// In en, this message translates to:
  /// **'Similar patients were found. Review the list before continuing.'**
  String get patientRpcDuplicateWarning;

  /// No description provided for @patientRpcStalePatient.
  ///
  /// In en, this message translates to:
  /// **'This record was updated elsewhere. Reload and try again.'**
  String get patientRpcStalePatient;

  /// No description provided for @patientRpcPatientArchived.
  ///
  /// In en, this message translates to:
  /// **'This patient is archived and is not available.'**
  String get patientRpcPatientArchived;

  /// No description provided for @patientRpcForbidden.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to perform this action.'**
  String get patientRpcForbidden;

  /// No description provided for @patientRpcBranchRequired.
  ///
  /// In en, this message translates to:
  /// **'Select an active branch before registering a patient.'**
  String get patientRpcBranchRequired;

  /// No description provided for @patientRpcDefaultError.
  ///
  /// In en, this message translates to:
  /// **'The clinic service rejected this request.'**
  String get patientRpcDefaultError;

  /// No description provided for @appointmentTypePlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get appointmentTypePlanned;

  /// No description provided for @appointmentTypeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get appointmentTypeUnknown;

  /// No description provided for @visitStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get visitStatusInProgress;

  /// No description provided for @visitStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get visitStatusCompleted;

  /// No description provided for @appointmentStatusScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get appointmentStatusScheduled;

  /// No description provided for @appointmentStatusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get appointmentStatusConfirmed;

  /// No description provided for @appointmentStatusCheckedIn.
  ///
  /// In en, this message translates to:
  /// **'Checked in'**
  String get appointmentStatusCheckedIn;

  /// No description provided for @appointmentStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get appointmentStatusInProgress;

  /// No description provided for @appointmentStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get appointmentStatusCompleted;

  /// No description provided for @appointmentStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get appointmentStatusCancelled;

  /// No description provided for @appointmentStatusNoShow.
  ///
  /// In en, this message translates to:
  /// **'No-show'**
  String get appointmentStatusNoShow;

  /// No description provided for @appointmentStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get appointmentStatusUnknown;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
