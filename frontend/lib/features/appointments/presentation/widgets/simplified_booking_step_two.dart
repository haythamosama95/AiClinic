import 'dart:async';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_session.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/alternate_doctors_dialog.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_day_strip.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_slot_summary_card.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_time_block_grid.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Step two of simplified booking: day strip, block grid, and summary card (011).
class SimplifiedBookingStepTwo extends ConsumerStatefulWidget {
  const SimplifiedBookingStepTwo({
    required this.session,
    required this.doctors,
    required this.onSessionChanged,
    required this.onBookingComplete,
    this.enabled = true,
    super.key,
  });

  final SimplifiedBookingSession session;
  final List<StaffListItem> doctors;
  final ValueChanged<SimplifiedBookingSession> onSessionChanged;
  final VoidCallback onBookingComplete;
  final bool enabled;

  @override
  ConsumerState<SimplifiedBookingStepTwo> createState() => _SimplifiedBookingStepTwoState();
}

class _SimplifiedBookingStepTwoState extends ConsumerState<SimplifiedBookingStepTwo> {
  List<SimplifiedBookingSlot> _slots = const [];
  bool _loadingSlots = true;
  bool _slotsAvailable = true;
  String? _slotsError;
  int _loadGeneration = 0;
  int _slideDirection = 0;

  static String _dateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  bool get _hasPreferredDoctor {
    final preferred = widget.session.preferredDoctorId;
    return preferred != null && preferred.trim().isNotEmpty;
  }

  String? _rpcDoctorId() {
    final fromSession = widget.session.effectiveDoctorId ?? widget.session.preferredDoctorId;
    if (fromSession != null && fromSession.trim().isNotEmpty) {
      return fromSession;
    }
    return widget.doctors.firstOrNull?.id;
  }

  List<SimplifiedBookingSlot> _slotsForDisplay(List<SimplifiedBookingSlot> slots) {
    if (_hasPreferredDoctor) {
      return slots;
    }
    return [
      for (final slot in slots)
        if (slot.state == SlotAvailabilityState.alternateDoctorsAvailable)
          SimplifiedBookingSlot(
            startTime: slot.startTime,
            endTime: slot.endTime,
            state: SlotAvailabilityState.available,
            availableDoctorIds: slot.availableDoctorIds,
          )
        else
          slot,
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSlots());
  }

  @override
  void didUpdateWidget(covariant SimplifiedBookingStepTwo oldWidget) {
    super.didUpdateWidget(oldWidget);
    final doctorChanged =
        oldWidget.session.effectiveDoctorId != widget.session.effectiveDoctorId ||
        oldWidget.session.preferredDoctorId != widget.session.preferredDoctorId;
    final dateChanged = !_isSameDay(oldWidget.session.selectedDate, widget.session.selectedDate);
    if (doctorChanged) {
      _slideDirection = 0;
      _loadSlots();
    } else if (dateChanged) {
      _loadSlots();
    }
  }

