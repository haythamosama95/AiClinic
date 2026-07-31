import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Pending undo action surfaced by [QueueUndoToastController].
class QueueUndoToastState {
  const QueueUndoToastState({
    required this.message,
    required this.onUndo,
  });

  final String message;
  final Future<void> Function() onUndo;
}

/// Controls the queue undo toast with a 5-second auto-dismiss window.
class QueueUndoToastController extends ChangeNotifier {
  QueueUndoToastState? _state;
  Timer? _timer;

  QueueUndoToastState? get state => _state;

  void show({
    required String message,
    required Future<void> Function() onUndo,
  }) {
    _timer?.cancel();
    _state = QueueUndoToastState(message: message, onUndo: onUndo);
    notifyListeners();
    _timer = Timer(const Duration(seconds: 5), dismiss);
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_state == null) {
      return;
    }
    _state = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Bottom-centred undo affordance after a status transition (web `UndoToast`).
class QueueUndoToast extends StatelessWidget {
  const QueueUndoToast({
    required this.controller,
    super.key,
  });

  final QueueUndoToastController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        return AnimatedSwitcher(
          duration: AppMotion.resolveDuration(
            AppMotionPreset.slideUp,
            reducedMotion: MediaQuery.disableAnimationsOf(context),
          ),
          switchInCurve: AppMotion.outCurve,
          switchOutCurve: AppMotion.inCurve,
          child: state == null
              ? const SizedBox.shrink(key: ValueKey('queue-undo-empty'))
              : Align(
                  key: const ValueKey('queue-undo-visible'),
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.space6),
                    child: _UndoToastBody(
                      message: state.message,
                      onUndo: () async {
                        await state.onUndo();
                        controller.dismiss();
                      },
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _UndoToastBody extends StatelessWidget {
  const _UndoToastBody({
    required this.message,
    required this.onUndo,
  });

  final String message;
  final Future<void> Function() onUndo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      liveRegion: true,
      child: Material(
        elevation: 8,
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colors.borderDefault),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.space4,
              AppSpacing.space3,
              AppSpacing.space3,
              AppSpacing.space3,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: AppTypography.bodySm(context).copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: AppSpacing.space3),
                AppButton(
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.sm,
                  onPressed: onUndo,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.undo,
                        size: 16,
                        color: colors.textPrimary,
                      ),
                      const SizedBox(width: AppSpacing.space1),
                      const Text('Undo'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
