/// Component showcase group identifiers (web `ShowcaseGroupId`).
enum ShowcaseGroupId { actions, inputs, display, navigation, feedback, ai, layout }

/// Whether a showcase section is implemented or placeholder.
enum ShowcaseSectionStatus { ready, placeholder }

/// Metadata for a single component showcase section.
class ShowcaseSectionDef {
  const ShowcaseSectionDef({
    required this.id,
    required this.title,
    required this.group,
    required this.status,
    this.description,
  });

  final String id;
  final String title;
  final ShowcaseGroupId group;
  final ShowcaseSectionStatus status;
  final String? description;
}

/// Metadata for a component group in the showcase nav.
class ShowcaseGroupDef {
  const ShowcaseGroupDef({required this.id, required this.title, required this.description});

  final ShowcaseGroupId id;
  final String title;
  final String description;
}

/// Showcase groups matching web `showcaseGroups`.
const showcaseGroups = <ShowcaseGroupDef>[
  ShowcaseGroupDef(
    id: ShowcaseGroupId.actions,
    title: 'Actions',
    description: 'Buttons, icon buttons, split buttons, and segmented controls.',
  ),
  ShowcaseGroupDef(
    id: ShowcaseGroupId.inputs,
    title: 'Inputs & forms',
    description: 'Form fields, text inputs, pickers, and validation states.',
  ),
  ShowcaseGroupDef(
    id: ShowcaseGroupId.display,
    title: 'Data display',
    description: 'Badges, chips, avatars, progress, and read-only primitives.',
  ),
  ShowcaseGroupDef(
    id: ShowcaseGroupId.navigation,
    title: 'Navigation',
    description: 'Sidebar, tabs, menus, Command Bar, and wayfinding.',
  ),
  ShowcaseGroupDef(
    id: ShowcaseGroupId.feedback,
    title: 'Feedback & overlays',
    description: 'Toasts, dialogs, drawers, and empty states.',
  ),
  ShowcaseGroupDef(
    id: ShowcaseGroupId.ai,
    title: 'AI',
    description: 'AI mode, panels, proposed actions, and thinking indicators.',
  ),
  ShowcaseGroupDef(
    id: ShowcaseGroupId.layout,
    title: 'Layout & utility',
    description: 'Headers, toolbars, scroll areas, and shell composition.',
  ),
];

