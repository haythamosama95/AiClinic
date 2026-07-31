import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';
import 'package:ai_clinic/features/queue/domain/queue_start_doctor.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_start_doctor_dialog.dart';

/// Callback when a queue row action advances or terminates an appointment.
typedef QueueAppointmentTransitionCallback = void Function(
  String appointmentId,
  AppointmentStatus target, {
  String? doctorId,
});

/// Per-row status transition menu (web `AppointmentRowActions`).
class QueueRowActions extends StatefulWidget {
  const QueueRowActions({
    required this.appointment,
    required this.siblingAppointments,
    required this.shiftLookup,
    required this.onTransition,
    this.organizationTimezone = 'UTC',
    this.referenceUtc,
    this.inProgressBlocked,
    super.key,
  });

  final AppointmentListItem appointment;
  final List<AppointmentListItem> siblingAppointments;
  final AppointmentQueueShiftDoctorLookup shiftLookup;
  final QueueAppointmentTransitionCallback onTransition;
  final String organizationTimezone;
  final DateTime? referenceUtc;
  final AppointmentInProgressBlockedPredicate? inProgressBlocked;

  @override
  State<QueueRowActions> createState() => _QueueRowActionsState();
}

class _QueueRowActionsState extends State<QueueRowActions> {
  var _popoverOpen = false;

  AppointmentListItem get _appointment => widget.appointment;

  AppointmentInProgressBlockedPredicate get _inProgressBlocked =>
      widget.inProgressBlocked ??
      (item, siblings) => AppointmentQueueStartDoctor.isForwardInProgressBlocked(
        item: item,
        siblingAppointments: siblings,
        shiftLookup: widget.shiftLookup,
      );

  AppointmentStatus? get _forwardTarget => forwardStatusTargetFor(
    _appointment,
    organizationTimezone: widget.organizationTimezone,
    referenceUtc: widget.referenceUtc,
    siblingAppointments: widget.siblingAppointments,
    inProgressBlocked: _inProgressBlocked,
  );

  bool get _canCancel => canCancelAppointment(_appointment);

  bool get _canMarkNoShow => canMarkNoShowAppointment(
    _appointment,
    organizationTimezone: widget.organizationTimezone,
    referenceUtc: widget.referenceUtc,
  );

  bool get _hasActions =>
      _forwardTarget != null || _canCancel || _canMarkNoShow;

  void _closePopover() {
    if (_popoverOpen) {
      setState(() => _popoverOpen = false);
    }
  }

  Future<String?> _resolveDoctorForStart() async {
    final item = _appointment;
    if (!AppointmentQueueStartDoctor.requiresDoctorPicker(
      item: item,
      shiftLookup: widget.shiftLookup,
      siblingAppointments: widget.siblingAppointments,
    )) {
      final assigned = item.doctorId?.trim();
      if (assigned != null && assigned.isNotEmpty) {
        return assigned;
      }
      final options = AppointmentQueueStartDoctor.optionsForStart(
        item: item,
        siblingAppointments: widget.siblingAppointments,
        shiftLookup: widget.shiftLookup,
      );
      return options.where((option) => !option.isBusy).firstOrNull?.id;
    }

    final options = AppointmentQueueStartDoctor.optionsForStart(
      item: item,
      siblingAppointments: widget.siblingAppointments,
      shiftLookup: widget.shiftLookup,
    );
    if (!mounted) {
      return null;
    }
    return QueueStartDoctorDialog.show(context, options: options);
  }

  Future<void> _handleTransition(AppointmentStatus target) async {
    _closePopover();

    if (target == AppointmentStatus.inProgress) {
      final doctorId = await _resolveDoctorForStart();
      if (doctorId == null) {
        return;
      }
      widget.onTransition(
        _appointment.id,
        target,
        doctorId: doctorId,
      );
      return;
    }

    widget.onTransition(_appointment.id, target);
  }

  String _forwardLabel(AppointmentStatus target) {
    if (target == AppointmentStatus.inProgress) {
      return 'Start Consultation';
    }
    return forwardStatusActionLabelFor(
      _appointment,
      organizationTimezone: widget.organizationTimezone,
      referenceUtc: widget.referenceUtc,
      siblingAppointments: widget.siblingAppointments,
      inProgressBlocked: _inProgressBlocked,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasActions) {
      return const SizedBox.shrink();
    }

    final forwardTarget = _forwardTarget;

    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: AppPopover(
        open: _popoverOpen,
        onOpenChange: (open) => setState(() => _popoverOpen = open),
        align: AppPopoverAlign.end,
        matchTriggerWidth: false,
        minWidth: 160,
        triggerBuilder: (context, isOpen, toggle) {
          return Semantics(
            button: true,
            expanded: isOpen,
            label: 'Actions for ${_appointment.patientName}',
            child: AppButton(
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              onPressed: toggle,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Actions',
                    style: AppTypography.bodySm(context).copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space1),
                  Icon(
                    Icons.expand_more,
                    size: 12,
                    color: context.appColors.iconDefault,
                  ),
                ],
              ),
            ),
          );
        },
        child: Semantics(
          container: true,
          label: 'Appointment actions',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (forwardTarget != null)
                _QueueRowActionMenuItem(
                  label: _forwardLabel(forwardTarget),
                  onPressed: () => _handleTransition(forwardTarget),
                ),
              if (_canCancel)
                _QueueRowActionMenuItem(
                  label: 'Cancel',
                  destructive: true,
                  onPressed: () =>
                      _handleTransition(AppointmentStatus.cancelled),
                ),
              if (_canMarkNoShow)
                _QueueRowActionMenuItem(
                  label: 'No Show',
                  destructive: true,
                  onPressed: () =>
                      _handleTransition(AppointmentStatus.noShow),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueRowActionMenuItem extends StatefulWidget {
  const _QueueRowActionMenuItem({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  State<_QueueRowActionMenuItem> createState() =>
      _QueueRowActionMenuItemState();
}

class _QueueRowActionMenuItemState extends State<_QueueRowActionMenuItem> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dangerSurface = isDark
        ? AppColorPrimitives.statusDangerSurfaceDark
        : AppColorPrimitives.red50;

    final foreground = widget.destructive
        ? colors.statusDangerFg
        : colors.textPrimary;

    final background = _hovered
        ? (widget.destructive ? dangerSurface : colors.surfaceHover)
        : Colors.transparent;

    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AppPressable(
            onPressed: widget.onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space3,
                vertical: 6,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  widget.label,
                  style: AppTypography.body(context).copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
