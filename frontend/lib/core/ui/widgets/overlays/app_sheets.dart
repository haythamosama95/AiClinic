import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../theme/theme.dart';

/// Sheet edge placement.
enum AppSheetSide { left, right, top, bottom }

/// Application sheet helpers wrapping [showFSheet] and [showFPersistentSheet].
abstract final class AppSheets {
  /// Shows a modal sheet sliding in from [side].
  static Future<T?> showModal<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    AppSheetSide side = AppSheetSide.bottom,
    bool barrierDismissible = true,
    bool useRootNavigator = false,
    double? width,
    BoxConstraints? constraints,
  }) {
    final resolvedConstraints =
        constraints ?? (width == null ? const BoxConstraints() : BoxConstraints.tightFor(width: width));

    return showFSheet<T>(
      context: context,
      mainAxisMaxRatio: width == null && constraints == null ? 9 / 16 : null,
      constraints: resolvedConstraints,
      builder: (context) {
        final colors = context.semanticColors;
        final radius = Radius.circular(context.shapeTokens.xl);
        final (borderRadius, border) = switch (side) {
          AppSheetSide.bottom => (BorderRadius.vertical(top: radius), Border(top: BorderSide(color: colors.border))),
          AppSheetSide.top => (BorderRadius.vertical(bottom: radius), Border(bottom: BorderSide(color: colors.border))),
          AppSheetSide.left => (
            BorderRadius.horizontal(right: radius),
            Border(right: BorderSide(color: colors.border)),
          ),
          AppSheetSide.right => (BorderRadius.horizontal(left: radius), Border(left: BorderSide(color: colors.border))),
        };

        return DecoratedBox(
          decoration: BoxDecoration(color: colors.popover, borderRadius: borderRadius, border: border),
          child: ClipRRect(borderRadius: borderRadius, child: builder(context)),
        );
      },
      side: _mapSide(side),
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
    );
  }

  /// Shows a persistent sheet above the current scaffold.
  static FPersistentSheetController showPersistent({
    required BuildContext context,
    required Widget Function(BuildContext context, FPersistentSheetController controller) builder,
    AppSheetSide side = AppSheetSide.bottom,
  }) {
    return showFPersistentSheet(context: context, builder: builder, side: _mapSide(side));
  }

  static FLayout _mapSide(AppSheetSide side) => switch (side) {
    AppSheetSide.left => FLayout.ltr,
    AppSheetSide.right => FLayout.rtl,
    AppSheetSide.top => FLayout.ttb,
    AppSheetSide.bottom => FLayout.btt,
  };
}
