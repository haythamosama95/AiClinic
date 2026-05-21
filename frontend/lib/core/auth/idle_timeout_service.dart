import 'dart:async';

import 'package:flutter/foundation.dart';

/// Default workstation idle sign-out (FR-005a).
const Duration kIdleTimeoutDuration = Duration(minutes: 15);

/// Shown on login after automatic idle sign-out.
const String kIdleTimeoutSignOutMessage = 'You were signed out due to inactivity. Sign in again to continue.';

/// Shown on login when the SDK ends the session (e.g. refresh failure).
const String kSessionEndedMessage = 'Your session has ended. Sign in again to continue.';

/// Tracks keyboard/pointer activity and signs out after [idleDuration] of inactivity.
///
/// Token refresh and other background auth events must not call [recordActivity].
class IdleTimeoutService {
  IdleTimeoutService({Duration? idleDuration, required this.onIdleTimeout})
    : _idleDuration = idleDuration ?? kIdleTimeoutDuration;

  Duration _idleDuration;
  final VoidCallback onIdleTimeout;

  Duration get idleDuration => _idleDuration;

  /// Applies a new idle deadline; reschedules the timer when monitoring is active.
  void updateIdleDuration(Duration duration) {
    _idleDuration = duration;
    if (_enabled) {
      _scheduleTimer();
    }
  }

  bool _enabled = false;
  Timer? _timer;

  bool get isEnabled => _enabled;

  /// Starts or restarts the idle timer when the user has an authenticated session.
  void enable({bool resetTimer = true}) {
    _enabled = true;
    if (resetTimer) {
      _scheduleTimer();
    }
  }

  /// Stops monitoring (explicit sign-out, unauthenticated, or after idle fires).
  void disable() {
    _enabled = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Resets the idle deadline after keyboard or pointer input (not background refresh).
  void recordActivity() {
    if (!_enabled) {
      return;
    }
    _scheduleTimer();
  }

  void _scheduleTimer() {
    _timer?.cancel();
    _timer = Timer(_idleDuration, _handleTimeout);
  }

  void _handleTimeout() {
    if (!_enabled) {
      return;
    }
    disable();
    onIdleTimeout();
  }

  void dispose() {
    disable();
  }
}
