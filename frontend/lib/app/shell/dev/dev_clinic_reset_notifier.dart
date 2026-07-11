import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class DevClinicResetState {
  const DevClinicResetState({this.inProgress = false});

  final bool inProgress;

  DevClinicResetState copyWith({bool? inProgress}) {
    return DevClinicResetState(inProgress: inProgress ?? this.inProgress);
  }
}

final devClinicResetProvider = NotifierProvider<DevClinicResetNotifier, DevClinicResetState>(
  DevClinicResetNotifier.new,
);

class DevClinicResetNotifier extends Notifier<DevClinicResetState> {
  @override
  DevClinicResetState build() => const DevClinicResetState();

  void setInProgress(bool inProgress) {
    state = state.copyWith(inProgress: inProgress);
  }
}
