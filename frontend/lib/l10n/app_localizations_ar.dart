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

  @override
  String get aiBillingOffersTitle => 'تغطية الذكاء الاصطناعي';

  @override
  String get aiBillingOffersDescription =>
      'إدارة خطة العيادة والمدفوعات وبيانات التواصل مع الدعم.';

  @override
  String get aiBillingOffersEmpty =>
      'لا توجد خطط متاحة للشراء حاليًا. تواصل مع الدعم وأرسل مرجع العيادة إذا احتجت إلى المساعدة.';

  @override
  String get aiBillingOffersEmptyTitle => 'لا توجد خطط متاحة';

  @override
  String get aiBillingOffersUnavailable => 'تعذّر تحميل الخطط';

  @override
  String get aiBillingOffersUnavailableDescription =>
      'تحقق من اتصالك بالإنترنت ثم حاول مرة أخرى.';

  @override
  String get aiBillingRefreshPlans => 'تحديث الخطط';

  @override
  String get aiBillingCurrentCoverage => 'التغطية الحالية';

  @override
  String get aiBillingAvailablePlans => 'الخطط المتاحة';

  @override
  String get aiBillingNoActivePlan => 'لا توجد خطة نشطة';

  @override
  String get aiBillingNoActivePlanDescription =>
      'تغطية الذكاء الاصطناعي غير نشطة لهذه العيادة. اختر خطة متاحة أدناه للبدء.';

  @override
  String get aiBillingPlanActiveDescription => 'هذه الخطة نشطة لعيادتك.';

  @override
  String get aiBillingRenewsOrEnds => 'تنتهي في';

  @override
  String get aiBillingStarted => 'بدأت في';

  @override
  String get aiBillingGraceEnds => 'تنتهي فترة السماح في';

  @override
  String get aiBillingCreditsIncluded => 'الرصيد المتضمن';

  @override
  String get aiBillingCreditsUsed => 'الرصيد المستخدم';

  @override
  String get aiBillingSupportReference => 'مرجع العيادة للدعم';

  @override
  String get aiBillingSupportReferenceDescription =>
      'أرسل هذا المرجع إلى الدعم عند الاستفسار عن الفوترة.';

  @override
  String get aiBillingStatusUnavailable =>
      'تعذّر تحميل تفاصيل التغطية. تحقق من اتصالك وحاول مرة أخرى.';

  @override
  String get aiBillingEndedReversed =>
      'تم التراجع عن إنهاء الخطة مؤخرًا. تواصل مع الدعم إذا بدت التغطية غير صحيحة.';

  @override
  String get aiBillingPaymentHistory => 'سجل المدفوعات';

  @override
  String get aiBillingNoPayments => 'لا توجد مدفوعات بعد';

  @override
  String get aiBillingNoPaymentsDescription =>
      'ستظهر هنا المدفوعات المكتملة لهذه العيادة.';

  @override
  String get aiBillingPaymentHistoryUnavailable =>
      'تعذّر تحميل سجل المدفوعات. تحقق من اتصالك وحاول مرة أخرى.';

  @override
  String get aiBillingPaymentsLoadMore => 'تحميل المزيد من المدفوعات';

  @override
  String get aiBillingBrowsePlans => 'استعراض الخطط';

  @override
  String get aiBillingTermsTitle => 'شروط الخدمة';

  @override
  String get aiBillingAcceptTerms => 'أوافق على الشروط الحالية';

  @override
  String get aiBillingContinue => 'متابعة';

  @override
  String get aiBillingContactTitle => 'جهة اتصال الفوترة';

  @override
  String get aiBillingContactName => 'الاسم';

  @override
  String get aiBillingContactEmail => 'البريد الإلكتروني';

  @override
  String get aiBillingContactPhone => 'الهاتف';

  @override
  String get aiBillingContactSave => 'حفظ جهة الاتصال';

  @override
  String get aiBillingCheckoutTitle => 'الدفع';

  @override
  String get aiBillingCheckoutSubmit => 'ادفع الآن';

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
      'هذا العرض لم يعد متاحًا. راجع السعر المحدّث قبل الدفع.';

  @override
  String get aiBillingErrorBillingContactRequired =>
      'أضف جهة اتصال للفوترة قبل الدفع.';

  @override
  String get aiBillingErrorTermsNotAccepted => 'اقبل الشروط الحالية قبل الدفع.';

  @override
  String get aiBillingErrorProviderUnavailable =>
      'مزوّد الدفع غير متاح. حاول مرة أخرى لاحقًا.';

  @override
  String get aiBillingErrorRateLimited =>
      'طلبات الفوترة كثيرة جدًا. حاول مرة أخرى لاحقًا.';

  @override
  String get aiBillingRefresh => 'تحديث الفوترة';

  @override
  String get aiBillingProjectionPending =>
      'تم طلب تحديث التغطية. قد يستغرق ظهور الخطة والأرصدة بضع دقائق. حدّث الصفحة للتحقق مرة أخرى.';

  @override
  String get aiBillingProjectionPullFailed =>
      'تعذّر طلب تحديث التغطية. حدّث الصفحة للمحاولة مرة أخرى.';

  @override
  String get aiBillingNoticeDuplicatePayment =>
      'يبدو أن دفعة لهذه العيادة مكررة وهي قيد المراجعة. تواصل مع الدعم إذا تم خصم المبلغ مرتين.';

  @override
  String get aiBillingNoticeLatePaymentHonoured =>
      'وصلت دفعة بعد نافذة الدفع الخاصة بها وتم اعتمادها.';

  @override
  String get aiBillingNoticePaymentWithheld =>
      'تم حجز دفعة لأن تفاصيلها لم تتطابق. تواصل مع الدعم لحلها.';

  @override
  String get aiBillingNoticeReversalRecorded =>
      'تم تسجيل عكس دفعة لهذه العيادة. راجع التغطية وتواصل مع الدعم إذا بدت غير صحيحة.';

  @override
  String get aiBillingNoticeTermsHeld =>
      'بعض شروط الاشتراك معلّقة ولن تسري حتى يتم الإفراج عنها.';

  @override
  String get aiNoticeUnavailable => 'معلومات الحالة غير متاحة حاليًا.';

  @override
  String get aiNoticeAskAdministrator => 'راجع مسؤول العيادة';

  @override
  String get aiNoticeEndsSoonAdmin =>
      'ستنتهي تغطية الذكاء الاصطناعي قريبًا. جدّد الاشتراك لتجنب انقطاع الخدمة.';

  @override
  String get aiNoticeEndsSoonStaff => 'ستنتهي تغطية الذكاء الاصطناعي قريبًا.';

  @override
  String aiNoticeInGraceAdmin(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days يوم متبقٍ',
      many: '$days يومًا متبقيًا',
      few: '$days أيام متبقية',
      two: 'يومان متبقيان',
      one: 'يوم واحد متبقٍ',
      zero: 'أقل من يوم واحد متبقٍ',
    );
    return 'تغطية الذكاء الاصطناعي في فترة السماح: $_temp0. جدّد للحفاظ على إمكانية استخدام الذكاء الاصطناعي.';
  }

  @override
  String aiNoticeInGraceStaff(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days يوم متبقٍ',
      many: '$days يومًا متبقيًا',
      few: '$days أيام متبقية',
      two: 'يومان متبقيان',
      one: 'يوم واحد متبقٍ',
      zero: 'أقل من يوم واحد متبقٍ',
    );
    return 'تغطية الذكاء الاصطناعي في فترة السماح: $_temp0.';
  }

  @override
  String get aiNoticeAllowanceLowAdmin =>
      'استُخدم معظم أرصدة الذكاء الاصطناعي لهذه العيادة. جدّد أو أضف رصيدًا قبل نفاده.';

  @override
  String get aiNoticeAllowanceLowStaff =>
      'أرصدة الذكاء الاصطناعي على وشك النفاد.';

  @override
  String get aiNoticeAllowanceExhaustedAdmin =>
      'نفدت أرصدة الذكاء الاصطناعي لهذه العيادة. جدّد لمتابعة الاستخدام.';

  @override
  String get aiNoticeAllowanceExhaustedStaff =>
      'نفدت أرصدة الذكاء الاصطناعي لهذه العيادة.';

  @override
  String get aiNoticeLapsedAdmin =>
      'انتهت تغطية الذكاء الاصطناعي. جدّد لاستخدامه مرة أخرى.';

  @override
  String get aiNoticeLapsedStaff => 'انتهت تغطية الذكاء الاصطناعي.';

  @override
  String get aiNoticeEndedReversedAdmin =>
      'انتهت تغطية الذكاء الاصطناعي بعد عكس إنهاء خطة. تواصل مع الدعم إذا بدا ذلك غير صحيح.';

  @override
  String get aiNoticeEndedReversedStaff =>
      'تغيّرت تغطية الذكاء الاصطناعي بعد عكس إنهاء خطة.';

  @override
  String get aiNoticeSuspendedAdmin =>
      'الوصول إلى الذكاء الاصطناعي موقوف لهذه العيادة. تواصل مع الدعم لاستعادته.';

  @override
  String get aiNoticeSuspendedStaff =>
      'الوصول إلى الذكاء الاصطناعي موقوف لهذه العيادة.';

  @override
  String get aiNoticeStatusStaleAdmin =>
      'لم يتم تأكيد حالة الذكاء الاصطناعي مؤخرًا، لذا قد تكون التغطية المعروضة غير محدّثة.';

  @override
  String get aiNoticeStatusStaleStaff =>
      'قد تكون حالة الذكاء الاصطناعي غير محدّثة.';
}
