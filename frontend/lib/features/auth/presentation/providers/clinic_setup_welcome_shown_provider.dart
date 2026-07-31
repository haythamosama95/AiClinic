import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the first-run clinic setup welcome dialog was shown for a staff member.
///
/// Keyed by [staffMemberId] so switching users resets shown-state without relying on
/// a library-level global or which widget tree constructed [ClinicSetupWelcomeScope].
final clinicSetupWelcomeShownProvider = NotifierProvider.autoDispose
    .family<ClinicSetupWelcomeShownNotifier, bool, String>(ClinicSetupWelcomeShownNotifier.new);

class ClinicSetupWelcomeShownNotifier extends Notifier<bool> {
  ClinicSetupWelcomeShownNotifier(String _);

  @override
  bool build() => false;

  /// Marks the welcome dialog as shown. Returns `false` if it was already shown.
  bool tryMarkShown() {
    if (state) {
      return false;
    }
    state = true;
    return true;
  }
}
