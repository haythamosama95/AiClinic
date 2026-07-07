import 'package:flutter/material.dart';

import 'package:ai_clinic/features/design_system/presentation/components/actions/button_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/actions/icon_button_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/actions/segmented_control_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/actions/split_button_showcase_section.dart';
// Inputs & forms
import 'package:ai_clinic/features/design_system/presentation/components/inputs/choice_controls_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/combobox_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/date_time_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/file_dropzone_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/form_field_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/money_field_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/multi_select_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/number_input_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/password_input_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/phone_input_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/search_input_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/select_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/slider_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/text_input_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/textarea_showcase_section.dart';
// Data display
import 'package:ai_clinic/features/design_system/presentation/components/display/avatar_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/badge_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/card_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/chart_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/chip_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/code_block_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/data_table_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/description_list_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/divider_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/entity_cards_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/kbd_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/list_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/timeline_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/calendar_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/metric_card_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/money_display_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/progress_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/resizable_panels_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/scroll_area_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/skeleton_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/display/tooltip_showcase_section.dart';
// Navigation
import 'package:ai_clinic/features/design_system/presentation/components/navigation/breadcrumb_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/navigation/menu_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/navigation/pagination_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/navigation/stepper_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/navigation/tabs_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/navigation/branch_switcher_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/navigation/command_bar_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/navigation/sidebar_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/navigation/top_bar_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/navigation/user_menu_showcase_section.dart';
// Feedback & overlays
import 'package:ai_clinic/features/design_system/presentation/components/feedback/alert_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/feedback/empty_state_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/feedback/error_state_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/feedback/loading_overlay_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/feedback/popover_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/feedback/dialog_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/feedback/drawer_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/feedback/toast_showcase_section.dart';
// AI
import 'package:ai_clinic/features/design_system/presentation/components/ai/ai_mode_toggle_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/ai/thinking_indicator_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/ai/ai_suggestion_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/ai/ai_message_bubble_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/ai/ai_panel_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/ai/proposed_action_card_showcase_section.dart';
// Layout & utility
import 'package:ai_clinic/features/design_system/presentation/components/layout/app_shell_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/layout/bulk_action_bar_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/layout/page_header_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/layout/resizable_panels_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/layout/scroll_area_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/layout/section_header_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/layout/toolbar_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/component_registry.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';

typedef ComponentSectionBuilder = Widget Function();

