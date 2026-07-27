// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'AiClinic';

  @override
  String get patients => 'المرضى';

  @override
  String get settings => 'الإعدادات';

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get home => 'الرئيسية';

  @override
  String get loading => 'جارٍ التحميل…';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get delete => 'حذف';

  @override
  String get edit => 'تعديل';

  @override
  String get create => 'إنشاء';

  @override
  String get search => 'بحث';

  @override
  String get noResults => 'لا توجد نتائج';

  @override
  String get error => 'خطأ';

  @override
  String get discardChangesTitle => 'تجاهل التغييرات؟';

  @override
  String get discardChangesMessage =>
      'لديك تغييرات غير محفوظة. هل أنت متأكد أنك تريد المغادرة؟';

  @override
  String get keepEditing => 'متابعة التعديل';

  @override
  String get discard => 'تجاهل';

  @override
  String get visitUnsavedChangesTitle => 'وثائق غير محفوظة';

  @override
  String get visitUnsavedChangesMessage =>
      'لديك وثائق سريرية غير محفوظة. احفظ عملك، أو تجاهل التغييرات، أو ابقَ في هذه الصفحة.';

  @override
  String get visitUnsavedChangesSaveAndLeave => 'حفظ والمغادرة';

  @override
  String get visitUnsavedChangesDiscardAndLeave => 'تجاهل والمغادرة';

  @override
  String get visitUnsavedChangesStay => 'البقاء في الصفحة';

  @override
  String get patientSummaryFallbackName => 'مريض';

  @override
  String get appointmentWindowFallbackLabel => 'موعد';

  @override
  String get registerPatient => 'تسجيل مريض';

  @override
  String get patientDetail => 'تفاصيل المريض';

  @override
  String get editPatient => 'تعديل المريض';

  @override
  String get manageStaff => 'إدارة الموظفين';

  @override
  String get networkUnavailable =>
      'تعذّر الاتصال بالخادم. يرجى التحقق من اتصال الشبكة.';

  @override
  String get operationTimedOut => 'انتهت مهلة العملية. يرجى المحاولة مرة أخرى.';

  @override
  String get unexpectedError =>
      'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى أو التواصل مع الدعم.';

  @override
  String get genderMale => 'ذكر';

  @override
  String get genderFemale => 'أنثى';

  @override
  String get genderOther => 'آخر';

  @override
  String get genderPreferNotToSay => 'أفضل عدم الإفصاح';

  @override
  String get genderUnknown => 'غير معروف';

  @override
  String get genderNotSpecified => 'غير محدد';

  @override
  String get patientDetailBreadcrumb => 'غير موجود';

  @override
  String get patientNotFound => 'المريض غير موجود';

  @override
  String get patientNotFoundDescription =>
      'سجل المريض الذي طلبته غير موجود أو تمت إزالته.';

  @override
  String get backToPatients => 'العودة إلى المرضى';

  @override
  String get pastVisits => 'الزيارات السابقة';

  @override
  String get upcoming => 'القادمة';

  @override
  String get visits => 'الزيارات';

  @override
  String get documents => 'المستندات';

  @override
  String get billing => 'الفواتير';

  @override
  String get noVisitsYet => 'لا توجد زيارات بعد';

  @override
  String get noVisitsYetDescription => 'لا توجد زيارات مسجلة لهذا المريض.';

  @override
  String get noUpcomingAppointments => 'لا توجد مواعيد قادمة';

  @override
  String get noUpcomingAppointmentsDescription =>
      'لا توجد مواعيد مجدولة لهذا المريض.';

  @override
  String get noDocuments => 'لا توجد مستندات';

  @override
  String get noDocumentsDescription =>
      'لم يتم تحميل أي مستندات لهذا المريض بعد.';

  @override
  String get noInvoices => 'لا توجد فواتير';

  @override
  String get noInvoicesDescription => 'لا توجد سجلات فوترة لهذا المريض.';

  @override
  String get billingNoAccess => 'ليس لديك صلاحية الوصول إلى سجلات الفوترة.';

  @override
  String get attendingPhysician => 'الطبيب المعالج';

  @override
  String get linkedVisit => 'الزيارة المرتبطة';

  @override
  String get patientFile => 'ملف المريض';

  @override
  String get downloadFile => 'تنزيل الملف';

  @override
  String get saveChanges => 'حفظ التغييرات';

  @override
  String get editingPatient => 'تعديل بيانات المريض';

  @override
  String get editPatientDescription =>
      'حدّث المعلومات الديموغرافية والسريرية للمريض.';

  @override
  String get registeredAt => 'مسجّل في';

  @override
  String get newRecordMrsAssignedOnSave =>
      'سجل جديد · يُعيَّن رقم الملف الطبي عند الحفظ';

  @override
  String get editingSuffix => 'تعديل';

  @override
  String get invoiceBalance => 'الرصيد';

  @override
  String get invoiceIssued => 'تاريخ الإصدار';

  @override
  String get invoicePayments => 'المدفوعات';

  @override
  String get invoicePaid => 'مدفوع';

  @override
  String get invoiceNoPayments => 'لا توجد مدفوعات بعد';

  @override
  String get invoiceInsuranceCovered => 'تغطية التأمين';

  @override
  String get invoicePaymentRefund => 'استرداد';

  @override
  String get paymentMethodCash => 'نقدًا';

  @override
  String get paymentMethodCard => 'بطاقة';

  @override
  String get paymentMethodBankTransfer => 'تحويل بنكي';

  @override
  String get paymentMethodInsuranceSettlement => 'تأمين';

  @override
  String get invoiceStatusDraft => 'مسودة';

  @override
  String get invoiceStatusIssued => 'صادرة';

  @override
  String get invoiceStatusPartiallyPaid => 'مدفوعة جزئيًا';

  @override
  String get invoiceStatusPaid => 'مدفوعة';

  @override
  String get invoiceStatusVoided => 'مُبطَلة';

  @override
  String get recordChangedTitle => 'تغيّر السجل';

  @override
  String get recordChangedDescription =>
      'عُدّل هذا السجل من قبل شخص آخر. إعادة التحميل وتجاهل تعديلاتك؟';

  @override
  String get reload => 'إعادة التحميل';

  @override
  String get registeringAt => 'التسجيل في ';

  @override
  String get yourActiveBranch => 'فرعك النشط';

  @override
  String get patientDetailsSectionTitle => 'بيانات المريض';

  @override
  String get patientDetailsSectionDescription =>
      'المعلومات الأساسية لتحديد المريض والتواصل معه للرعاية.';

  @override
  String get fullNameLabel => 'الاسم الكامل';

  @override
  String get fullNameHint => 'الاسم القانوني كما يظهر في الهوية الرسمية.';

  @override
  String get fullNamePlaceholder => 'مثال: Sara Hassan Ibrahim';

  @override
  String get dateOfBirthLabel => 'تاريخ الميلاد';

  @override
  String get dateOfBirthHint => 'يُستخدم مع الاسم للكشف عن التكرار.';

  @override
  String get selectDate => 'اختر التاريخ';

  @override
  String get genderLabel => 'الجنس';

  @override
  String get genderHint => 'اختياري. يظهر في ملف المريض.';

  @override
  String get selectGender => 'اختر الجنس';

  @override
  String get mobileNumberLabel => 'رقم الجوال';

  @override
  String get mobileNumberHint => 'يُستخدم للتذكيرات والتحقق من التكرار.';

  @override
  String get maritalStateLabel => 'الحالة الاجتماعية';

  @override
  String get maritalStateHint => 'اختياري. تظهر في ملف المريض.';

  @override
  String get selectMaritalState => 'اختر الحالة الاجتماعية';

  @override
  String get clinicalNotesSectionTitle => 'ملاحظات سريرية';

  @override
  String get clinicalNotesSectionDescription =>
      'سياق اختياري يظهر للموظفين في ملف المريض.';

  @override
  String get notesLabel => 'ملاحظات';

  @override
  String get notesHelperText => 'الحساسية، مصدر الإحالة، أو ملاحظات الاستقبال.';

  @override
  String get notesPlaceholder =>
      'مثال: أُحيل من Dr. Nabil. حساسية بنسلين وُجدت شفهيًا.';

  @override
  String get maritalStatusSingle => 'أعزب';

  @override
  String get maritalStatusMarried => 'متزوج';

  @override
  String get maritalStatusDivorced => 'مطلّق';

  @override
  String get maritalStatusWidowed => 'أرمل';

  @override
  String get patientTableColumnPatient => 'المريض';

  @override
  String get patientTableColumnPhone => 'الهاتف';

  @override
  String get patientTableColumnDob => 'تاريخ الميلاد';

  @override
  String get patientTableColumnLastVisit => 'آخر زيارة';

  @override
  String get patientTableColumnNextVisit => 'الزيارة القادمة';

  @override
  String get patientPickerLabel => 'المريض';

  @override
  String get patientPickerSearchHint =>
      'ابحث بالاسم أو رقم الملف الطبي أو البريد الإلكتروني أو الهاتف.';

  @override
  String get patientPickerSearchPlaceholder =>
      'ابحث عن المرضى بالاسم أو رقم الملف الطبي أو البريد الإلكتروني أو الهاتف…';

  @override
  String get patientPickerSearchFailed => 'تعذّر البحث عن المرضى.';

  @override
  String get patientPickerClear => 'مسح المريض';

  @override
  String get emDash => '—';

  @override
  String get patientRowActionOpenDetails => 'فتح تفاصيل المريض';

  @override
  String get patientRowActionBookAppointment => 'حجز موعد';

  @override
  String get patientRowActionDeactivate => 'إلغاء التفعيل';

  @override
  String get patientRowActionsLabel => 'إجراءات المريض';

  @override
  String patientDeactivatedSuccess(String fullName) {
    return 'تم إلغاء تفعيل $fullName.';
  }

  @override
  String get archivePatientDialogTitle => 'إلغاء تفعيل المريض؟';

  @override
  String archivePatientDialogDescription(String fullName) {
    return 'إلغاء تفعيل $fullName؟ سيُخفى من القوائم النشطة مع الاحتفاظ بسجلاته.';
  }

  @override
  String get archivePatientDialogConfirm => 'إلغاء التفعيل';

  @override
  String get patientsListTitle => 'المرضى';

  @override
  String get patientsListDescription =>
      'إدارة سجلات المرضى والملفات والتاريخ الطبي.';

  @override
  String get patientsListAddPatient => 'إضافة مريض';

  @override
  String get patientsListEmptyTitle => 'لا يوجد مرضى بعد';

  @override
  String get patientsListEmptyDescription => 'أضف أول مريض لبدء بناء السجلات.';

  @override
  String get patientsListNoAccessTitle =>
      'ليس لديك صلاحية الوصول إلى سجلات المرضى';

  @override
  String get patientsListNoMatchTitle => 'لا يوجد مرضى مطابقون';

  @override
  String get patientsListNoMatchDescription =>
      'جرّب مصطلح بحث مختلفًا أو امسح عوامل التصفية.';

  @override
  String get patientsListClearFilters => 'مسح عوامل التصفية';

  @override
  String patientsListSearchChip(String query) {
    return 'بحث: $query';
  }

  @override
  String patientsListLastVisitChip(String label) {
    return 'آخر زيارة: $label';
  }

  @override
  String get patientsListSearchPlaceholder =>
      'ابحث عن المرضى بالاسم أو رقم الملف أو البريد أو الهاتف…';

  @override
  String get patientsListSearchAriaLabel => 'بحث عن المرضى';

  @override
  String get patientsListSortAriaLabel => 'ترتيب المرضى';

  @override
  String get patientsListLastVisitSection => 'آخر زيارة';

  @override
  String get patientsListSortNameAsc => 'الاسم (أ → ي)';

  @override
  String get patientsListSortNameDesc => 'الاسم (ي → أ)';

  @override
  String get patientsListSortLastVisitNewest => 'آخر زيارة (الأحدث)';

  @override
  String get patientsListSortLastVisitOldest => 'آخر زيارة (الأقدم)';

  @override
  String get patientsListLastVisitAny => 'أي وقت';

  @override
  String get patientsListLastVisit30Days => 'آخر 30 يومًا';

  @override
  String get patientsListLastVisit90Days => 'آخر 90 يومًا';

  @override
  String get patientsListLastVisitOver90Days => 'أكثر من 90 يومًا';

  @override
  String get patientsListLastVisitNever => 'لم يزر أبدًا';

  @override
  String get patientNameFallback => 'مريض';

  @override
  String get branchNameFallback => 'فرع';

  @override
  String get patientSectionsAriaLabel => 'أقسام المريض';

  @override
  String get addPatientDescription =>
      'Register a new patient at your active branch.';

  @override
  String get duplicatePatientDialogTitle => 'Possible duplicate found';

  @override
  String get duplicatePatientDialogDescription =>
      'A patient with similar details already exists. Review the matches below before creating a new record.';

  @override
  String get duplicatePatientGoBack => 'Go back';

  @override
  String get duplicatePatientRegisterAnyway => 'Register anyway';

  @override
  String get duplicatePatientOpen => 'Open';

  @override
  String get duplicatePatientMatchCountOne =>
      '1 existing patient matches the details you entered.';

  @override
  String duplicatePatientMatchCountMany(int count) {
    return '$count existing patients match the details you entered.';
  }

  @override
  String duplicatePatientDobLabel(String date) {
    return 'DOB $date';
  }

  @override
  String get patientsListFilteredBy => 'Filtered by';

  @override
  String get patientsListClearAll => 'Clear all';

  @override
  String get patientFormSelectBranchBeforeRegister =>
      'Select an active branch before registering a patient.';

  @override
  String get patientFormCouldNotRegister =>
      'Could not register the patient. Try again.';

  @override
  String get patientFormDetailsStillLoading =>
      'Patient details are still loading. Try again.';

  @override
  String get patientFormCouldNotUpdate =>
      'Could not update the patient. Try again.';

  @override
  String patientFormRegisteredAtBranch(String fullName, String branchName) {
    return '$fullName registered at $branchName.';
  }

  @override
  String patientFormPatientUpdated(String fullName) {
    return '$fullName updated.';
  }

  @override
  String get patientFormFullNameRequired => 'Enter the patient\'s full name.';

  @override
  String get patientFormFullNameMinLength =>
      'Full name must be at least 2 characters.';

  @override
  String get patientFormMobileRequired => 'Mobile number is required.';

  @override
  String get patientFormMobileDigitsOnly => 'Only numbers are allowed.';

  @override
  String get patientFormMobileLength => 'Mobile number must be 8 to 15 digits.';

  @override
  String get patientRpcNotFound =>
      'Patient was not found or you do not have access.';

  @override
  String get patientRpcDuplicateWarning =>
      'Similar patients were found. Review the list before continuing.';

  @override
  String get patientRpcStalePatient =>
      'This record was updated elsewhere. Reload and try again.';

  @override
  String get patientRpcPatientArchived =>
      'This patient is archived and is not available.';

  @override
  String get patientRpcForbidden =>
      'You do not have permission to perform this action.';

  @override
  String get patientRpcBranchRequired =>
      'Select an active branch before registering a patient.';

  @override
  String get patientRpcDefaultError =>
      'The clinic service rejected this request.';

  @override
  String get appointmentTypePlanned => 'Planned';

  @override
  String get appointmentTypeUnknown => 'Unknown';

  @override
  String get visitStatusInProgress => 'In progress';

  @override
  String get visitStatusCompleted => 'Completed';

  @override
  String get visitCatalogItemAlreadyAdded => 'Already added';

  @override
  String get encounterPhaseBackground => 'Background';

  @override
  String get encounterPhaseIntake => 'Intake';

  @override
  String get encounterPhaseFindingsDiagnosis => 'Findings & Diagnosis';

  @override
  String get encounterPhaseTreatment => 'Treatment';

  @override
  String get encounterPhaseSummary => 'Summary';

  @override
  String get appointmentStatusScheduled => 'Scheduled';

  @override
  String get appointmentStatusConfirmed => 'Confirmed';

  @override
  String get appointmentStatusCheckedIn => 'Checked in';

  @override
  String get appointmentStatusInProgress => 'In progress';

  @override
  String get appointmentStatusCompleted => 'Completed';

  @override
  String get appointmentStatusCancelled => 'Cancelled';

  @override
  String get appointmentStatusNoShow => 'No-show';

  @override
  String get appointmentStatusUnknown => 'Unknown';

  @override
  String get visitStaleConflictTitle => 'تغيّرت الوثائق في مكان آخر';

  @override
  String get visitStaleConflictDescription =>
      'قام مستخدم آخر بتحديث الملاحظات السريرية لهذه الزيارة. اختر الإصدار الذي تريد الاحتفاظ به قبل الحفظ مرة أخرى.';

  @override
  String get visitStaleConflictKeepMine => 'الاحتفاظ بإصداري';

  @override
  String get visitStaleConflictLoadTheirs => 'تحميل إصدارهم';

  @override
  String get visitStaleConflictServerVersion => 'المحفوظ على الخادم';

  @override
  String get visitStaleConflictYourVersion => 'مسودتك';

  @override
  String get visitStaleConflictSectionEmpty => 'لا يوجد محتوى';

  @override
  String get visitClinicalSectionComplaint => 'الشكوى';

  @override
  String get visitClinicalSectionHistory => 'التاريخ المرضي';

  @override
  String get visitClinicalSectionExamination => 'الفحص';

  @override
  String get visitClinicalSectionDiagnosis => 'التشخيص';

  @override
  String get visitClinicalSectionPlan => 'الخطة';

  @override
  String get visitDocumentationSaveStatusSaving => 'جارٍ الحفظ…';

  @override
  String get visitDocumentationSaveStatusSaved => 'تم الحفظ';

  @override
  String get visitDocumentationSaveStatusStale => 'تعارض';

  @override
  String get visitDocumentationSaveStatusError => 'فشل الحفظ';

  @override
  String get visitDocumentationResolveConflict => 'حل التعارض';

  @override
  String get visitFinalizeFailed =>
      'تعذّر إنهاء الزيارة. يُرجى المحاولة مرة أخرى.';

  @override
  String get visitBillingSubmittedWithoutInvoicePermission =>
      'تم تقديم الزيارة. لم يتم إنشاء فاتورة لأنك لا تملك صلاحية الفوترة.';

  @override
  String get visitBillingRetryInvoice => 'إعادة محاولة الفاتورة';
}
