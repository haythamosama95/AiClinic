import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

final _menuEntries = <MenuEntry>[
  MenuSectionEntry(
    MenuSection(
      label: 'Patient',
      items: [
        MenuItemDef(
          id: 'edit',
          label: 'Edit profile',
          icon: Icon(Icons.edit_outlined, size: 16),
          shortcut: const ['⌘', 'E'],
        ),
        MenuItemDef(
          id: 'copy',
          label: 'Copy MRN',
          icon: Icon(Icons.copy_outlined, size: 16),
        ),
      ],
    ),
  ),
  MenuSeparatorEntry(),
  MenuItemEntry(
    MenuItemDef(
      id: 'delete',
      label: 'Delete record',
      icon: Icon(Icons.delete_outline, size: 16),
      destructive: true,
    ),
  ),
];

class MenuShowcase extends StatelessWidget {
  const MenuShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return ShowcaseSection(
      title: 'Menu / Context menu',
      description:
          'Dropdown and right-click menus with icons, shortcuts, and destructive items.',
      child: ShowcaseDemoGrid(
        children: [
          ShowcaseDemo(
            label: 'Dropdown menu',
            child: AppMenu(
              trigger: AppButton(
                onPressed: () {},
                variant: AppButtonVariant.secondary,
                child: const Text('Open menu'),
              ),
              entries: _menuEntries,
            ),
          ),
          ShowcaseDemo(
            label: 'Context menu',
            child: AppContextMenu(
              entries: _menuEntries,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                    color: colors.borderDefault,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: AppSpacing.s6,
                  ),
                  child: Text(
                    'Right-click here',
                    style: typography.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
