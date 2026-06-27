import 'dart:async';
import 'dart:ui';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_session.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_booking_step_one.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_booking_step_two.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract final class _SimplifiedBookingFlowPalette {
  static const modalRadius = 24.0;
  static const maxWidth = 560.0;
}

enum _SimplifiedBookingStep { one, two }

/// Two-step simplified booking modal launched from the calendar header (011).
class SimplifiedBookingFlow extends ConsumerStatefulWidget {
  const SimplifiedBookingFlow({required this.branchId, required this.schedule, required this.doctors, super.key});

  final String branchId;
  final BranchWorkingSchedule schedule;
  final List<StaffListItem> doctors;

  /// Presents the two-step booking flow. Returns `true` when an appointment was created.
  static Future<bool?> show(
    BuildContext context, {
    required String branchId,
    required BranchWorkingSchedule schedule,
    required List<StaffListItem> doctors,
  }) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return UncontrolledProviderScope(
          container: ProviderScope.containerOf(context, listen: false),
          child: _SimplifiedBookingModalOverlay(branchId: branchId, schedule: schedule, doctors: doctors),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  @override
  ConsumerState<SimplifiedBookingFlow> createState() => _SimplifiedBookingFlowState();
}

class _SimplifiedBookingModalOverlay extends StatelessWidget {
  const _SimplifiedBookingModalOverlay({required this.branchId, required this.schedule, required this.doctors});

  final String branchId;
  final BranchWorkingSchedule schedule;
  final List<StaffListItem> doctors;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: ColoredBox(color: colors.background.withValues(alpha: 0.35)),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.xl),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: _SimplifiedBookingFlowPalette.maxWidth, maxHeight: maxHeight),
                  child: SimplifiedBookingFlow(branchId: branchId, schedule: schedule, doctors: doctors),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimplifiedBookingFlowState extends ConsumerState<SimplifiedBookingFlow> {
  _SimplifiedBookingStep _step = _SimplifiedBookingStep.one;
  late SimplifiedBookingSession _session;

  bool _loadingStepTwo = false;
  String? _stepTwoError;

  @override
  void initState() {
    super.initState();
    _session = SimplifiedBookingSession.initial(branchId: widget.branchId);
  }

  Future<void> _advanceToStepTwo(SimplifiedBookingSession updatedSession) async {
    if (!updatedSession.canAdvanceFromStepOne) {
      return;
    }

    setState(() {
      _loadingStepTwo = true;
      _stepTwoError = null;
      _session = updatedSession;
    });

    try {
      final settings = await ref.read(appointmentRepositoryProvider).getSettings(branchId: widget.branchId);
      if (!mounted) {
        return;
      }
      setState(() {
        _session = updatedSession.forStepTwoEntry(defaultDurationMinutes: settings.defaultDurationMinutes);
        _step = _SimplifiedBookingStep.two;
        _loadingStepTwo = false;
      });
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingStepTwo = false;
        _stepTwoError = appointmentMessageForRpc(error);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingStepTwo = false;
        _stepTwoError = UserErrorMapper.mapToUserMessage(error);
      });
    }
  }

  void _backToStepOne() {
    setState(() {
      _step = _SimplifiedBookingStep.one;
      _session = _session.clearSlot();
      _stepTwoError = null;
    });
  }

  void _onBookingComplete() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
    AppToast.success(context, message: 'Appointment booked successfully.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(_SimplifiedBookingFlowPalette.modalRadius),
        boxShadow: ShadowTokens.shadowLg,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.all(SpacingTokens.xl),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (_step == _SimplifiedBookingStep.two)
                        IconButton(
                          key: const Key('simplified_booking_back'),
                          tooltip: 'Back',
                          onPressed: _loadingStepTwo ? null : _backToStepOne,
                          icon: const Icon(Icons.arrow_back, size: 20),
                        )
                      else
                        const SizedBox(width: 48),
                      Expanded(
                        child: Text(
                          _step == _SimplifiedBookingStep.one ? 'Step 1 / 2' : 'Step 2 / 2',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium?.copyWith(color: colors.mutedForeground),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  if (_loadingStepTwo)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: SpacingTokens.xl),
                      child: Center(child: AppCircularProgress()),
                    )
                  else if (_stepTwoError != null) ...[
                    AppAlert(title: _stepTwoError!, variant: AppAlertVariant.destructive),
                    const SizedBox(height: SpacingTokens.sm),
                    AppButton(
                      label: 'Retry',
                      variant: AppButtonVariant.secondary,
                      onPressed: () => unawaited(_advanceToStepTwo(_session)),
                    ),
                  ] else if (_step == _SimplifiedBookingStep.one)
                    SimplifiedBookingStepOne(
                      branchId: widget.branchId,
                      doctors: widget.doctors,
                      session: _session,
                      enabled: !_loadingStepTwo,
                      onNext: (session) => unawaited(_advanceToStepTwo(session)),
                    )
                  else
                    SimplifiedBookingStepTwo(
                      session: _session,
                      doctors: widget.doctors,
                      enabled: !_loadingStepTwo,
                      onSessionChanged: (session) => setState(() => _session = session),
                      onBookingComplete: _onBookingComplete,
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            top: SpacingTokens.sm,
            right: SpacingTokens.sm,
            child: IconButton(
              onPressed: _loadingStepTwo ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 20),
              style: IconButton.styleFrom(
                foregroundColor: colors.mutedForeground,
                backgroundColor: colors.background.withValues(alpha: 0.9),
                padding: const EdgeInsets.all(SpacingTokens.sm),
                minimumSize: const Size(36, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              tooltip: 'Close',
            ),
          ),
        ],
      ),
    );
  }
}
