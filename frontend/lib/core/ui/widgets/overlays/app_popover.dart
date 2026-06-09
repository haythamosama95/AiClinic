import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Application popover wrapping [FPopover].
class AppPopover extends StatelessWidget {
  const AppPopover({required this.child, required this.content, this.controller, super.key});

  final Widget child;
  final Widget content;
  final FPopoverController? controller;

  @override
  Widget build(BuildContext context) {
    return FPopover(
      control: controller == null ? const FPopoverControl.managed() : FPopoverControl.managed(controller: controller),
      popoverBuilder: (_, _) => content,
      child: child,
    );
  }
}

/// Menu item for [AppPopoverMenu].
class AppPopoverMenuItem {
  const AppPopoverMenuItem({required this.label, this.onPressed, this.icon, this.destructive = false});

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool destructive;
}

/// Application popover menu wrapping [FPopoverMenu].
class AppPopoverMenu extends StatelessWidget {
  const AppPopoverMenu({required this.child, required this.items, this.controller, super.key});

  final Widget child;
  final List<AppPopoverMenuItem> items;
  final FPopoverController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final popoverItemGroupStyle = context.theme.popoverMenuStyle.itemGroupStyle;

    return FPopoverMenu(
      control: controller == null ? const FPopoverControl.managed() : FPopoverControl.managed(controller: controller),
      menuBuilder: (context, popoverController, _) => [
        FItemGroup(
          style: popoverItemGroupStyle,
          children: [
            for (final item in items)
              FItem(
                variant: item.destructive ? FItemVariant.destructive : FItemVariant.primary,
                prefix: item.icon,
                title: Text(item.label, style: theme.textTheme.bodyMedium),
                // forui only enables hover/press feedback when onPress is non-null.
                onPress: () {
                  item.onPressed?.call();
                  popoverController.hide();
                },
              ),
          ],
        ),
      ],
      builder: (context, popoverController, child) => FTappable(
        onPress: popoverController.toggle,
        child: IgnorePointer(child: child),
      ),
      child: child,
    );
  }
}
