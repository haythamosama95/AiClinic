import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _EntityCardsCopy {
  const _EntityCardsCopy({
    required this.sectionDescription,
    required this.patientName,
    required this.patientMrn,
    required this.patientPhone,
    required this.tagInsurance,
    required this.tagVip,
    required this.appointmentTime,
    required this.appointmentPatient,
    required this.appointmentDoctor,
    required this.appointmentBranch,
    required this.invoiceNumber,
    required this.invoicePatient,
    required this.invoiceDate,
    required this.serviceName,
    required this.serviceBranchSummary,
  });

  final String sectionDescription;
  final String patientName;
  final String patientMrn;
  final String patientPhone;
  final String tagInsurance;
  final String tagVip;
  final String appointmentTime;
  final String appointmentPatient;
  final String appointmentDoctor;
  final String appointmentBranch;
  final String invoiceNumber;
  final String invoicePatient;
  final String invoiceDate;
  final String serviceName;
  final String serviceBranchSummary;
}

const _copyEn = _EntityCardsCopy(
  sectionDescription: 'Domain-specific card compositions for patients, appointments, invoices, and services.',
  patientName: 'Layla Hassan',
  patientMrn: '10482',
  patientPhone: '+20 100 234 5678',
  tagInsurance: 'Insurance',
  tagVip: 'VIP',
  appointmentTime: '9:30 AM',
  appointmentPatient: 'Omar Farouk',
  appointmentDoctor: 'Dr. Sara Mahmoud',
  appointmentBranch: 'Downtown',
  invoiceNumber: 'INV-2026-0842',
  invoicePatient: 'Nadia El-Sayed',
  invoiceDate: 'Jul 2, 2026',
  serviceName: 'General consultation',
  serviceBranchSummary: 'Available at 3 of 4 branches',
);

const _copyAr = _EntityCardsCopy(
  sectionDescription: 'تكوينات بطاقات خاصة بالمجال للمرضى والمواعيد والفواتير والخدمات.',
  patientName: 'ليلى حسن',
  patientMrn: '10482',
  patientPhone: '+20 100 234 5678',
  tagInsurance: 'تأمين',
  tagVip: 'VIP',
  appointmentTime: '9:30 ص',
  appointmentPatient: 'عمر فاروق',
  appointmentDoctor: 'د. سارة محمود',
  appointmentBranch: 'وسط المدينة',
  invoiceNumber: 'INV-2026-0842',
  invoicePatient: 'نادية السيد',
  invoiceDate: '٢ يوليو ٢٠٢٦',
  serviceName: 'استشارة عامة',
  serviceBranchSummary: 'متاح في ٣ من ٤ فروع',
);

_EntityCardsCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Entity cards showcase (web `EntityCardsShowcase` in `DataDisplayShowcase.tsx`).
class EntityCardsShowcaseSection extends ConsumerWidget {
  const EntityCardsShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'entity-cards',
      title: 'Entity cards',
      description: copy.sectionDescription,
      componentName: 'PatientCard / AppointmentCard / \u2026',
      child: ShowcaseDemoGrid(
        columns: 2,
        children: [
          AppPatientCard(
            name: copy.patientName,
            mrn: copy.patientMrn,
            phone: copy.patientPhone,
            tags: [copy.tagInsurance, copy.tagVip],
          ),
          AppAppointmentCard(
            time: copy.appointmentTime,
            patient: copy.appointmentPatient,
            doctor: copy.appointmentDoctor,
            status: 'confirmed',
            branch: copy.appointmentBranch,
          ),
          AppInvoiceCard(
            number: copy.invoiceNumber,
            patient: copy.invoicePatient,
            amount: 1850,
            status: 'pending',
            date: copy.invoiceDate,
          ),
          AppServiceCard(
            name: copy.serviceName,
            price: 350,
            globalStatus: 'active',
            branchSummary: copy.serviceBranchSummary,
          ),
        ],
      ),
    );
  }
}
