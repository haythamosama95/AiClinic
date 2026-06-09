import 'package:forui/forui.dart';

/// Dense field sizing aligned with the application design tokens.
enum AppFieldSize { sm, md, lg }

/// Maps [AppFieldSize] to forui field size variants.
extension AppFieldSizeForui on AppFieldSize {
  FTextFieldSizeVariant get forui => switch (this) {
    AppFieldSize.sm => FTextFieldSizeVariant.sm,
    AppFieldSize.md => FTextFieldSizeVariant.md,
    AppFieldSize.lg => FTextFieldSizeVariant.lg,
  };
}

/// Maps [AppFieldSize] to forui button size variants.
extension AppFieldSizeButton on AppFieldSize {
  FButtonSizeVariant get buttonSize => switch (this) {
    AppFieldSize.sm => FButtonSizeVariant.sm,
    AppFieldSize.md => FButtonSizeVariant.md,
    AppFieldSize.lg => FButtonSizeVariant.lg,
  };

  FCircularProgressSizeVariant get progressSize => switch (this) {
    AppFieldSize.sm => FCircularProgressSizeVariant.sm,
    AppFieldSize.md => FCircularProgressSizeVariant.md,
    AppFieldSize.lg => FCircularProgressSizeVariant.lg,
  };
}
