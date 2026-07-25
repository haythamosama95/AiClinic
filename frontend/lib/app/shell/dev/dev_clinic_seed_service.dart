import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/data/patient_rpc_failure.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/create_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_branch_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_organization_input.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/setup/domain/repositories/bootstrap_repository.dart';
import 'package:ai_clinic/features/setup/domain/repositories/provisioning_repository.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/billing/data/billing_settings_repository.dart';
import 'package:ai_clinic/features/billing/data/insurance_provider_repository.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/data/payment_repository.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_attachments.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_billing.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_schedule.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_service_catalog.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_spec.dart';
import 'package:ai_clinic/app/shell/dev/dev_egyptian_investigations_asset.dart';
import 'package:ai_clinic/app/shell/dev/dev_egyptian_medications_asset.dart';

typedef DevClinicSeedProgress = void Function(String message);

class _BranchSeedContext {
  const _BranchSeedContext({
    required this.branchId,
    required this.branchCode,
    required this.primaryDoctorId,
    this.secondaryDoctorId,
    required this.patientIds,
  });

  final String branchId;
  final String branchCode;
  final String primaryDoctorId;
  final String? secondaryDoctorId;
  final List<String> patientIds;
}

class _SeededVisit {
  const _SeededVisit({
    required this.visitId,
    required this.branchId,
    required this.branchCode,
    required this.patientIndex,
    required this.seedKey,
    required this.isCompleted,
  });

  final String visitId;
  final String branchId;
  final String branchCode;
  final int patientIndex;
  final int seedKey;
  final bool isCompleted;
}

class _BillingPrerequisites {
  const _BillingPrerequisites({this.insuranceProviderId, this.consultationServiceId});

  final String? insuranceProviderId;
  final String? consultationServiceId;
}

/// Resets the installation and seeds a multi-branch demo clinic (debug builds only).
class DevClinicSeedService {
  DevClinicSeedService({
    required BootstrapRepository bootstrap,
    required BranchRepository branches,
    required ProvisioningRepository provisioning,
    required StaffAdminRepository staffAdmin,
    required PatientRepository patients,
    required AppointmentRepository appointments,
    required VisitRepository visits,
    required ShiftRepository shiftRepository,
    required VisitAttachmentService visitAttachments,
    required InvoiceRepository invoices,
    required PaymentRepository payments,
    required InsuranceProviderRepository insuranceProviders,
    required BillingSettingsRepository billingSettings,
    required ServiceCatalogRepository serviceCatalog,
  }) : _bootstrap = bootstrap,
       _branches = branches,
       _provisioning = provisioning,
       _staffAdmin = staffAdmin,
       _patients = patients,
       _appointments = appointments,
       _visits = visits,
       _shiftRepository = shiftRepository,
       _visitAttachments = visitAttachments,
       _invoices = invoices,
       _payments = payments,
       _insuranceProviders = insuranceProviders,
       _billingSettings = billingSettings,
       _serviceCatalog = serviceCatalog;

  final BootstrapRepository _bootstrap;
  final BranchRepository _branches;
  final ProvisioningRepository _provisioning;
  final StaffAdminRepository _staffAdmin;
  final PatientRepository _patients;
  final AppointmentRepository _appointments;
  final VisitRepository _visits;
  final ShiftRepository _shiftRepository;
  final VisitAttachmentService _visitAttachments;
  final InvoiceRepository _invoices;
  final PaymentRepository _payments;
  final InsuranceProviderRepository _insuranceProviders;
  final BillingSettingsRepository _billingSettings;
  final ServiceCatalogRepository _serviceCatalog;

