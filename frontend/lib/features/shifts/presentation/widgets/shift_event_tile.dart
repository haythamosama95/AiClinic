import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';

import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_status_badge.dart';

/// Week-view event tile for a branch shift (V1-7 US2).
class ShiftEventTile extends StatelessWidget {
  const ShiftEventTile({required this.item, required this.boundary, this.onTap, super.key});

  final ShiftListItem item;
  final Rect boundary;
  final VoidCallback? onTap;

  static Widget weekBuilder(
    DateTime date,
    List<CalendarEventData<ShiftListItem>> events,
    Rect boundary,
    DateTime startDuration,
    DateTime endDuration,
  ) {
    final event = events.first;
    final item = event.event;
    if (item == null) {
      return const SizedBox.shrink();
    }

    return ShiftEventTile(item: item, boundary: boundary);
  }

  Color _tileColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (item.status) {
      ShiftStatus.incomplete => scheme.tertiary,
      ShiftStatus.active => scheme.primary,
      ShiftStatus.cancelled => scheme.error,
      ShiftStatus.unknown => scheme.outline,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tileColor = _tileColor(context);
    final brightness = ThemeData.estimateBrightnessForColor(tileColor);
    final textColor = brightness == Brightness.dark ? Colors.white : Colors.black87;

    return Semantics(
      label: '${item.startTime} to ${item.endTime}, ${item.assigneeSummary}',
      button: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('shift_event_tile_${item.id}'),
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: tileColor.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tileColor.withValues(alpha: 0.95), width: 1.1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.startTime}–${item.endTime}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textColor),
                ),
                const SizedBox(height: 2),
                Text(
                  item.assigneeSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.95)),
                ),
                if (item.isUnassigned) ...[
                  const SizedBox(height: 2),
                  ShiftStatusBadge(status: ShiftStatus.incomplete, isUnassigned: true),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
