import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_filter_popover.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

/// Syncfusion calendar default header row height.
const appointmentCalendarHeaderRowHeight = 40.0;

/// Total custom header height (single navigation row).
const appointmentCalendarHeaderHeight = appointmentCalendarHeaderRowHeight;

const _viewTabFontSize = 12.0;
const _viewTabPadding = 10.0;
const _maxArrowButtonWidth = 40.0;

/// Custom calendar header styled like [SfCalendar]'s built-in header.
class AppointmentCalendarHeaderBar extends ConsumerWidget {
  const AppointmentCalendarHeaderBar({
    required this.branchesAsync,
    required this.doctorsAsync,
    required this.selectedBranchId,
    required this.selectedDoctorId,
    required this.showDoctorFilter,
    required this.onBranchChanged,
    required this.onDoctorChanged,
    super.key,
  });

  final AsyncValue<List<BranchListItem>> branchesAsync;
  final AsyncValue<List<StaffListItem>> doctorsAsync;
  final String? selectedBranchId;
  final String? selectedDoctorId;
  final bool showDoctorFilter;
  final ValueChanged<String?> onBranchChanged;
  final ValueChanged<String?> onDoctorChanged;

  static const _modes = <AppointmentCalendarMode>[
    AppointmentCalendarMode.day,
    AppointmentCalendarMode.week,
    AppointmentCalendarMode.month,
    AppointmentCalendarMode.schedule,
    AppointmentCalendarMode.doctors,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.semanticColors;
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(appointmentCalendarProvider);
    final controller = ref.read(appointmentCalendarProvider.notifier);

    final headerBackgroundColor = colors.card;
    final headerTextStyle = textTheme.titleMedium?.copyWith(color: colors.foreground);
    final headerTextColor = headerTextStyle?.color ?? colors.foreground;
    final arrowColor = headerTextColor.withValues(alpha: headerTextColor.a * 0.6);
    final highlightColor = colors.primary;
    final tabBorderColor = colors.border;

    final showNavigation = state.mode != AppointmentCalendarMode.schedule;
    final arrowSize = (appointmentCalendarHeaderRowHeight * 0.6).clamp(0.0, 25.0);
    final title = AppointmentCalendarDisplay.headerTitle(state.mode, state.focusDate);

    return ColoredBox(
      color: headerBackgroundColor,
      child: SizedBox(
        height: appointmentCalendarHeaderRowHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final iconWidth = (constraints.maxWidth / 8).clamp(0.0, _maxArrowButtonWidth);

            return Row(
              children: [
                if (showNavigation) ...[
                  _HeaderIconButton(
                    width: iconWidth,
                    height: appointmentCalendarHeaderRowHeight,
                    backgroundColor: headerBackgroundColor,
                    onTap: () => controller.previousPeriod(),
                    child: Icon(Icons.chevron_left, color: arrowColor, size: arrowSize),
                  ),
                  _HeaderIconButton(
                    width: iconWidth,
                    height: appointmentCalendarHeaderRowHeight,
                    backgroundColor: headerBackgroundColor,
                    onTap: () => controller.nextPeriod(),
                    child: Icon(Icons.chevron_right, color: arrowColor, size: arrowSize),
                  ),
                ],
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
                    child: Text(
                      title,
                      style: headerTextStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                    ),
                  ),
                ),
                _HeaderTextButton(
                  label: 'Today',
                  height: appointmentCalendarHeaderRowHeight,
                  textColor: headerTextColor,
                  borderColor: tabBorderColor,
                  onTap: () => controller.goToToday(),
                ),
                const SizedBox(width: SpacingTokens.sm),
                const SizedBox(
                  height: appointmentCalendarHeaderRowHeight,
                  child: VerticalDivider(width: 0.5, thickness: 0.5, color: Colors.grey),
                ),
                const SizedBox(width: SpacingTokens.xs),
                AppointmentCalendarFilterButton(
                  branchesAsync: branchesAsync,
                  doctorsAsync: doctorsAsync,
                  selectedBranchId: selectedBranchId,
                  selectedDoctorId: selectedDoctorId,
                  showDoctorFilter: showDoctorFilter,
                  onBranchChanged: onBranchChanged,
                  onDoctorChanged: onDoctorChanged,
                ),
                const SizedBox(width: SpacingTokens.xs),
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < _modes.length; i++) ...[
                          if (i > 0) const SizedBox(width: SpacingTokens.xs),
                          _ViewTab(
                            label: _viewLabel(_modes[i]),
                            selected: state.mode == _modes[i],
                            highlightColor: highlightColor,
                            borderColor: tabBorderColor,
                            onTap: () => controller.setMode(_modes[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _viewLabel(AppointmentCalendarMode mode) {
    return switch (mode) {
      AppointmentCalendarMode.day => 'Day',
      AppointmentCalendarMode.week => 'Week',
      AppointmentCalendarMode.month => 'Month',
      AppointmentCalendarMode.schedule => 'Schedule',
      AppointmentCalendarMode.doctors => 'Timeline Day',
    };
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.width,
    required this.height,
    required this.backgroundColor,
    required this.onTap,
    required this.child,
  });

  final double width;
  final double height;
  final Color backgroundColor;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: backgroundColor,
        child: InkWell(
          onTap: onTap,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _HeaderTextButton extends StatelessWidget {
  const _HeaderTextButton({
    required this.label,
    required this.height,
    required this.textColor,
    required this.borderColor,
    required this.onTap,
  });

  final String label;
  final double height;
  final Color textColor;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: height * 0.8,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: _viewTabPadding),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(color: textColor, fontSize: _viewTabFontSize),
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}

class _ViewTab extends StatelessWidget {
  const _ViewTab({
    required this.label,
    required this.selected,
    required this.highlightColor,
    required this.borderColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color highlightColor;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = selected ? highlightColor : borderColor;
    final textColor = selected ? highlightColor : Theme.of(context).textTheme.titleMedium?.color;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: appointmentCalendarHeaderRowHeight * 0.8,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: _viewTabPadding),
          decoration: BoxDecoration(
            border: Border.all(color: activeColor),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(color: textColor, fontSize: _viewTabFontSize),
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}