  Future<void> run({
    required AuthSessionContext auth,
    required Future<void> Function() refreshSession,
    DevClinicSeedProgress? onProgress,
  }) async {
    if (!auth.staffProfile.isBootstrapAdmin) {
      throw StateError('Only the bootstrap administrator can fill dummy clinic data.');
    }

    void report(String message) {
      AppLog.info('dev_clinic_seed.$message');
      onProgress?.call(message);
    }

    report('Wiping all clinic data from the server…');
    await _bootstrap.resetInstallationForDevelopment();
    await refreshSession();

    final doctorIdsByBranch = <String, String>{};
    String? multiBranchDoctorId;

    final firstBranch = DevClinicSeedSpec.branches.first;
    report('Creating organization and first branch…');
    final bootstrapResult = await _bootstrap.finishSetup(
      BootstrapFinishSetupInput(
        organization: const BootstrapOrganizationInput(
          name: DevClinicSeedSpec.organizationName,
          currencyCode: DevClinicSeedSpec.currencyCode,
          timezone: DevClinicSeedSpec.timezone,
        ),
        branch: BootstrapBranchInput(
          organizationId: '',
          name: firstBranch.name,
          code: firstBranch.code,
          address: firstBranch.address,
          phone: firstBranch.phone,
          mapsUrl: firstBranch.mapsUrl,
          workingSchedule: DevClinicSeedSpec.workingScheduleFor(firstBranch.scheduleKind),
        ),
        staffAccounts: [
          for (final staff in firstBranch.branchStaff)
            CreateStaffAccountInput(
              username: staff.username,
              password: DevClinicSeedSpec.defaultStaffPassword,
              fullName: staff.fullName,
              role: _staffRole(staff.role),
              branchIds: const [],
              phone: staff.phone,
            ),
        ],
      ),
    );
    await refreshSession();

    await _seedEgyptianCatalogs(onProgress: report);

    final branchIds = <String>[bootstrapResult.branchId];
    for (var staffIndex = 0; staffIndex < firstBranch.branchStaff.length; staffIndex++) {
      final staff = firstBranch.branchStaff[staffIndex];
      if (staff.role == DevClinicStaffRole.doctor && staffIndex < bootstrapResult.staffMemberIds.length) {
        doctorIdsByBranch[bootstrapResult.branchId] = bootstrapResult.staffMemberIds[staffIndex];
      }
    }

    for (var index = 1; index < DevClinicSeedSpec.branches.length; index++) {
      final spec = DevClinicSeedSpec.branches[index];
      report('Creating branch ${spec.name}…');
      final branchId = await _branches.createBranch(
        CreateBranchInput(
          name: spec.name,
          code: spec.code,
          address: spec.address,
          phone: spec.phone,
          mapsUrl: spec.mapsUrl,
          workingSchedule: DevClinicSeedSpec.workingScheduleFor(spec.scheduleKind),
        ),
      );
      branchIds.add(branchId);
    }

    report('Assigning branches to your account…');
    await _assignBootstrapAdminToBranches(auth.staffProfile.staffMemberId, branchIds);
    await refreshSession();

    for (var branchIndex = 1; branchIndex < DevClinicSeedSpec.branches.length; branchIndex++) {
      final spec = DevClinicSeedSpec.branches[branchIndex];
      final branchId = branchIds[branchIndex];
      for (final staff in spec.branchStaff) {
        report('Creating staff ${staff.fullName}…');
        final created = await _provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: staff.username,
            password: DevClinicSeedSpec.defaultStaffPassword,
            fullName: staff.fullName,
            role: _staffRole(staff.role),
            branchIds: [branchId],
            primaryBranchId: branchId,
            phone: staff.phone,
          ),
        );
        if (staff.role == DevClinicStaffRole.doctor) {
          doctorIdsByBranch[branchId] = created.staffMemberId;
        }
      }
    }

    for (final staff in DevClinicSeedSpec.allBranchStaff) {
      report('Creating staff ${staff.fullName}…');
      final created = await _provisioning.createStaffAccount(
        CreateStaffAccountInput(
          username: staff.username,
          password: DevClinicSeedSpec.defaultStaffPassword,
          fullName: staff.fullName,
          role: _staffRole(staff.role),
          branchIds: List<String>.from(branchIds),
          primaryBranchId: branchIds.first,
          phone: staff.phone,
        ),
      );
      if (staff.role == DevClinicStaffRole.doctor) {
        multiBranchDoctorId = created.staffMemberId;
      }
    }

    await refreshSession();

    final branchContexts = <_BranchSeedContext>[];
    var patientCount = 0;
    final totalPatients = DevClinicSeedSpec.patientsPerBranch * branchIds.length;
    for (var branchIndex = 0; branchIndex < branchIds.length; branchIndex++) {
      final branchId = branchIds[branchIndex];
      final branchCode = DevClinicSeedSpec.branches[branchIndex].code;
      final primaryDoctorId = doctorIdsByBranch[branchId];
      if (primaryDoctorId == null || primaryDoctorId.isEmpty) {
        throw StateError('No doctor was created for branch $branchCode.');
      }

      final patientIds = <String>[];
      for (var patientIndex = 1; patientIndex <= DevClinicSeedSpec.patientsPerBranch; patientIndex++) {
        patientCount++;
        if (patientCount == 1 || patientCount % 10 == 0 || patientCount == totalPatients) {
          report('Creating patients ($patientCount/$totalPatients)…');
        }

        final patientId = await _createPatient(
          branchId: branchId,
          branchIndex: branchIndex + 1,
          branchCode: branchCode,
          patientIndex: patientIndex,
        );
        patientIds.add(patientId);
      }

      branchContexts.add(
        _BranchSeedContext(
          branchId: branchId,
          branchCode: branchCode,
          primaryDoctorId: primaryDoctorId,
          secondaryDoctorId: multiBranchDoctorId,
          patientIds: patientIds,
        ),
      );
    }

    await _seedShifts(branchContexts: branchContexts, onProgress: report);

    final organizationId = bootstrapResult.organizationId;
    if (organizationId.isEmpty) {
      throw StateError('Organization ID missing after bootstrap setup.');
    }

    final seededVisits = await _seedAppointmentsAndVisits(branchContexts: branchContexts, onProgress: report);

    final consultationServiceId = await _seedServiceCatalog(branchIds: branchIds, onProgress: report);
    final billingPrerequisites = await _seedBillingPrerequisites(
      consultationServiceId: consultationServiceId,
      onProgress: report,
    );
    await _seedVisitAttachments(organizationId: organizationId, seededVisits: seededVisits, onProgress: report);
    await _seedVisitBilling(seededVisits: seededVisits, prerequisites: billingPrerequisites, onProgress: report);

    report('Refreshing session…');
    await refreshSession();
    report('Done');
  }

  Future<void> _seedEgyptianCatalogs({required DevClinicSeedProgress onProgress}) async {
    await _seedEgyptianMedications(onProgress: onProgress);
    await _seedEgyptianInvestigations(onProgress: onProgress);
  }

  Future<void> _seedEgyptianMedications({required DevClinicSeedProgress onProgress}) async {
    onProgress('Loading Egyptian medication catalog…');
    final names = await DevEgyptianMedicationsAsset.loadNames();
    final batches = DevEgyptianMedicationsAsset.batchesFor(names);
    if (batches.isEmpty) {
      return;
    }

    var totalInserted = 0;
    for (var batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      onProgress('Importing medications (${batchIndex + 1}/${batches.length})…');
      final result = await _visits.devSeedMedicationsCatalog(names: batches[batchIndex]);
      totalInserted += result.inserted;
    }

    onProgress('Imported $totalInserted Egyptian medications.');
  }

  Future<void> _seedEgyptianInvestigations({required DevClinicSeedProgress onProgress}) async {
    onProgress('Loading Egyptian investigation catalog…');
    final names = await DevEgyptianInvestigationsAsset.loadNames();
    final batches = DevEgyptianInvestigationsAsset.batchesFor(names);
    if (batches.isEmpty) {
      return;
    }

    var totalInserted = 0;
    for (var batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      onProgress('Importing investigations (${batchIndex + 1}/${batches.length})…');
      final result = await _visits.devSeedInvestigationsCatalog(names: batches[batchIndex]);
      totalInserted += result.inserted;
    }

    onProgress('Imported $totalInserted Egyptian investigations.');
  }

  Future<void> _seedShifts({
    required List<_BranchSeedContext> branchContexts,
    required DevClinicSeedProgress onProgress,
  }) async {
    final referenceUtc = DateTime.now().toUtc();
    final dayOffsets = DevClinicSeedSchedule.shiftDayOffsets;
    final totalShifts = branchContexts.length * dayOffsets.length;
    var shiftCount = 0;

    for (final branch in branchContexts) {
      final doctorIds = DevClinicSeedSchedule.shiftDoctorIdsForBranch(
        primaryDoctorId: branch.primaryDoctorId,
        secondaryDoctorId: branch.secondaryDoctorId,
      );

      for (final dayOffset in dayOffsets) {
        shiftCount++;
        if (shiftCount == 1 || shiftCount % 5 == 0 || shiftCount == totalShifts) {
          onProgress('Creating shifts ($shiftCount/$totalShifts)…');
        }

        await _shiftRepository.createShift(
          branchId: branch.branchId,
          shiftDate: DevClinicSeedSchedule.shiftDateLocal(
            timezone: DevClinicSeedSpec.timezone,
            dayOffset: dayOffset,
            referenceUtc: referenceUtc,
          ),
          startTime: DevClinicSeedSpec.branchOpenTime,
          endTime: DevClinicSeedSpec.branchCloseTime,
          notes: DevClinicSeedSchedule.shiftNotes(branchCode: branch.branchCode, dayOffset: dayOffset),
          staffIds: doctorIds,
        );
      }
    }
  }

  Future<List<_SeededVisit>> _seedAppointmentsAndVisits({
    required List<_BranchSeedContext> branchContexts,
    required DevClinicSeedProgress onProgress,
  }) async {
    final seededVisits = <_SeededVisit>[];
    final referenceUtc = DateTime.now().toUtc();
    var appointmentCount = 0;
    final totalAppointments =
        branchContexts.length *
        DevClinicSeedSpec.patientsPerBranch *
        DevClinicSeedSchedule.appointmentDayOffsets.length;

    for (final branch in branchContexts) {
      for (var patientIndex = 1; patientIndex <= branch.patientIds.length; patientIndex++) {
        final patientId = branch.patientIds[patientIndex - 1];

        for (final dayOffset in DevClinicSeedSchedule.appointmentDayOffsets) {
          appointmentCount++;
          if (appointmentCount == 1 || appointmentCount % 25 == 0 || appointmentCount == totalAppointments) {
            onProgress('Creating appointments ($appointmentCount/$totalAppointments)…');
          }

          final seedKey = patientIndex + dayOffset;
          final doctorId = DevClinicSeedSchedule.doctorIdForAppointment(
            primaryDoctorId: branch.primaryDoctorId,
            secondaryDoctorId: branch.secondaryDoctorId,
            patientIndex: patientIndex,
          );
          final startTime = DevClinicSeedSchedule.appointmentStartUtc(
            timezone: DevClinicSeedSpec.timezone,
            dayOffset: dayOffset,
            patientIndex: patientIndex,
            referenceUtc: referenceUtc,
          );
          final dayRelation = DevClinicSeedSchedule.calendarDayRelationFor(
            startTimeUtc: startTime,
            timezone: DevClinicSeedSpec.timezone,
            referenceUtc: referenceUtc,
          );
          final targetStatus = DevClinicSeedSchedule.appointmentStatusFor(
            startTimeUtc: startTime,
            timezone: DevClinicSeedSpec.timezone,
            seedKey: seedKey,
            referenceUtc: referenceUtc,
          );
          final doctorLabel = DevClinicSeedSchedule.doctorAssignmentLabel(
            primaryDoctorId: branch.primaryDoctorId,
            secondaryDoctorId: branch.secondaryDoctorId,
            patientIndex: patientIndex,
          );

          final created = await _appointments.createAppointment(
            branchId: branch.branchId,
            patientId: patientId,
            doctorId: doctorId,
            type: AppointmentType.planned,
            startTime: startTime,
            durationMinutes: DevClinicSeedSchedule.appointmentDurationMinutesFor(seedKey),
            notes: DevClinicSeedSchedule.appointmentNotes(
              branchCode: branch.branchCode,
              patientIndex: patientIndex,
              dayOffset: dayOffset,
              status: targetStatus,
              doctorAssignmentLabel: doctorLabel,
            ),
          );

          await _finalizeSeededAppointment(
            appointmentId: created.appointmentId,
            branchId: branch.branchId,
            branchCode: branch.branchCode,
            patientIndex: patientIndex,
            dayOffset: dayOffset,
            seedKey: seedKey,
            targetStatus: targetStatus,
            dayRelation: dayRelation,
            seededVisits: seededVisits,
          );
        }
      }
    }

    return seededVisits;
  }

  /// Sets the terminal appointment status and optionally creates visit + invoice data.
  Future<void> _finalizeSeededAppointment({
    required String appointmentId,
    required String branchId,
    required String branchCode,
    required int patientIndex,
    required int dayOffset,
    required int seedKey,
    required AppointmentStatus targetStatus,
    required DevClinicSeedCalendarDayRelation dayRelation,
    required List<_SeededVisit> seededVisits,
  }) async {
    if (DevClinicSeedSchedule.requiresVisitAndInvoice(status: targetStatus, relation: dayRelation)) {
      await _seedCompletedPastAppointment(
        appointmentId: appointmentId,
        branchId: branchId,
        branchCode: branchCode,
        patientIndex: patientIndex,
        dayOffset: dayOffset,
        seedKey: seedKey,
        seededVisits: seededVisits,
      );
      return;
    }

    switch (targetStatus) {
      case AppointmentStatus.scheduled:
        return;
      case AppointmentStatus.confirmed:
        await _appointments.updateAppointmentStatus(
          appointmentId: appointmentId,
          newStatus: AppointmentStatus.confirmed,
        );
        return;
      case AppointmentStatus.cancelled:
        await _appointments.cancelAppointment(
          appointmentId: appointmentId,
          reason: 'Dev seed cancellation for $branchCode patient #$patientIndex.',
        );
        return;
      case AppointmentStatus.noShow:
        await _appointments.markAppointmentNoShow(appointmentId: appointmentId);
        return;
      case AppointmentStatus.checkedIn:
      case AppointmentStatus.inProgress:
      case AppointmentStatus.completed:
      case AppointmentStatus.unknown:
        throw StateError(
          'Dev seed target status ${targetStatus.label} is not allowed for $dayRelation '
          '(patient #$patientIndex day $dayOffset).',
        );
    }
  }

  /// Past completed only: advance to in_progress, document visit, complete → completed.
  Future<void> _seedCompletedPastAppointment({
    required String appointmentId,
    required String branchId,
    required String branchCode,
    required int patientIndex,
    required int dayOffset,
    required int seedKey,
    required List<_SeededVisit> seededVisits,
  }) async {
    for (final status in DevClinicSeedSchedule.completedVisitAppointmentTransitions) {
      await _appointments.updateAppointmentStatus(appointmentId: appointmentId, newStatus: status);
    }

    final documentation = DevClinicSeedSchedule.visitDocumentationFor(seedKey: seedKey);
    final visit = await _visits.createVisit(appointmentId: appointmentId);

    if (DevClinicSeedSchedule.shouldIncludeTreatmentPlan(documentation)) {
      final treatment = DevClinicSeedSchedule.treatmentPlanFor(branchCode: branchCode, patientIndex: patientIndex);
      await _visits.createTreatmentPlan(
        visitId: visit.visitId,
        medicationName: treatment.medicationName,
        dosage: treatment.dosage,
        frequency: treatment.frequency,
        duration: treatment.duration,
        notes: treatment.notes,
      );
    }

    final note = DevClinicSeedSchedule.clinicalNoteContentFor(
      kind: documentation,
      branchCode: branchCode,
      patientIndex: patientIndex,
      dayOffset: dayOffset,
    );

    final detail = await _visits.getVisit(visitId: visit.visitId);
    final docUpdatedAt = detail.documentation?.updatedAt;
    if (docUpdatedAt == null) {
      throw StateError('Visit documentation timestamp missing after create for dev seed.');
    }

    final saved = await _visits.saveVisitDocumentation(
      visitId: visit.visitId,
      expectedUpdatedAt: docUpdatedAt,
      complaint: note.complaint.isEmpty ? null : note.complaint,
      history: note.history.isEmpty ? null : note.history,
      examination: note.examination.isEmpty ? null : note.examination,
      diagnosis: note.diagnosis.isEmpty ? null : note.diagnosis,
      plan: note.plan.isEmpty ? null : note.plan,
    );

    await _visits.completeVisit(visitId: visit.visitId, expectedUpdatedAt: saved.updatedAt);

    seededVisits.add(
      _SeededVisit(
        visitId: visit.visitId,
        branchId: branchId,
        branchCode: branchCode,
        patientIndex: patientIndex,
        seedKey: seedKey,
        isCompleted: true,
      ),
    );
  }

  Future<String> _seedServiceCatalog({
    required List<String> branchIds,
    required DevClinicSeedProgress onProgress,
  }) async {
    final services = DevClinicSeedServiceCatalog.services;
    onProgress('Creating service catalog (${services.length} services)…');

    String? consultationServiceId;
    for (var index = 0; index < services.length; index++) {
      final spec = services[index];
      if (index == 0 || (index + 1) % 4 == 0 || index == services.length - 1) {
        onProgress('Creating services (${index + 1}/${services.length})…');
      }

      final created = await _serviceCatalog.createService(
        name: spec.name,
        defaultPrice: spec.defaultPrice,
        globalStatus: spec.globalStatus,
        assignAllBranches: spec.assignAllBranches,
      );

      if (spec.name == DevClinicSeedServiceCatalog.consultationServiceName) {
        consultationServiceId = created.serviceId;
      }

      if (spec.branchConfigs.isEmpty) {
        continue;
      }

      final detail = await _serviceCatalog.getService(serviceId: created.serviceId);
      for (final branchConfig in spec.branchConfigs) {
        if (branchConfig.branchIndex < 0 || branchConfig.branchIndex >= branchIds.length) {
          continue;
        }

        final branchId = branchIds[branchConfig.branchIndex];
        final branchRow = detail.branches.firstWhere(
          (row) => row.branchId == branchId,
          orElse: () => throw StateError('Branch row missing for seeded service ${spec.name}.'),
        );
        final updatedAt = branchRow.updatedAt;
        if (updatedAt == null) {
          throw StateError('Branch row timestamp missing for seeded service ${spec.name}.');
        }

        final configured = await _serviceCatalog.configureServiceBranch(
          serviceId: created.serviceId,
          branchId: branchId,
          expectedUpdatedAt: updatedAt,
          status: branchConfig.status,
          priceOverride: branchConfig.priceOverride,
        );

        final promotion = branchConfig.promotion;
        if (promotion == null) {
          continue;
        }

        final referenceDate = DateTime.now().toLocal();
        await _serviceCatalog.setServicePromotion(
          serviceId: created.serviceId,
          branchId: branchId,
          expectedUpdatedAt: configured.updatedAt,
          promotionPrice: promotion.price,
          startDate: referenceDate.add(Duration(days: promotion.startOffsetDays)),
          endDate: referenceDate.add(Duration(days: promotion.endOffsetDays)),
        );
      }
    }

    if (consultationServiceId == null || consultationServiceId.isEmpty) {
      throw StateError('Consultation service was not created for dev service catalog seed.');
    }

    return consultationServiceId;
  }

  Future<_BillingPrerequisites> _seedBillingPrerequisites({
    required String consultationServiceId,
    required DevClinicSeedProgress onProgress,
  }) async {
    onProgress('Preparing billing catalog…');

    await _billingSettings.update(allowPartialPayments: true);

    final insuranceProviderId = await _insuranceProviders.upsertProvider(
      name: 'Dev Seed Insurance Co.',
      contactInfo: 'claims@dev-seed.example.com',
    );

    return _BillingPrerequisites(
      insuranceProviderId: insuranceProviderId,
      consultationServiceId: consultationServiceId,
    );
  }

  Future<void> _seedVisitAttachments({
    required String organizationId,
    required List<_SeededVisit> seededVisits,
    required DevClinicSeedProgress onProgress,
  }) async {
    if (seededVisits.isEmpty) {
      return;
    }

    var attachmentCount = 0;
    final totalAttachments = seededVisits.fold<int>(0, (total, visit) {
      return total +
          DevClinicSeedAttachments.attachmentsFor(
            seedKey: visit.seedKey,
            branchCode: visit.branchCode,
            patientIndex: visit.patientIndex,
          ).length;
    });

    for (final visit in seededVisits) {
      final specs = DevClinicSeedAttachments.attachmentsFor(
        seedKey: visit.seedKey,
        branchCode: visit.branchCode,
        patientIndex: visit.patientIndex,
      );

      for (final spec in specs) {
        attachmentCount++;
        if (attachmentCount == 1 || attachmentCount % 10 == 0 || attachmentCount == totalAttachments) {
          onProgress('Uploading visit documents ($attachmentCount/$totalAttachments)…');
        }

        await _visitAttachments.uploadAndRegister(
          organizationId: organizationId,
          branchId: visit.branchId,
          visitId: visit.visitId,
          pick: VisitAttachmentPickInput(
            filename: spec.filename,
            bytes: DevClinicSeedAttachments.dummyBytesFor(spec.fileType),
          ),
          label: spec.label,
        );
      }
    }
  }

  Future<void> _seedVisitBilling({
    required List<_SeededVisit> seededVisits,
    required _BillingPrerequisites prerequisites,
    required DevClinicSeedProgress onProgress,
  }) async {
    final completedVisits = seededVisits.where((visit) => visit.isCompleted).toList(growable: false);
    if (completedVisits.isEmpty) {
      return;
    }

    var invoiceCount = 0;
    final totalInvoices = completedVisits.length;

    for (final visit in completedVisits) {
      final scenario = DevClinicSeedBilling.scenarioFor(visit.seedKey);
      invoiceCount++;
      if (invoiceCount == 1 || invoiceCount % 5 == 0 || invoiceCount == totalInvoices) {
        onProgress('Creating visit invoices ($invoiceCount/$totalInvoices)…');
      }

      await _applyBillingScenario(visit: visit, scenario: scenario, prerequisites: prerequisites);
    }
  }

  Future<void> _applyBillingScenario({
    required _SeededVisit visit,
    required DevClinicBillingScenario scenario,
    required _BillingPrerequisites prerequisites,
  }) async {
    final invoiceId = await _invoices.createFromVisit(visitId: visit.visitId);
    var detail = await _invoices.getDetail(invoiceId: invoiceId);

    if (DevClinicSeedBilling.shouldUseServiceCatalog(scenario)) {
      final serviceId = prerequisites.consultationServiceId;
      if (serviceId == null || serviceId.isEmpty) {
        throw StateError('Consultation service was not created for dev billing seed.');
      }

      await _serviceCatalog.addInvoiceItemFromService(
        invoiceId: invoiceId,
        expectedUpdatedAt: detail.updatedAt,
        serviceId: serviceId,
      );
      detail = await _invoices.getDetail(invoiceId: invoiceId);
    } else if (DevClinicSeedBilling.shouldAddManualItems(scenario)) {
      final itemId = await _invoices.addItem(
        invoiceId: invoiceId,
        expectedUpdatedAt: detail.updatedAt,
        description: DevClinicSeedBilling.primaryItemDescription(
          branchCode: visit.branchCode,
          patientIndex: visit.patientIndex,
        ),
        quantity: '1',
        unitPrice: DevClinicSeedBilling.primaryItemUnitPrice(),
      );
      detail = await _invoices.getDetail(invoiceId: invoiceId);

      if (DevClinicSeedBilling.shouldApplyLineDiscount(scenario)) {
        await _invoices.applyLineDiscount(
          itemId: itemId,
          expectedUpdatedAt: detail.updatedAt,
          kind: DevClinicSeedBilling.lineDiscountKind(scenario),
          value: DevClinicSeedBilling.lineDiscountValue(scenario),
        );
        detail = await _invoices.getDetail(invoiceId: invoiceId);
      }

      if (scenario != DevClinicBillingScenario.withLineDiscount) {
        await _invoices.addItem(
          invoiceId: invoiceId,
          expectedUpdatedAt: detail.updatedAt,
          description: DevClinicSeedBilling.secondaryItemDescription(),
          quantity: DevClinicSeedBilling.secondaryItemQuantity(),
          unitPrice: DevClinicSeedBilling.secondaryItemUnitPrice(),
        );
        detail = await _invoices.getDetail(invoiceId: invoiceId);
      }
    }

    if (DevClinicSeedBilling.shouldApplyInvoiceDiscount(scenario)) {
      await _invoices.applyInvoiceDiscount(
        invoiceId: invoiceId,
        expectedUpdatedAt: detail.updatedAt,
        kind: DevClinicSeedBilling.invoiceDiscountKind(scenario),
        value: DevClinicSeedBilling.invoiceDiscountValue(scenario),
      );
      detail = await _invoices.getDetail(invoiceId: invoiceId);
    }

    if (DevClinicSeedBilling.shouldApplyInsurance(scenario)) {
      final providerId = prerequisites.insuranceProviderId;
      if (providerId == null || providerId.isEmpty) {
        throw StateError('Insurance provider was not created for dev billing seed.');
      }

      await _invoices.setInsuranceCoverage(
        invoiceId: invoiceId,
        expectedUpdatedAt: detail.updatedAt,
        providerId: providerId,
        coveredAmount: DevClinicSeedBilling.insuranceCoveredAmount(scenario),
      );
      detail = await _invoices.getDetail(invoiceId: invoiceId);
    }

    if (DevClinicSeedBilling.shouldIssue(scenario)) {
      await _invoices.issue(invoiceId: invoiceId, expectedUpdatedAt: detail.updatedAt);
      detail = await _invoices.getDetail(invoiceId: invoiceId);
    }

    for (final payment in DevClinicSeedBilling.paymentsFor(scenario)) {
      if (payment.isRefund) {
        await _payments.recordRefund(
          invoiceId: invoiceId,
          method: payment.method,
          amount: payment.amount,
          note: payment.note ?? 'Dev seed refund',
        );
      } else {
        await _payments.recordPayment(
          invoiceId: invoiceId,
          method: payment.method,
          amount: payment.amount,
          reference: payment.reference,
          note: payment.note,
        );
      }
      detail = await _invoices.getDetail(invoiceId: invoiceId);
    }

    if (DevClinicSeedBilling.shouldVoid(scenario)) {
      await _invoices.voidInvoice(
        invoiceId: invoiceId,
        expectedUpdatedAt: detail.updatedAt,
        reason: DevClinicSeedBilling.voidReason(branchCode: visit.branchCode, patientIndex: visit.patientIndex),
      );
    }
  }

  Future<void> _assignBootstrapAdminToBranches(String staffMemberId, List<String> branchIds) async {
    final detail = await _staffAdmin.fetchStaffMember(staffMemberId);
    if (detail == null) {
      throw StateError('Could not load the bootstrap administrator profile.');
    }

    await _staffAdmin.updateStaffMember(
      UpdateStaffMemberInput(
        staffMemberId: staffMemberId,
        fullName: detail.fullName,
        role: detail.role,
        branchIds: branchIds,
        phone: detail.phone,
        primaryBranchId: branchIds.first,
      ),
    );
  }

  Future<String> _createPatient({
    required String branchId,
    required int branchIndex,
    required String branchCode,
    required int patientIndex,
  }) async {
    final seedKey = branchIndex * 1000 + patientIndex;
    final globalIndex = DevClinicSeedSpec.patientGlobalIndex(branchIndex: branchIndex, patientIndex: patientIndex);
    final input = CreatePatientInput(
      activeBranchId: branchId,
      fullName: DevClinicSeedSpec.patientFullName(branchCode: branchCode, index: patientIndex),
      phone: DevClinicSeedSpec.patientPhone(branchIndex: branchIndex, patientIndex: patientIndex),
      dateOfBirth: DevClinicSeedSchedule.patientDateOfBirth(seedKey),
      gender: DevClinicSeedSchedule.patientGender(seedKey),
      maritalStatus: DevClinicSeedSchedule.patientMaritalStatus(seedKey),
      notes: DevClinicSeedSchedule.patientNotes(branchCode: branchCode, patientIndex: patientIndex),
      mrn: DevClinicSeedSpec.patientMrn(globalIndex),
    );

    try {
      final result = await _patients.createPatient(input);
      return result.patientId;
    } on RpcFailure catch (error) {
      if (!error.isDuplicateWarning) {
        rethrow;
      }
      final result = await _patients.createPatient(input.copyWith(acknowledgeDuplicate: true));
      return result.patientId;
    }
  }

  static StaffRole _staffRole(DevClinicStaffRole role) {
    return switch (role) {
      DevClinicStaffRole.doctor => StaffRole.doctor,
      DevClinicStaffRole.receptionist => StaffRole.receptionist,
    };
  }
}
