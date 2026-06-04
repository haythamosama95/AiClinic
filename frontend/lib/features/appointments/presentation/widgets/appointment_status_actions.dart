import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/domain/create_appointment_result.dart';
import 'package:ai_clinic/features/appointments/presentation/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_cancel_dialog.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_reschedule_dialog.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/visit_create_dialog.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';

/// Check-in / start / visit actions, reschedule, and cancel controls for an appointment row (V1-4 + V1-5 US1).
class AppointmentStatusActions extends ConsumerStatefulWidget {
  const AppointmentStatusActions({
    super.key,
    required this.item,
    this.onStatusChanged,
    this.onRescheduled,
    this.onVisitChanged,
    this.dense = false,
  });

  final AppointmentListItem item;
  final ValueChanged<AppointmentStatus>? onStatusChanged;
  final ValueChanged<CreateAppointmentResult>? onRescheduled;
  final VoidCallback? onVisitChanged;
  final bool dense;

  @override
  ConsumerState<AppointmentStatusActions> createState() => _AppointmentStatusActionsState();
}

class _AppointmentStatusActionsState extends ConsumerState<AppointmentStatusActions> {
  bool _submitting = false;
  String? _error;
  String? _linkedVisitId;
  bool _visitLookupDone = false;

  AppointmentListItem get _item => widget.item;

  bool get _canStartVisit {
    return _item.status == AppointmentStatus.checkedIn || _item.status == AppointmentStatus.inProgress;
  }

  @override
  void initState() {
    super.initState();
    _refreshVisitLink();
  }

