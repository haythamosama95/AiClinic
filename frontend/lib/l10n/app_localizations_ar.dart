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
<<<<<<< HEAD
=======

  @override
  String get breadcrumbCalendar => 'التقويم';

  @override
  String get breadcrumbQueue => 'الطابور';

  @override
  String get breadcrumbInvoices => 'الفواتير';

  @override
  String get breadcrumbVisitDocumentation => 'توثيق الزيارة';

  @override
  String get breadcrumbVisitChronicle => 'سجل الزيارة';

  @override
  String get breadcrumbVisitBilling => 'الفوترة';

  @override
  String get breadcrumbNotFound => 'غير موجود';
>>>>>>> master
}
