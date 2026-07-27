import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_fullscreen_overlay.dart';

/// Manages the calendar fullscreen overlay lifecycle.
class AppointmentCalendarFullscreenController {
  final GlobalKey calendarHostKey = GlobalKey();

  OverlayEntry? _fullscreenOverlay;
  bool isFullscreen = false;
  double? calendarHostHeight;
  Future<void> Function()? _closeFullscreenOverlay;

  bool get isOpen => isFullscreen;

  void toggle({
    required BuildContext context,
    required bool isCurrentlyFullscreen,
    required WidgetBuilder calendarBuilder,
  }) {
    if (isCurrentlyFullscreen) {
      unawaited(_closeFullscreenOverlay?.call());
      return;
    }
    open(context: context, calendarBuilder: calendarBuilder);
  }

  void open({required BuildContext context, required WidgetBuilder calendarBuilder}) {
    if (isFullscreen) {
      return;
    }

    final hostContext = calendarHostKey.currentContext;
    final sourceRect = hostContext == null ? null : globalRectOnScreen(hostContext);
    if (sourceRect == null) {
      return;
    }

    final box = hostContext!.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      calendarHostHeight = box.size.height;
    }

    _fullscreenOverlay = OverlayEntry(
      builder: (overlayContext) {
        return AppointmentCalendarFullscreenOverlay(
          sourceRect: sourceRect,
          onClose: close,
          onReady: (close) => _closeFullscreenOverlay = close,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space4),
            child: calendarBuilder(overlayContext),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_fullscreenOverlay!);
    isFullscreen = true;
  }

  void close() {
    _closeFullscreenOverlay = null;
    _fullscreenOverlay?.remove();
    _fullscreenOverlay = null;
    isFullscreen = false;
  }

  void refreshOverlay() {
    _fullscreenOverlay?.markNeedsBuild();
  }

  void dispose() {
    _fullscreenOverlay?.remove();
    _fullscreenOverlay = null;
    isFullscreen = false;
  }
}
