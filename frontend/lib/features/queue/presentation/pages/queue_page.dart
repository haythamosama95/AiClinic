import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_today_range.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_cancel_dialog.dart';
import 'package:ai_clinic/features/queue/domain/queue_display.dart';
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';
import 'package:ai_clinic/features/queue/presentation/providers/queue_provider.dart';
import 'package:ai_clinic/features/queue/presentation/providers/queue_shift_provider.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_appointments_table.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_confirm_dialog.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_flow_control_panel.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_kpi_carousel.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_secretary_utils.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_toolbar.dart';

class _PendingConfirm {
  const _PendingConfirm({required this.appointmentId, required this.target, required this.patientName});

  final String appointmentId;
  final AppointmentStatus target;
  final String patientName;
}

/// Today's clinic queue page (web `QueuePage`).
class QueuePage extends ConsumerStatefulWidget {
  const QueuePage({super.key});

  @override
  ConsumerState<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends ConsumerState<QueuePage> {
  static const _largeBreakpoint = 1024.0;
  static const _xlBreakpoint = 1280.0;
  static const _sideRailWidthLg = 340.0;
  static const _sideRailWidthXl = 380.0;

  Timer? _nowTimer;
  DateTime _now = DateTime.now();
  String _search = '';
  final Set<AppointmentStatus> _statusFilters = {};
  _PendingConfirm? _pendingConfirm;
  var _transitionBusy = false;

  @override
  void initState() {
    super.initState();
    _nowTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _nowTimer?.cancel();
    super.dispose();
  }

  String get _organizationTimezone =>
      effectiveOrganizationTimezone(ref.read(authSessionProvider).context?.organizationTimezone);

  AppointmentQueueShiftDoctorLookup get _emptyShiftLookup => AppointmentQueueShiftDoctorLookup.empty;

  AppointmentListItem? _findAppointment(List<AppointmentListItem> items, String appointmentId) {
    for (final item in items) {
      if (item.id == appointmentId) {
        return item;
      }
    }
    return null;
  }

  QueueKpiCarouselTrends _buildTrends({
    required List<AppointmentListItem> items,
    required List<AppointmentListItem>? comparisonItems,
    required DateTime now,
    required DateTime? comparisonNow,
  }) {
    final partition = AppointmentQueueDisplay.partition(items, now: now);
    final waiting = partition.waiting.length;
    final checkedIn = waiting;
    final inProgress = items.where((item) => item.status == AppointmentStatus.inProgress).length;
    final cancelled = items.where((item) => item.status == AppointmentStatus.cancelled).length;
    final queueLength = waiting;

    if (comparisonItems == null) {
      return QueueKpiCarouselTrends(
        waiting: waiting,
        checkedIn: checkedIn,
        inProgress: inProgress,
        cancelled: cancelled,
        queueLength: queueLength,
      );
    }

    final previousNow = comparisonNow ?? now;
    final previousPartition = AppointmentQueueDisplay.partition(comparisonItems, now: previousNow);
    final previousWaiting = previousPartition.waiting.length;
    final previousCheckedIn = previousWaiting;
    final previousInProgress = comparisonItems.where((item) => item.status == AppointmentStatus.inProgress).length;
    final previousCancelled = comparisonItems.where((item) => item.status == AppointmentStatus.cancelled).length;

    return QueueKpiCarouselTrends(
      waiting: waiting,
      checkedIn: checkedIn,
      inProgress: inProgress,
      cancelled: cancelled,
      queueLength: queueLength,
      waitingTrend: AppointmentQueueStatTrend(percentChange: _percentChange(waiting, previousWaiting)),
      checkedInTrend: AppointmentQueueStatTrend(percentChange: _percentChange(checkedIn, previousCheckedIn)),
      inProgressTrend: AppointmentQueueStatTrend(percentChange: _percentChange(inProgress, previousInProgress)),
      cancelledTrend: AppointmentQueueStatTrend(percentChange: _percentChange(cancelled, previousCancelled)),
      queueLengthTrend: AppointmentQueueStatTrend(percentChange: _percentChange(queueLength, previousWaiting)),
    );
  }

  double? _percentChange(int current, int previous) {
    if (previous == 0) {
      return current == 0 ? 0 : null;
    }
    return ((current - previous) / previous) * 100;
  }

  List<AppointmentListItem> _filterTableAppointments(List<AppointmentListItem> items) {
    var result = queueFilterByStatus(items, _statusFilters);
    final query = _search.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((item) => item.patientName.toLowerCase().contains(query)).toList(growable: false);
    }
    return sortAppointmentsByStartTime(result);
  }

