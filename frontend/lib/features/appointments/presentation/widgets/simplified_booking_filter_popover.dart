import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

final _filterPopoverMotion = FPopoverStyleDelta.delta(
  motion: FPopoverMotionDelta.delta(
    entranceDuration: Duration(milliseconds: 200),
    exitDuration: Duration(milliseconds: 150),
    scaleTween: Tween<double>(begin: 0.96, end: 1),
    fadeTween: Tween<double>(begin: 0, end: 1),
  ),
);

/// Filter popover for simplified booking step two (doctor, date, slot display).
class SimplifiedBookingFilterButton extends StatefulWidget {
  const SimplifiedBookingFilterButton({
    required this.hideFullyBooked,
    required this.viewDoctorId,
    required this.defaultViewDoctorId,
    required this.selectedDate,
    required this.firstDate,
    required this.lastDate,
    required this.doctorItems,
    required this.onHideFullyBookedChanged,
    required this.onViewDoctorChanged,
    required this.onDateChanged,
    this.enabled = true,
    super.key,
  });

  final bool hideFullyBooked;
  final String viewDoctorId;
  final String defaultViewDoctorId;
  final DateTime selectedDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Map<String, String> doctorItems;
  final ValueChanged<bool> onHideFullyBookedChanged;
  final ValueChanged<String> onViewDoctorChanged;
  final ValueChanged<DateTime> onDateChanged;
  final bool enabled;

  bool get hasActiveFilters => !hideFullyBooked || viewDoctorId != defaultViewDoctorId;

  @override
  State<SimplifiedBookingFilterButton> createState() => _SimplifiedBookingFilterButtonState();
}