  Future<void> _loadSlots() async {
    final doctorId = _rpcDoctorId();
    if (doctorId == null || doctorId.trim().isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingSlots = false;
        _slots = const [];
        _slotsAvailable = true;
        _slotsError = null;
      });
      return;
    }

    final generation = ++_loadGeneration;

    setState(() {
      _loadingSlots = true;
      _slotsError = null;
    });

    try {
      final daySlots = await ref
          .read(appointmentRepositoryProvider)
          .getSimplifiedBookingSlots(
            branchId: widget.session.branchId,
            localDate: widget.session.selectedDate,
            preferredDoctorId: doctorId,
          );
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loadingSlots = false;
        _slots = daySlots.blocks;
        _slotsAvailable = true;
      });
    } on RpcFailure catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loadingSlots = false;
        _slots = const [];
        _slotsAvailable = false;
        _slotsError = appointmentMessageForRpc(error);
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loadingSlots = false;
        _slots = const [];
        _slotsAvailable = false;
        _slotsError = UserErrorMapper.mapToUserMessage(error);
      });
    }
  }

  void _onDateSelected(DateTime date, {bool defer = false}) {
    final current = widget.session.selectedDate;
    final normalized = clampSimplifiedBookingDate(date);
    if (_isSameDay(normalized, current)) {
      return;
    }
    if (normalized.isAfter(current)) {
      _slideDirection = 1;
    } else if (normalized.isBefore(current)) {
      _slideDirection = -1;
    } else {
      _slideDirection = 0;
    }
    void apply() {
      if (!mounted) {
        return;
      }
      widget.onSessionChanged(widget.session.copyWith(selectedDate: normalized, clearSelectedSlot: true));
    }

    if (defer) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  void _onAvailableSlotSelected(SimplifiedBookingSlot slot) {
    final preferredDoctorId = widget.session.preferredDoctorId;
    if (preferredDoctorId == null || preferredDoctorId.trim().isEmpty) {
      unawaited(_onAlternateSlotTap(slot));
      return;
    }
    widget.onSessionChanged(widget.session.copyWith(selectedSlot: slot, effectiveDoctorId: preferredDoctorId));
  }

  Future<void> _onAlternateSlotTap(SimplifiedBookingSlot slot) async {
    await AlternateDoctorsDialog.show(
      context,
      slot: slot,
      doctors: widget.doctors,
      onDoctorSelected: (doctorId) {
        widget.onSessionChanged(widget.session.copyWith(selectedSlot: slot, effectiveDoctorId: doctorId));
      },
    );
  }

  String _doctorName(String? doctorId) {
    if (doctorId == null) {
      return 'Unknown doctor';
    }
    return widget.doctors.where((doctor) => doctor.id == doctorId).firstOrNull?.fullName ?? 'Unknown doctor';
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildSlotsPanel() {
    if (_loadingSlots) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: SpacingTokens.xl),
        child: Center(child: AppCircularProgress()),
      );
    }
    if (_slotsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppAlert(title: _slotsError!, variant: AppAlertVariant.destructive),
          const SizedBox(height: SpacingTokens.sm),
          AppButton(label: 'Retry', variant: AppButtonVariant.secondary, onPressed: _loadSlots),
        ],
      );
    }
    return SimplifiedTimeBlockGrid(
      slots: _slotsForDisplay(_slots),
      selectedStart: widget.session.selectedSlot?.startTime,
      onSlotTap: widget.enabled ? _onAvailableSlotSelected : (_) {},
      onAlternateSlotTap: widget.enabled ? _onAlternateSlotTap : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    final durationMinutes = session.defaultDurationMinutes;
    final effectiveDoctorId = session.effectiveDoctorId ?? session.preferredDoctorId;
    final dateRange = simplifiedBookingDateRange();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text('Select Date and Time', style: theme.textTheme.titleMedium)),
            const SizedBox(width: SpacingTokens.md),
            SizedBox(
              width: 148,
              child: AppDateField(
                key: const Key('simplified_booking_pick_date'),
                label: 'Date',
                size: AppFieldSize.sm,
                value: session.selectedDate,
                firstDate: dateRange.minDate,
                lastDate: dateRange.maxDate,
                enabled: widget.enabled,
                onChanged: widget.enabled
                    ? (date) {
                        if (date != null) {
                          _onDateSelected(clampSimplifiedBookingDate(date), defer: true);
                        }
                      }
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: SpacingTokens.md),
        SimplifiedDayStrip(selectedDate: session.selectedDate, onDateSelected: _onDateSelected),
        const SizedBox(height: SpacingTokens.md),
        Divider(height: 1, color: context.semanticColors.border),
        const SizedBox(height: SpacingTokens.md),
        AppPaginatedSlideSwitcher(
          pageKey: _dateKey(session.selectedDate),
          direction: _slideDirection,
          child: _buildSlotsPanel(),
        ),
        if (durationMinutes != null && session.patientId != null) ...[
          const SizedBox(height: SpacingTokens.lg),
          SimplifiedSlotSummaryCard(
            branchId: session.branchId,
            patientId: session.patientId!,
            effectiveDoctorId: effectiveDoctorId ?? '',
            defaultDurationMinutes: durationMinutes,
            doctorName: effectiveDoctorId != null ? _doctorName(effectiveDoctorId) : '',
            selectedDate: session.selectedDate,
            selectedSlot: session.selectedSlot,
            notes: session.notes,
            slotsAvailable: _slotsAvailable,
            onRetry: _loadSlots,
            onSlotsRefresh: _loadSlots,
            onBookingComplete: widget.onBookingComplete,
          ),
        ],
      ],
    );
  }
}