  void _handleTransition(String appointmentId, AppointmentStatus target, {String? doctorId}) {
    if (_transitionBusy) {
      return;
    }

    final items = ref.read(appointmentQueueProvider).items;
    final appointment = _findAppointment(items, appointmentId);
    if (appointment == null) {
      return;
    }

    if (target == AppointmentStatus.cancelled || target == AppointmentStatus.noShow) {
      setState(() {
        _pendingConfirm = _PendingConfirm(
          appointmentId: appointmentId,
          target: target,
          patientName: appointment.patientName,
        );
      });
      return;
    }

    unawaited(_applyTransition(appointment, target, doctorId: doctorId));
  }

  Future<void> _applyTransition(AppointmentListItem appointment, AppointmentStatus target, {String? doctorId}) async {
    if (_transitionBusy) {
      return;
    }

    final canAdvance = ref.read(authSessionProvider.select(AuthRouteGuard.canAccessAppointmentBooking));
    if (!canAdvance) {
      if (mounted) {
        appToast(
          context,
          const AppToastInput(
            message: 'You do not have permission to manage appointments.',
            variant: AppToastVariant.danger,
          ),
        );
      }
      return;
    }

    setState(() => _transitionBusy = true);
    final appointmentId = appointment.id;
    final patientName = appointment.patientName;

    try {
      final repository = ref.read(appointmentRepositoryProvider);

      if (target == AppointmentStatus.inProgress) {
        final selectedDoctorId = doctorId ?? appointment.doctorId?.trim();
        if (selectedDoctorId == null || selectedDoctorId.isEmpty) {
          return;
        }

        final assignedDoctorId = appointment.doctorId?.trim();
        if (assignedDoctorId == null || assignedDoctorId.isEmpty || assignedDoctorId != selectedDoctorId) {
          await repository.updateAppointment(
            appointmentId: appointment.id,
            patientId: appointment.patientId,
            doctorId: selectedDoctorId,
            startTime: appointment.startTime,
            endTime: appointment.endTime,
          );
        }
      }

      final update = await switch (target) {
        AppointmentStatus.cancelled => _cancelWithReason(repository, appointment),
        AppointmentStatus.noShow =>
          repository
              .markAppointmentNoShow(appointmentId: appointment.id)
              .then(
                (status) => (
                  status: status,
                  updatedAt: DateTime.now().toUtc(),
                  checkedInAt: appointment.checkedInAt,
                  inProgressAt: appointment.inProgressAt,
                ),
              ),
        _ =>
          repository
              .updateAppointmentStatus(appointmentId: appointment.id, newStatus: target)
              .then(
                (result) => (
                  status: result.status,
                  updatedAt: result.updatedAt,
                  checkedInAt: result.checkedInAt,
                  inProgressAt: result.inProgressAt,
                ),
              ),
      };

      ref
          .read(appointmentQueueProvider.notifier)
          .patchAppointmentStatus(
            appointmentId: appointmentId,
            newStatus: update.status,
            doctorId: doctorId ?? appointment.doctorId,
            updatedAt: update.updatedAt,
            checkedInAt: update.checkedInAt,
            inProgressAt: update.inProgressAt,
          );

      if (!mounted) {
        return;
      }

      final successMessage = AppointmentQueueDisplay.statusTransitionToastMessage(
        patientName: patientName,
        newStatus: update.status,
      );
      final revertTarget = previousStatusTargetFor(appointment.copyWith(status: update.status));
      if (revertTarget != null && canRevertAppointmentStatus(appointment.copyWith(status: update.status))) {
        appToast(
          context,
          AppToastInput(
            message: successMessage,
            variant: AppToastVariant.success,
            action: AppToastAction(
              label: 'Undo',
              onPressed: () => unawaited(
                _revertTransition(
                  appointmentId: appointmentId,
                  currentStatus: update.status,
                  revertTarget: revertTarget,
                  patientName: patientName,
                ),
              ),
            ),
          ),
        );
      } else {
        appToast(context, AppToastInput(message: successMessage, variant: AppToastVariant.success));
      }
    } on _QueueTransitionCancelled {
      return;
    } on RpcFailure catch (error) {
      if (mounted) {
        appToast(context, AppToastInput(message: appointmentMessageForRpc(error), variant: AppToastVariant.danger));
      }
    } catch (_) {
      if (mounted) {
        appToast(
          context,
          const AppToastInput(
            message: 'Could not update the appointment status. Please try again.',
            variant: AppToastVariant.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _transitionBusy = false);
      }
    }
  }

  Future<({AppointmentStatus status, DateTime? updatedAt, DateTime? checkedInAt, DateTime? inProgressAt})>
  _cancelWithReason(AppointmentRepository repository, AppointmentListItem appointment) async {
    final reason = await AppointmentCancelDialog.show(context, appointment: appointment);
    if (reason == null) {
      throw _QueueTransitionCancelled();
    }
    final status = await repository.cancelAppointment(appointmentId: appointment.id, reason: reason);
    return (
      status: status,
      updatedAt: DateTime.now().toUtc(),
      checkedInAt: appointment.checkedInAt,
      inProgressAt: appointment.inProgressAt,
    );
  }

  Future<void> _revertTransition({
    required String appointmentId,
    required AppointmentStatus currentStatus,
    required AppointmentStatus revertTarget,
    required String patientName,
  }) async {
    try {
      final result = await ref
          .read(appointmentRepositoryProvider)
          .updateAppointmentStatus(appointmentId: appointmentId, newStatus: revertTarget);

      ref
          .read(appointmentQueueProvider.notifier)
          .patchAppointmentStatus(
            appointmentId: appointmentId,
            newStatus: result.status,
            updatedAt: result.updatedAt,
            checkedInAt: result.checkedInAt,
            inProgressAt: result.inProgressAt,
          );

      if (mounted) {
        appToast(
          context,
          AppToastInput(
            message: AppointmentQueueDisplay.statusRevertToastMessage(
              patientName: patientName,
              revertedTo: revertTarget,
            ),
            variant: AppToastVariant.success,
          ),
        );
      }
    } on RpcFailure catch (error) {
      if (mounted) {
        appToast(context, AppToastInput(message: appointmentMessageForRpc(error), variant: AppToastVariant.danger));
      }
    } catch (_) {
      if (mounted) {
        appToast(
          context,
          const AppToastInput(
            message: 'Could not revert the appointment status. Please try again.',
            variant: AppToastVariant.danger,
          ),
        );
      }
    }
  }

  Future<void> _confirmPendingTransition() async {
    final pending = _pendingConfirm;
    if (pending == null) {
      return;
    }

    setState(() => _pendingConfirm = null);
    final items = ref.read(appointmentQueueProvider).items;
    final appointment = items.firstWhere((item) => item.id == pending.appointmentId);

    if (pending.target == AppointmentStatus.cancelled) {
      await _applyTransition(appointment, pending.target);
      return;
    }

    await _applyTransition(appointment, pending.target);
  }

  @override
  Widget build(BuildContext context) {
    final queueState = ref.watch(appointmentQueueProvider);
    final shiftLookupAsync = ref.watch(appointmentQueueShiftDoctorLookupProvider);
    final shiftLookup = shiftLookupAsync.maybeWhen(data: (lookup) => lookup, orElse: () => _emptyShiftLookup);

    if (queueState.loading && queueState.items.isEmpty) {
      return const AppLoadingOverlay(loading: true, label: 'Loading queue', scoped: true, child: SizedBox.expand());
    }

    if (queueState.error != null && queueState.items.isEmpty) {
      return AppErrorState(
        title: 'Unable to load queue',
        message: queueState.error!,
        onRetry: () => ref.read(appointmentQueueProvider.notifier).refresh(),
      );
    }

    final items = queueState.items;
    final stats = AppointmentQueueDisplay.computeStats(
      items,
      now: _now,
      comparisonItems: queueState.comparisonItems,
      comparisonNow: queueState.comparisonNow,
    );
    final trends = _buildTrends(
      items: items,
      comparisonItems: queueState.comparisonItems,
      now: _now,
      comparisonNow: queueState.comparisonNow,
    );
    final filteredAppointments = _filterTableAppointments(items);

    return Stack(
      children: [
        AppLoadingOverlay(
          loading: queueState.loading,
          label: 'Refreshing queue',
          scoped: true,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.space6,
              children: [
                const AppPageHeader(
                  title: 'Queue',
                  description: "Today's patient flow — scan exceptions, move patients forward",
                ),
                QueueKpiCarousel(stats: stats, trends: trends),
                QueueToolbar(
                  search: _search,
                  onSearchChange: (value) => setState(() => _search = value),
                  statusFilters: _statusFilters,
                  onToggleStatus: (status) {
                    setState(() {
                      if (_statusFilters.contains(status)) {
                        _statusFilters.remove(status);
                      } else {
                        _statusFilters.add(status);
                      }
                    });
                  },
                  onClearFilters: () => setState(_statusFilters.clear),
                ),
                if (items.isEmpty)
                  const AppEmptyState(
                    variant: AppEmptyStateVariant.firstRun,
                    title: 'No appointments today',
                    description: 'Checked-in patients and today\'s schedule will appear here.',
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final useSideBySide = width >= _largeBreakpoint;
                      final sideRailWidth = width >= _xlBreakpoint ? _sideRailWidthXl : _sideRailWidthLg;

                      final tableSection = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "Today's appointments",
                                  style: AppTypography.bodySm(
                                    context,
                                  ).copyWith(fontWeight: FontWeight.w600, color: context.appColors.textPrimary),
                                ),
                              ),
                              Text(
                                '${filteredAppointments.length} shown',
                                style: AppTypography.caption(context).copyWith(color: context.appColors.textSecondary),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.space3),
                          QueueAppointmentsTable(
                            appointments: filteredAppointments,
                            siblingAppointments: items,
                            shiftLookup: shiftLookup,
                            now: _now,
                            organizationTimezone: _organizationTimezone,
                            referenceUtc: DateTime.now().toUtc(),
                            onTransition: _handleTransition,
                          ),
                        ],
                      );

                      final flowPanel = QueueFlowControlPanel(appointments: items, now: _now);

                      if (!useSideBySide) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: AppSpacing.space6,
                          children: [tableSection, flowPanel],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: AppSpacing.space6,
                        children: [
                          Expanded(child: tableSection),
                          SizedBox(width: sideRailWidth, child: flowPanel),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        QueueConfirmDialog(
          open: _pendingConfirm != null,
          kind: _pendingConfirm?.target == AppointmentStatus.noShow ? QueueConfirmKind.noShow : QueueConfirmKind.cancel,
          patientName: _pendingConfirm?.patientName ?? '',
          onConfirm: _confirmPendingTransition,
          onCancel: () => setState(() => _pendingConfirm = null),
        ),
      ],
    );
  }
}

class _QueueTransitionCancelled implements Exception {}
