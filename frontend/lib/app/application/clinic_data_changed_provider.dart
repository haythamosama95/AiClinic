import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A monotonically-increasing signal bumped whenever clinic-wide data changes
/// (organization, branches, staff, services) in a way that other features'
/// cached state should refresh.
///
/// This decouples the setup feature from the appointments feature: instead of
/// the setup notifier calling `invalidateAppointmentSurfaceProviders(_ref)`
/// directly (a cross-feature layering violation, review §6.2), it bumps this
/// signal, and features that care listen and invalidate themselves.
final clinicDataChangedProvider = NotifierProvider<ClinicDataChangedNotifier, int>(ClinicDataChangedNotifier.new);

class ClinicDataChangedNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Bump the signal so listeners re-evaluate cached clinic-derived state.
  void bump() => state++;
}
