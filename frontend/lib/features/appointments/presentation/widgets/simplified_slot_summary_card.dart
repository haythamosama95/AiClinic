import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Bottom summary card for simplified booking confirmation (011).
class SimplifiedSlotSummaryCard extends ConsumerStatefulWidget {
  const SimplifiedSlotSummaryCard({
    required this.branchId,
    required this.patientId,
    required this.effectiveDoctorId,
    required this.defaultDurationMinutes,
    required this.doctorName,
    required this.selectedDate,
    required this.slotsAvailable,
    required this.onSlotsRefresh,
    this.selectedSlot,
    this.notes,
    this.onRetry,
    this.onBookingComplete,
    super.key,
  });

  final String branchId;
  final String patientId;
  final String effectiveDoctorId;
  final int defaultDurationMinutes;
  final String doctorName;
  final DateTime selectedDate;
  final SimplifiedBookingSlot? selectedSlot;
  final String? notes;
  final bool slotsAvailable;
  final VoidCallback? onRetry;
  final VoidCallback onSlotsRefresh;
  final VoidCallback? onBookingComplete;

  @override
  ConsumerState<SimplifiedSlotSummaryCard> createState() => _SimplifiedSlotSummaryCardState();
}

class _SimplifiedSlotSummaryCardState extends ConsumerState<SimplifiedSlotSummaryCard> {
  static const _maxNotesLength = 2000;

  bool _isSaving = false;
  String? _errorMessage;

  bool get _hasSelection => widget.selectedSlot != null;

  bool get _hasDoctor => widget.effectiveDoctorId.trim().isNotEmpty;

  bool get _notesValid => (widget.notes?.trim().length ?? 0) <= _maxNotesLength;

  bool get _canConfirm => _hasSelection && widget.slotsAvailable && !_isSaving && _hasDoctor && _notesValid;

  String? _confirmBlockedMessage() {
    if (!_hasSelection) {
      return null;
    }
    if (!_hasDoctor) {
      return 'Select a doctor for this time slot before confirming.';
    }
    if (!_notesValid) {
      return 'Notes must be $_maxNotesLength characters or fewer.';
    }
    return null;
  }

  Future<void> _confirm() async {
    final slot = widget.selectedSlot;
    if (slot == null || !_canConfirm) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(appointmentRepositoryProvider)
          .createAppointment(
            branchId: widget.branchId,
            patientId: widget.patientId,
            doctorId: widget.effectiveDoctorId,
            type: AppointmentType.planned,
            startTime: slot.startTime,
            durationMinutes: widget.defaultDurationMinutes,
            notes: widget.notes,
          );
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == 'SCHEDULE_CONFLICT') {
        widget.onSlotsRefresh();
      }
      setState(() {
        _isSaving = false;
        _errorMessage = appointmentMessageForRpc(error);
      });
      return;
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = UserErrorMapper.mapToUserMessage(error);
      });
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() => _isSaving = false);
    widget.onBookingComplete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final slot = widget.selectedSlot;
    final summaryLabel = slot == null ? 'Select a time slot above' : _formatSelection(slot);
    final confirmBlockedMessage = _confirmBlockedMessage();

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        gradient: LinearGradient(
          colors: [colors.primary.withValues(alpha: 0.18), colors.accent.withValues(alpha: 0.12), colors.card],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: colors.primary.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Currently Selected:', style: theme.textTheme.labelMedium?.copyWith(color: colors.mutedForeground)),
            const SizedBox(height: SpacingTokens.xs),
            Text(summaryLabel, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (_hasSelection && widget.doctorName.trim().isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.xs),
              Text(widget.doctorName, style: theme.textTheme.bodySmall),
            ],
            if (!widget.slotsAvailable) ...[
              const SizedBox(height: SpacingTokens.sm),
              AppAlert(
                title: 'Could not load available slots. Try again before confirming.',
                variant: AppAlertVariant.destructive,
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(height: SpacingTokens.sm),
                AppButton(label: 'Retry', variant: AppButtonVariant.secondary, onPressed: widget.onRetry),
              ],
            ],
            if (confirmBlockedMessage != null) ...[
              const SizedBox(height: SpacingTokens.sm),
              AppAlert(title: confirmBlockedMessage, variant: AppAlertVariant.destructive),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: SpacingTokens.sm),
              AppAlert(title: _errorMessage!, variant: AppAlertVariant.destructive),
            ],
            const SizedBox(height: SpacingTokens.sm),
            AppButton(
              key: const Key('simplified_slot_confirm'),
              label: 'Confirm appointment',
              expand: true,
              isLoading: _isSaving,
              onPressed: _canConfirm ? _confirm : null,
            ),
          ],
        ),
      ),
    );
  }

  String _formatSelection(SimplifiedBookingSlot slot) {
    final localStart = slot.startTime.toLocal();
    final localEnd = localStart.add(Duration(minutes: widget.defaultDurationMinutes));
    final weekday = DateFormat.EEEE().format(widget.selectedDate);
    final monthDay = DateFormat.MMMd().format(widget.selectedDate);
    final from = DateFormat.jm().format(localStart);
    final to = DateFormat.jm().format(localEnd);
    return '$weekday, $monthDay, $from – $to';
  }
}
