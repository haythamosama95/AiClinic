import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shell density scale matching web `data-density` tokens.
enum AppDensity { compact, default_, comfortable }

extension AppDensityX on AppDensity {
  String get label => switch (this) {
    AppDensity.compact => 'Compact',
    AppDensity.default_ => 'Default',
    AppDensity.comfortable => 'Comfortable',
  };

  double get shellTopbarHeight => switch (this) {
    AppDensity.compact => 48,
    AppDensity.default_ => 56,
    AppDensity.comfortable => 64,
  };

  double get shellNavItemHeight => switch (this) {
    AppDensity.compact => 32,
    AppDensity.default_ => 36,
    AppDensity.comfortable => 40,
  };
}

class AppDensityNotifier extends Notifier<AppDensity> {
  @override
  AppDensity build() => AppDensity.default_;

  void setDensity(AppDensity density) => state = density;

  void cycle() {
    state = switch (state) {
      AppDensity.compact => AppDensity.default_,
      AppDensity.default_ => AppDensity.comfortable,
      AppDensity.comfortable => AppDensity.compact,
    };
  }
}

final appDensityProvider = NotifierProvider<AppDensityNotifier, AppDensity>(
  AppDensityNotifier.new,
);
