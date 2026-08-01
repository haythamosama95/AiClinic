import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_resolver.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';

/// Whether the signed-in user can open a visit from patient history.
bool canOpenVisitFromPatientHistory(WidgetRef ref, VisitListItem visit) {
  final auth = ref.read(authSessionProvider);
  return switch (visit.status) {
    VisitStatus.inProgress => AuthRouteGuard.canAccessVisitDocumentation(auth),
    VisitStatus.completed =>
      AuthRouteGuard.canAccessVisitDetail(auth) || AuthRouteGuard.canAccessVisitDocumentation(auth),
  };
}

/// Opens the appropriate visit route for a patient history card.
void openVisitFromPatientHistory(BuildContext context, WidgetRef ref, VisitListItem visit) {
  final auth = ref.read(authSessionProvider);
  final parentTrail = BreadcrumbTrailResolver.inheritFrom(context);

  switch (visit.status) {
    case VisitStatus.inProgress:
      if (AuthRouteGuard.canAccessVisitDocumentation(auth)) {
        context.nav.goVisitDocument(visit.id, trail: parentTrail.append(BreadcrumbEntries.visitDocument(visit.id)));
      }
    case VisitStatus.completed:
      if (AuthRouteGuard.canAccessVisitDetail(auth)) {
        context.nav.goVisitDetail(visit.id, trail: parentTrail.append(BreadcrumbEntries.visitDetail(visit.id)));
      } else if (AuthRouteGuard.canAccessVisitDocumentation(auth)) {
        context.nav.goVisitDocument(visit.id, trail: parentTrail.append(BreadcrumbEntries.visitDocument(visit.id)));
      }
  }
}

/// Whether an appointment can surface an "Open visit" action.
bool appointmentSupportsOpenVisit(AppointmentDetail detail) {
  return detail.status == AppointmentStatus.inProgress || detail.status == AppointmentStatus.completed;
}

/// Whether the signed-in user can open (or start) a visit for [detail].
bool canOpenVisitForAppointment(WidgetRef ref, AppointmentDetail detail) {
  if (!appointmentSupportsOpenVisit(detail)) {
    return false;
  }
  final auth = ref.read(authSessionProvider);
  if (detail.status == AppointmentStatus.inProgress) {
    return AuthRouteGuard.canAccessVisitDocumentation(auth);
  }
  return AuthRouteGuard.canAccessVisitDetail(auth) || AuthRouteGuard.canAccessVisitDocumentation(auth);
}

/// Resolves (or creates) the visit for [detail] and navigates to document or chronicle.
Future<void> openVisitForAppointment({
  required BuildContext context,
  required WidgetRef ref,
  required AppointmentDetail detail,
}) async {
  if (!canOpenVisitForAppointment(ref, detail)) {
    return;
  }

  final repo = ref.read(visitRepositoryProvider);

  try {
    var lookup = await repo.getVisitByAppointment(appointmentId: detail.id);
    var visitId = lookup.visitId?.trim();

    if ((visitId == null || visitId.isEmpty) && detail.status == AppointmentStatus.inProgress) {
      final created = await repo.createVisit(appointmentId: detail.id, doctorId: detail.doctorId);
      visitId = created.visitId;
      lookup = VisitByAppointmentResult(visitId: visitId, status: created.status);
    }

    if (visitId == null || visitId.isEmpty) {
      if (context.mounted) {
        appToast(
          context,
          AppToastInput(message: 'No visit record exists for this appointment yet.', variant: AppToastVariant.info),
        );
      }
      return;
    }

    if (!context.mounted) {
      return;
    }

    final visitStatus = VisitStatus.tryParse(lookup.status);
    final openChronicle = detail.status == AppointmentStatus.completed || visitStatus == VisitStatus.completed;
    final parentTrail = BreadcrumbTrailResolver.inheritFrom(context);

    if (openChronicle && AuthRouteGuard.canAccessVisitDetail(ref.read(authSessionProvider))) {
      context.nav.goVisitDetail(visitId, trail: parentTrail.append(BreadcrumbEntries.visitDetail(visitId)));
      return;
    }

    if (AuthRouteGuard.canAccessVisitDocumentation(ref.read(authSessionProvider))) {
      context.nav.goVisitDocument(visitId, trail: parentTrail.append(BreadcrumbEntries.visitDocument(visitId)));
    }
  } on RpcFailure catch (error) {
    if (context.mounted) {
      appToast(context, AppToastInput(message: visitMessageForRpc(error), variant: AppToastVariant.danger));
    }
  } catch (_) {
    if (context.mounted) {
      appToast(
        context,
        const AppToastInput(message: 'Could not open the visit. Please try again.', variant: AppToastVariant.danger),
      );
    }
  }
}