class _SimplifiedBookingFilterButtonState extends State<SimplifiedBookingFilterButton>
    with SingleTickerProviderStateMixin {
  late final FPopoverController _controller = FPopoverController(vsync: this);
  final _filterPopoverGroup = Object();
  var _isHovered = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyFilters({required bool hideFullyBooked, required String viewDoctorId, required DateTime selectedDate}) {
    if (hideFullyBooked != widget.hideFullyBooked) {
      widget.onHideFullyBookedChanged(hideFullyBooked);
    }
    if (viewDoctorId != widget.viewDoctorId) {
      widget.onViewDoctorChanged(viewDoctorId);
    }
    if (!_isSameDay(selectedDate, widget.selectedDate)) {
      widget.onDateChanged(selectedDate);
    }
    _controller.hide();
  }

  void _clearFilters() {
    _applyFilters(hideFullyBooked: true, viewDoctorId: widget.defaultViewDoctorId, selectedDate: widget.selectedDate);
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final isFilterActive = widget.hasActiveFilters;

    return FPopover(
      control: FPopoverControl.managed(controller: _controller),
      style: _filterPopoverMotion,
      groupId: _filterPopoverGroup,
      constraints: const FPortalConstraints(minWidth: 280, maxWidth: 320),
      popoverAnchor: Alignment.topCenter,
      childAnchor: Alignment.bottomCenter,
      popoverBuilder: (context, controller) => _SimplifiedBookingFilterPanel(
        controller: controller,
        filterPopoverGroup: _filterPopoverGroup,
        hideFullyBooked: widget.hideFullyBooked,
        viewDoctorId: widget.viewDoctorId,
        defaultViewDoctorId: widget.defaultViewDoctorId,
        selectedDate: widget.selectedDate,
        firstDate: widget.firstDate,
        lastDate: widget.lastDate,
        doctorItems: widget.doctorItems,
        enabled: widget.enabled,
        onApplyFilters: _applyFilters,
        onClearFilters: _clearFilters,
      ),
      builder: (context, controller, child) => MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: FTappable(
          onPress: widget.enabled ? controller.toggle : null,
          child: IgnorePointer(child: child),
        ),
      ),
      child: Tooltip(
        message: isFilterActive ? 'Filters active' : 'Filter slots',
        child: SizedBox(
          key: const Key('simplified_booking_filter_button'),
          width: 40,
          height: 40,
          child: Badge(
            isLabelVisible: isFilterActive,
            smallSize: 8,
            backgroundColor: colors.primary,
            child: Material(
              color: _isHovered ? colors.muted : colors.background,
              shape: CircleBorder(side: BorderSide(color: isFilterActive ? colors.primary : colors.border)),
              clipBehavior: Clip.antiAlias,
              child: Center(
                child: Icon(
                  Icons.filter_list_outlined,
                  color: isFilterActive ? colors.primary : colors.foreground,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SimplifiedBookingFilterPanel extends StatefulWidget {
  const _SimplifiedBookingFilterPanel({
    required this.controller,
    required this.filterPopoverGroup,
    required this.hideFullyBooked,
    required this.viewDoctorId,
    required this.defaultViewDoctorId,
    required this.selectedDate,
    required this.firstDate,
    required this.lastDate,
    required this.doctorItems,
    required this.enabled,
    required this.onApplyFilters,
    required this.onClearFilters,
  });

  final FPopoverController controller;
  final Object filterPopoverGroup;
  final bool hideFullyBooked;
  final String viewDoctorId;
  final String defaultViewDoctorId;
  final DateTime selectedDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Map<String, String> doctorItems;
  final bool enabled;
  final void Function({required bool hideFullyBooked, required String viewDoctorId, required DateTime selectedDate})
  onApplyFilters;
  final VoidCallback onClearFilters;

  @override
  State<_SimplifiedBookingFilterPanel> createState() => _SimplifiedBookingFilterPanelState();
}

class _SimplifiedBookingFilterPanelState extends State<_SimplifiedBookingFilterPanel> {
  late bool _draftHideFullyBooked;
  late String _draftViewDoctorId;
  late DateTime _draftSelectedDate;

  @override
  void initState() {
    super.initState();
    _syncDraftFromApplied();
  }

  @override
  void didUpdateWidget(covariant _SimplifiedBookingFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hideFullyBooked != widget.hideFullyBooked ||
        oldWidget.viewDoctorId != widget.viewDoctorId ||
        !_isSameDay(oldWidget.selectedDate, widget.selectedDate)) {
      _syncDraftFromApplied();
    }
  }

  void _syncDraftFromApplied() {
    _draftHideFullyBooked = widget.hideFullyBooked;
    _draftViewDoctorId = widget.viewDoctorId;
    _draftSelectedDate = widget.selectedDate;
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _applyFilters() {
    widget.onApplyFilters(
      hideFullyBooked: _draftHideFullyBooked,
      viewDoctorId: _draftViewDoctorId,
      selectedDate: clampSimplifiedBookingDate(_draftSelectedDate),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(SpacingTokens.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SpacingTokens.sm,
                  SpacingTokens.sm,
                  SpacingTokens.sm,
                  SpacingTokens.sm,
                ),
                child: Text('Filter by', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              _FilterInlineRow(
                label: 'Date',
                child: _InlineDateField(
                  key: const Key('simplified_booking_pick_date'),
                  value: _draftSelectedDate,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  popoverGroupId: widget.filterPopoverGroup,
                  enabled: widget.enabled,
                  onChanged: widget.enabled
                      ? (date) {
                          if (date != null) {
                            setState(() => _draftSelectedDate = date);
                          }
                        }
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs),
                child: Divider(height: 1, color: colors.border),
              ),
              _FilterInlineRow(
                label: 'Doctor',
                child: AppFilterSelect<String>(
                  key: const Key('simplified_booking_view_doctor'),
                  items: widget.doctorItems,
                  value: _draftViewDoctorId,
                  hintText: 'All doctors',
                  enabled: widget.enabled,
                  contentGroupId: widget.filterPopoverGroup,
                  showPopoverCloseButton: true,
                  onChanged: widget.enabled
                      ? (doctorId) => setState(() => _draftViewDoctorId = doctorId ?? widget.defaultViewDoctorId)
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs),
                child: Divider(height: 1, color: colors.border),
              ),
              _FilterInlineRow(
                label: 'Hide fully booked',
                child: AppSwitch(
                  key: const Key('simplified_booking_hide_fully_booked'),
                  value: _draftHideFullyBooked,
                  enabled: widget.enabled,
                  onChanged: (value) {
                    if (!widget.enabled) {
                      return;
                    }
                    setState(() => _draftHideFullyBooked = value);
                  },
                ),
              ),
            ],
          ),
        ),
        _FilterFooter(onClearFilters: widget.onClearFilters, onApplyFilters: widget.enabled ? _applyFilters : null),
      ],
    );
  }
}

class _FilterInlineRow extends StatelessWidget {
  const _FilterInlineRow({required this.label, required this.child});

  final String label;
  final Widget child;

  static const _labelWidth = 124.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _labelWidth,
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _InlineDateField extends StatefulWidget {
  const _InlineDateField({
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.popoverGroupId,
    required this.enabled,
    this.onChanged,
    super.key,
  });

  final DateTime value;
  final DateTime firstDate;
  final DateTime lastDate;
  final Object popoverGroupId;
  final bool enabled;
  final ValueChanged<DateTime?>? onChanged;

  @override
  State<_InlineDateField> createState() => _InlineDateFieldState();
}

class _InlineDateFieldState extends State<_InlineDateField> {
  late final FDateFieldController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FDateFieldController(date: widget.value, validator: (_) => null);
    _controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(covariant _InlineDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.value) {
      _controller.value = widget.value;
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChange)
      ..dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    widget.onChanged?.call(_controller.value);
  }

  @override
  Widget build(BuildContext context) {
    return FDateField(
      control: FDateFieldControl.managed(controller: _controller),
      size: AppFieldSize.sm.forui,
      enabled: widget.enabled,
      calendar: FDateFieldCalendarProperties(
        start: widget.firstDate,
        end: widget.lastDate,
        groupId: widget.popoverGroupId,
      ),
    );
  }
}

class _FilterFooter extends StatelessWidget {
  const _FilterFooter({required this.onClearFilters, this.onApplyFilters});

  final VoidCallback onClearFilters;
  final VoidCallback? onApplyFilters;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.45),
        border: Border(top: BorderSide(color: colors.border)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SpacingTokens.md, SpacingTokens.md, SpacingTokens.md, SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppButton(label: 'Apply Filters', size: AppFieldSize.sm, onPressed: onApplyFilters),
            const SizedBox(height: SpacingTokens.sm),
            AppButton(
              label: 'Clear Filters',
              variant: AppButtonVariant.outline,
              size: AppFieldSize.sm,
              onPressed: onApplyFilters == null ? null : onClearFilters,
            ),
          ],
        ),
      ),
    );
  }
}