  @override
  void didUpdateWidget(covariant AppointmentStatusActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id || oldWidget.item.status != widget.item.status) {
      setState(() {
        _error = null;
        _submitting = false;
      });
      _refreshVisitLink();
    }
  }

  Future<void> _refreshVisitLink() async {
    final permissions = ref.read(permissionServiceProvider);
    if (!permissions.canCreateVisits() || !_canStartVisit) {
      if (mounted) {
        setState(() {
          _linkedVisitId = null;
          _visitLookupDone = true;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _visitLookupDone = false);
    }

    try {
      final link = await ref.read(visitRepositoryProvider).getVisitByAppointment(appointmentId: _item.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _linkedVisitId = link.visitId?.trim().isNotEmpty == true ? link.visitId : null;
        _visitLookupDone = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _linkedVisitId = null;
        _visitLookupDone = true;
      });
    }
  }

  Future<void> _advance() async {
    final timezone = effectiveOrganizationTimezone(ref.read(authSessionProvider).context?.organizationTimezone);
    final referenceUtc = DateTime.now().toUtc();
    final target = forwardStatusTargetFor(_item, organizationTimezone: timezone, referenceUtc: referenceUtc);
    if (target == null || _submitting) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final updated = await ref
          .read(appointmentRepositoryProvider)
          .updateAppointmentStatus(appointmentId: _item.id, newStatus: target);

      if (!mounted) {
        return;
      }

      setState(() => _submitting = false);
      widget.onStatusChanged?.call(updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status updated to ${updated.label}.')));
      await _refreshVisitLink();
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = appointmentMessageForRpc(error);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = UserErrorMapper.mapToUserMessage(error);
      });
    }
  }

  Future<void> _openVisitDocumentation(String visitId) async {
    if (!mounted) {
      return;
    }
    await context.push(AppRoutes.visitDocument(visitId));
    if (!mounted) {
      return;
    }
    widget.onVisitChanged?.call();
    await _refreshVisitLink();
  }

  Future<void> _createOrOpenVisit() async {
    if (_submitting) {
      return;
    }

    final existingVisitId = _linkedVisitId;
    if (existingVisitId != null && existingVisitId.isNotEmpty) {
      await _openVisitDocumentation(existingVisitId);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final created = await VisitCreateDialog.show(context, item: _item);
    if (!mounted) {
      return;
    }

    setState(() => _submitting = false);

    if (created == null) {
      return;
    }

    widget.onVisitChanged?.call();
    await _openVisitDocumentation(created.visitId);
  }

  Future<void> _openReschedule() async {
    if (_submitting) {
      return;
    }

    final result = await AppointmentRescheduleDialog.show(context, item: _item);
    if (!mounted || result == null) {
      return;
    }

    widget.onRescheduled?.call(result);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment rescheduled.')));
  }

  Future<void> _openCancelOrNoShow() async {
    if (_submitting) {
      return;
    }

    final updated = await AppointmentCancelDialog.show(context, item: _item);
    if (!mounted || updated == null) {
      return;
    }

    widget.onStatusChanged?.call(updated);
    final message = switch (updated) {
      AppointmentStatus.cancelled => 'Appointment cancelled.',
      AppointmentStatus.noShow => 'Appointment marked as no-show.',
      _ => 'Status updated to ${updated.label}.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionServiceProvider);
    final timezone = effectiveOrganizationTimezone(ref.watch(authSessionProvider).context?.organizationTimezone);
    final referenceUtc = DateTime.now().toUtc();
    final canCreateAppt = permissions.canCreateAppointments();
    final canCancel = permissions.canCancelAppointments();
    final canCreateVisit = permissions.canCreateVisits();
    final target = forwardStatusTargetFor(_item, organizationTimezone: timezone, referenceUtc: referenceUtc);
    final label = forwardStatusActionLabelFor(_item, organizationTimezone: timezone, referenceUtc: referenceUtc);
    final showStatus = canCreateAppt && target != null && label.isNotEmpty && !_item.status.isTerminal;
    final showReschedule = canCreateAppt && canRescheduleAppointment(_item);
    final showCancel =
        canCancel && canCancelOrNoShowAppointment(_item, organizationTimezone: timezone, referenceUtc: referenceUtc);
    final showVisitAction = canCreateVisit && _canStartVisit && _visitLookupDone;
    final visitLabel = _linkedVisitId != null ? 'Open visit' : 'Create visit';
    final visitKey = _linkedVisitId != null
        ? const Key('appointments_visit_open')
        : const Key('appointments_visit_create');

    if (!showStatus && !showReschedule && !showCancel && !showVisitAction) {
      return const SizedBox.shrink();
    }

    final buttonKey = switch (target) {
      AppointmentStatus.confirmed => const Key('appointments_status_confirm'),
      AppointmentStatus.checkedIn => const Key('appointments_status_check_in'),
      AppointmentStatus.inProgress => const Key('appointments_status_start'),
      _ => const Key('appointments_status_advance'),
    };

    final statusButton = _submitting
        ? SizedBox(
            width: widget.dense ? 20 : 24,
            height: widget.dense ? 20 : 24,
            child: const CircularProgressIndicator(strokeWidth: 2),
          )
        : widget.dense
        ? TextButton(key: buttonKey, onPressed: _advance, child: Text(label))
        : FilledButton.tonal(key: buttonKey, onPressed: _advance, child: Text(label));

    final visitButton = widget.dense
        ? TextButton(key: visitKey, onPressed: _submitting ? null : _createOrOpenVisit, child: Text(visitLabel))
        : FilledButton(key: visitKey, onPressed: _submitting ? null : _createOrOpenVisit, child: Text(visitLabel));

    final rescheduleButton = TextButton(
      key: const Key('appointments_status_reschedule'),
      onPressed: _submitting ? null : _openReschedule,
      child: const Text('Reschedule'),
    );

    final cancelButton = TextButton(
      key: const Key('appointments_status_cancel'),
      onPressed: _submitting ? null : _openCancelOrNoShow,
      child: const Text('Cancel / no-show'),
    );

    final actionButtons = <Widget>[
      if (showStatus) statusButton,
      if (showVisitAction) visitButton,
      if (showReschedule) rescheduleButton,
      if (showCancel) cancelButton,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (actionButtons.length == 1)
          actionButtons.first
        else
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: actionButtons),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(
            _error!,
            key: const Key('appointments_status_error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