/// All component sections. Actions, Inputs, and Data display are ready; other groups use placeholders.
const componentSections = <ShowcaseSectionDef>[
  // Actions (ready)
  ShowcaseSectionDef(
    id: 'button',
    title: 'Button',
    description: 'Primary, secondary, ghost, danger, AI, and link variants.',
    group: ShowcaseGroupId.actions,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'icon-button',
    title: 'Icon button',
    group: ShowcaseGroupId.actions,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'split-button',
    title: 'Split button',
    group: ShowcaseGroupId.actions,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'segmented-control',
    title: 'Segmented control',
    group: ShowcaseGroupId.actions,
    status: ShowcaseSectionStatus.ready,
  ),

  // Inputs & forms (ready)
  ShowcaseSectionDef(
    id: 'form-field',
    title: 'Form field',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'text-input',
    title: 'Text input',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'textarea',
    title: 'Textarea',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'search-input',
    title: 'Search input',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'password-input',
    title: 'Password input',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'number-input',
    title: 'Number / stepper',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'money-field',
    title: 'Money field',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'phone-input',
    title: 'Phone input',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(id: 'select', title: 'Select', group: ShowcaseGroupId.inputs, status: ShowcaseSectionStatus.ready),
  ShowcaseSectionDef(
    id: 'combobox',
    title: 'Combobox / autocomplete',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'multi-select',
    title: 'Multi-select / token',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'checkbox',
    title: 'Checkbox',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'radio-group',
    title: 'Radio group',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(id: 'switch', title: 'Switch', group: ShowcaseGroupId.inputs, status: ShowcaseSectionStatus.ready),
  ShowcaseSectionDef(
    id: 'date-picker',
    title: 'Date picker',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'time-picker',
    title: 'Time picker',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'date-range-picker',
    title: 'Date range picker',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'file-dropzone',
    title: 'File dropzone',
    group: ShowcaseGroupId.inputs,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(id: 'slider', title: 'Slider', group: ShowcaseGroupId.inputs, status: ShowcaseSectionStatus.ready),

  // Data display (ready)
  ShowcaseSectionDef(
    id: 'badge',
    title: 'Badge / Status pill',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'chip',
    title: 'Chip / Tag',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'avatar',
    title: 'Avatar / Group',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'tooltip',
    title: 'Tooltip',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(id: 'kbd', title: 'Kbd', group: ShowcaseGroupId.display, status: ShowcaseSectionStatus.ready),
  ShowcaseSectionDef(
    id: 'divider',
    title: 'Divider',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'skeleton',
    title: 'Skeleton',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'progress',
    title: 'Progress',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'data-table',
    title: 'Table / Data grid',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(id: 'card', title: 'Card', group: ShowcaseGroupId.display, status: ShowcaseSectionStatus.ready),
  ShowcaseSectionDef(
    id: 'metric-card',
    title: 'Metric card',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'entity-cards',
    title: 'Entity cards',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(id: 'list', title: 'List', group: ShowcaseGroupId.display, status: ShowcaseSectionStatus.ready),
  ShowcaseSectionDef(
    id: 'description-list',
    title: 'Description list',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'timeline',
    title: 'Timeline',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'calendar',
    title: 'Calendar',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'chart',
    title: 'Chart primitives',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'money-display',
    title: 'Money display',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'code-block',
    title: 'Code block',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'scroll-area',
    title: 'Scroll area',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'resizable-panels',
    title: 'Resizable panels',
    group: ShowcaseGroupId.display,
    status: ShowcaseSectionStatus.ready,
  ),

  // Navigation (Phase 1 ready; Phase 2 placeholder)
  ShowcaseSectionDef(
    id: 'breadcrumb',
    title: 'Breadcrumb',
    group: ShowcaseGroupId.navigation,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(id: 'tabs', title: 'Tabs', group: ShowcaseGroupId.navigation, status: ShowcaseSectionStatus.ready),
  ShowcaseSectionDef(id: 'menu', title: 'Menu', group: ShowcaseGroupId.navigation, status: ShowcaseSectionStatus.ready),
  ShowcaseSectionDef(
    id: 'pagination',
    title: 'Pagination',
    group: ShowcaseGroupId.navigation,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'stepper',
    title: 'Stepper',
    group: ShowcaseGroupId.navigation,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'app-sidebar',
    title: 'App sidebar',
    group: ShowcaseGroupId.navigation,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'app-topbar',
    title: 'App top bar',
    group: ShowcaseGroupId.navigation,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'command-bar',
    title: 'Command bar',
    group: ShowcaseGroupId.navigation,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'branch-switcher',
    title: 'Branch switcher',
    group: ShowcaseGroupId.navigation,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'user-menu',
    title: 'User menu',
    group: ShowcaseGroupId.navigation,
    status: ShowcaseSectionStatus.ready,
  ),

  // Feedback & overlays (placeholder)
  ShowcaseSectionDef(
    id: 'toast',
    title: 'Toast',
    group: ShowcaseGroupId.feedback,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'alert',
    title: 'Inline alert',
    group: ShowcaseGroupId.feedback,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'dialog',
    title: 'Dialog',
    group: ShowcaseGroupId.feedback,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'drawer',
    title: 'Drawer / sheet',
    group: ShowcaseGroupId.feedback,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'popover',
    title: 'Popover',
    group: ShowcaseGroupId.feedback,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'loading-overlay',
    title: 'Loading overlay',
    group: ShowcaseGroupId.feedback,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'empty-state',
    title: 'Empty states',
    group: ShowcaseGroupId.feedback,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'error-state',
    title: 'Error state',
    group: ShowcaseGroupId.feedback,
    status: ShowcaseSectionStatus.placeholder,
  ),

  // AI (placeholder)
  ShowcaseSectionDef(
    id: 'ai-mode-toggle',
    title: 'AI mode toggle',
    group: ShowcaseGroupId.ai,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'ai-panel',
    title: 'AI panel / chat',
    group: ShowcaseGroupId.ai,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'ai-message-bubble',
    title: 'AI message bubbles',
    group: ShowcaseGroupId.ai,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'proposed-action-card',
    title: 'Proposed action card',
    group: ShowcaseGroupId.ai,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'ai-suggestion',
    title: 'Inline AI suggestion',
    group: ShowcaseGroupId.ai,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'thinking-indicator',
    title: 'Thinking indicator',
    group: ShowcaseGroupId.ai,
    status: ShowcaseSectionStatus.placeholder,
  ),

  // Layout & utility (placeholder)
  ShowcaseSectionDef(
    id: 'app-shell',
    title: 'App shell',
    group: ShowcaseGroupId.layout,
    status: ShowcaseSectionStatus.ready,
  ),
  ShowcaseSectionDef(
    id: 'page-header',
    title: 'Page header',
    group: ShowcaseGroupId.layout,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'section-header',
    title: 'Section header',
    group: ShowcaseGroupId.layout,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'toolbar',
    title: 'Toolbar / filter bar',
    group: ShowcaseGroupId.layout,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'bulk-action-bar',
    title: 'Bulk action bar',
    group: ShowcaseGroupId.layout,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'layout-scroll-area',
    title: 'Scroll area',
    group: ShowcaseGroupId.layout,
    status: ShowcaseSectionStatus.placeholder,
  ),
  ShowcaseSectionDef(
    id: 'layout-resizable',
    title: 'Resizable panels',
    group: ShowcaseGroupId.layout,
    status: ShowcaseSectionStatus.placeholder,
  ),
];

/// Group id string used for scroll anchors (`group-actions`, etc.).
String showcaseGroupSectionId(ShowcaseGroupId group) => 'group-${group.name}';

/// Sections grouped by showcase group.
Map<ShowcaseGroupId, List<ShowcaseSectionDef>> get groupedComponentSections {
  return {
    for (final group in showcaseGroups)
      group.id: componentSections.where((section) => section.group == group.id).toList(),
  };
}
