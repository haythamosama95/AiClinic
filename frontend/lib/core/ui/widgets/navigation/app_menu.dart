import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/navigation/app_dropdown_menu.dart';
import 'package:ai_clinic/core/ui/widgets/overlays/app_popover.dart';

/// Minimum width for [AppMenu] panels (`12rem`).
const double kAppMenuMinWidth = AppSpacing.s12 * 4;

/// One selectable action inside a menu.
class AppMenuItem {
  const AppMenuItem({
    required this.id,
    required this.label,
    this.leading,
    this.shortcutKeys,
    this.checked = false,
    this.destructive = false,
    this.disabled = false,
    this.disabledReason,
    this.onSelected,
  });

  final String id;
  final String label;
  final IconData? leading;
  final List<String>? shortcutKeys;
  final bool checked;
  final bool destructive;
  final bool disabled;
  final String? disabledReason;
  final VoidCallback? onSelected;
}

/// Horizontal rule between menu groups.
class AppMenuSeparator {
  const AppMenuSeparator();
}

/// Grouped menu items with an optional overline label.
class AppMenuSection {
  const AppMenuSection({
    required this.items,
    this.label,
  });

  final String? label;
  final List<AppMenuItem> items;
}

/// Discriminated menu content entry.
sealed class AppMenuEntry {
  const AppMenuEntry();
}

/// A single [AppMenuItem] row.
final class AppMenuItemEntry extends AppMenuEntry {
  const AppMenuItemEntry(this.item);

  final AppMenuItem item;
}

/// A labeled section of [AppMenuItem] rows.
final class AppMenuSectionEntry extends AppMenuEntry {
  const AppMenuSectionEntry({
    required this.items,
    this.label,
  });

  final String? label;
  final List<AppMenuItem> items;
}

/// A separator between menu groups.
final class AppMenuSeparatorEntry extends AppMenuEntry {
  const AppMenuSeparatorEntry();
}

/// Logical alignment of [AppMenu] relative to its trigger.
enum AppMenuAlign {
  start,
  center,
  end,
}

AppDropdownMenuAlign _toDropdownAlign(AppMenuAlign align) {
  return switch (align) {
    AppMenuAlign.start => AppDropdownMenuAlign.start,
    AppMenuAlign.center => AppDropdownMenuAlign.center,
    AppMenuAlign.end => AppDropdownMenuAlign.end,
  };
}

/// Dropdown action list anchored to a custom trigger.
class AppMenu extends StatefulWidget {
  const AppMenu({
    required this.trigger,
    required this.entries,
    this.controller,
    this.align = AppMenuAlign.start,
    this.onOpenChange,
    super.key,
  });

  final Widget Function(
    BuildContext context,
    VoidCallback show,
    VoidCallback hide,
    VoidCallback toggle,
  ) trigger;
  final List<AppMenuEntry> entries;
  final AppPopoverController? controller;
  final AppMenuAlign align;
  final ValueChanged<bool>? onOpenChange;

  @override
  State<AppMenu> createState() => _AppMenuState();
}

class _AppMenuState extends State<AppMenu> {
  late AppPopoverController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? AppPopoverController();
  }

  @override
  void didUpdateWidget(covariant AppMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      if (_ownsController) {
        _controller.dispose();
      }
      _ownsController = widget.controller == null;
      _controller = widget.controller ?? AppPopoverController();
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDropdownMenu(
      controller: _controller,
      align: _toDropdownAlign(widget.align),
      minWidth: kAppMenuMinWidth,
      onOpenChange: widget.onOpenChange,
      trigger: widget.trigger,
      children: buildAppMenuEntryWidgets(widget.entries),
    );
  }
}

/// Builds dropdown menu child widgets from [AppMenuEntry] values.
List<Widget> buildAppMenuEntryWidgets(List<AppMenuEntry> entries) {
  final widgets = <Widget>[];
  var order = 0;

  for (final entry in entries) {
    switch (entry) {
      case AppMenuSeparatorEntry():
        widgets.add(const AppDropdownMenuSeparator());
      case AppMenuSectionEntry(:final label, :final items):
        if (label != null) {
          widgets.add(AppDropdownMenuLabel(label: label));
        }
        for (final item in items) {
          widgets.add(_menuItemWidget(item, order++));
        }
      case AppMenuItemEntry(:final item):
        widgets.add(_menuItemWidget(item, order++));
    }
  }

  return widgets;
}

Widget _menuItemWidget(AppMenuItem item, int order) {
  return AppDropdownMenuItem(
    key: ValueKey<String>(item.id),
    label: item.label,
    leading: item.leading,
    shortcutKeys: item.shortcutKeys,
    checked: item.checked,
    destructive: item.destructive,
    disabled: item.disabled,
    disabledReason: item.disabledReason,
    order: order,
    onSelected: item.onSelected,
  );
}

/// Right-click and long-press context menu wrapper.
class AppContextMenu extends StatelessWidget {
  const AppContextMenu({
    required this.child,
    required this.entries,
    this.align = AppMenuAlign.start,
    super.key,
  });

  final Widget child;
  final List<AppMenuEntry> entries;
  final AppMenuAlign align;

  void _openAt(BuildContext context, Offset globalPosition) {
    showAppContextMenu(
      context: context,
      globalPosition: globalPosition,
      entries: entries,
      align: align,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapDown: (details) => _openAt(context, details.globalPosition),
      onLongPressStart: (details) => _openAt(context, details.globalPosition),
      child: child,
    );
  }
}

/// Opens an [AppMenu] panel anchored at [globalPosition].
Future<void> showAppContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required List<AppMenuEntry> entries,
  AppMenuAlign align = AppMenuAlign.start,
}) {
  final overlayState = Overlay.of(context, rootOverlay: true);
  final anchorLink = LayerLink();
  final anchorKey = GlobalKey();
  late OverlayEntry anchorEntry;

  anchorEntry = OverlayEntry(
    builder: (overlayContext) {
      final overlayBox =
          Overlay.of(overlayContext).context.findRenderObject() as RenderBox;
      final local = overlayBox.globalToLocal(globalPosition);
      return Positioned(
        left: local.dx,
        top: local.dy,
        child: CompositedTransformTarget(
          key: anchorKey,
          link: anchorLink,
          child: const SizedBox(width: 1, height: 1),
        ),
      );
    },
  );

  overlayState.insert(anchorEntry);

  return showAppPopover(
    context: context,
    anchorLink: anchorLink,
    anchorKey: anchorKey,
    placement: appDropdownMenuAlignToPlacement(_toDropdownAlign(align)),
    builder: (_, dismiss) => AppDropdownMenuContent(
      minWidth: kAppMenuMinWidth,
      onClose: dismiss,
      children: buildAppMenuEntryWidgets(entries),
    ),
  ).whenComplete(anchorEntry.remove);
}