/// Maps ready section ids to their showcase builders.
final Map<String, ComponentSectionBuilder> componentSectionBuilders = {
  'button': () => const ButtonShowcaseSection(),
  'icon-button': () => const IconButtonShowcaseSection(),
  'split-button': () => const SplitButtonShowcaseSection(),
  'segmented-control': () => const SegmentedControlShowcaseSection(),
  'form-field': () => const FormFieldShowcaseSection(),
  'text-input': () => const TextInputShowcaseSection(),
  'textarea': () => const TextareaShowcaseSection(),
  'search-input': () => const SearchInputShowcaseSection(),
  'password-input': () => const PasswordInputShowcaseSection(),
  'number-input': () => const NumberInputShowcaseSection(),
  'money-field': () => const MoneyFieldShowcaseSection(),
  'phone-input': () => const PhoneInputShowcaseSection(),
  'select': () => const SelectShowcaseSection(),
  'combobox': () => const ComboboxShowcaseSection(),
  'multi-select': () => const MultiSelectShowcaseSection(),
  'checkbox': () => const CheckboxShowcaseSection(),
  'radio-group': () => const RadioGroupShowcaseSection(),
  'switch': () => const SwitchShowcaseSection(),
  'date-picker': () => const DatePickerShowcaseSection(),
  'time-picker': () => const TimePickerShowcaseSection(),
  'date-range-picker': () => const DateRangePickerShowcaseSection(),
  'file-dropzone': () => const FileDropzoneShowcaseSection(),
  'slider': () => const SliderShowcaseSection(),
  // Data display
  'badge': () => const BadgeShowcaseSection(),
  'chip': () => const ChipShowcaseSection(),
  'avatar': () => const AvatarShowcaseSection(),
  'tooltip': () => const TooltipShowcaseSection(),
  'kbd': () => const KbdShowcaseSection(),
  'divider': () => const DividerShowcaseSection(),
  'money-display': () => const MoneyDisplayShowcaseSection(),
  'code-block': () => const CodeBlockShowcaseSection(),
  'description-list': () => const DescriptionListShowcaseSection(),
  'list': () => const ListShowcaseSection(),
  'skeleton': () => const SkeletonShowcaseSection(),
  'progress': () => const ProgressShowcaseSection(),
  'data-table': () => const DataTableShowcaseSection(),
  'timeline': () => const TimelineShowcaseSection(),
  'calendar': () => const CalendarShowcaseSection(),
  'chart': () => const ChartShowcaseSection(),
  'card': () => const CardShowcaseSection(),
  'metric-card': () => const MetricCardShowcaseSection(),
  'entity-cards': () => const EntityCardsShowcaseSection(),
  'scroll-area': () => const ScrollAreaShowcaseSection(),
  'resizable-panels': () => const ResizablePanelsShowcaseSection(),
  // Navigation (Phase 1)
  'breadcrumb': () => const BreadcrumbShowcaseSection(),
  'tabs': () => const TabsShowcaseSection(),
  'menu': () => const MenuShowcaseSection(),
  'pagination': () => const PaginationShowcaseSection(),
  'stepper': () => const StepperShowcaseSection(),
  // Navigation (Phase 2)
  'app-sidebar': () => const SidebarShowcaseSection(),
  'branch-switcher': () => const BranchSwitcherShowcaseSection(),
  'user-menu': () => const UserMenuShowcaseSection(),
  'command-bar': () => const CommandBarShowcaseSection(),
  'app-topbar': () => const TopBarShowcaseSection(),
  // Layout & utility (Phase 1)
  'page-header': () => const PageHeaderShowcaseSection(),
  'section-header': () => const SectionHeaderShowcaseSection(),
  'toolbar': () => const ToolbarShowcaseSection(),
  'bulk-action-bar': () => const BulkActionBarShowcaseSection(),
  // Layout & utility (Phase 2)
  'app-shell': () => const AppShellShowcaseSection(),
  'layout-scroll-area': () => const LayoutScrollAreaShowcaseSection(),
  'layout-resizable': () => const ResizablePanelsLayoutShowcaseSection(),
  // Feedback & overlays
  'toast': () => const ToastShowcaseSection(),
  'alert': () => const AlertShowcaseSection(),
  'loading-overlay': () => const LoadingOverlayShowcaseSection(),
  'empty-state': () => const EmptyStateShowcaseSection(),
  'error-state': () => const ErrorStateShowcaseSection(),
  'popover': () => const PopoverShowcaseSection(),
  'dialog': () => const DialogShowcaseSection(),
  'drawer': () => const DrawerShowcaseSection(),
  // AI (Phase 1)
  'ai-mode-toggle': () => const AiModeToggleShowcaseSection(),
  'thinking-indicator': () => const ThinkingIndicatorShowcaseSection(),
  'ai-suggestion': () => const AiSuggestionShowcaseSection(),
  'ai-message-bubble': () => const AiMessageBubbleShowcaseSection(),
  // AI (Phase 2)
  'ai-panel': () => const AiPanelShowcaseSection(),
  'proposed-action-card': () => const ProposedActionCardShowcaseSection(),
};

/// Builds a section widget from registry metadata.
Widget buildComponentSection(ShowcaseSectionDef section) {
  if (section.status == ShowcaseSectionStatus.ready) {
    final builder = componentSectionBuilders[section.id];
    if (builder != null) return builder();
  }

  return ShowcaseSection(
    id: section.id,
    title: section.title,
    description: section.description,
    child: PlaceholderSection(title: section.title, message: 'To be implemented later'),
  );
}
