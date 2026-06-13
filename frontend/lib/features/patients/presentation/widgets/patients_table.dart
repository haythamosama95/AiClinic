import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';

/// Column layout shared by header, body rows, and skeleton.
final patientTableColumns = <AppDataTableColumn>[
  const AppDataTableColumn(label: 'Patient', flex: 3),
  const AppDataTableColumn(label: 'Age/Gender', flex: 2, width: 108),
  const AppDataTableColumn(label: 'Contact', flex: 2, width: 132),
  const AppDataTableColumn(label: 'Last Visit', flex: 2, width: 112),
  const AppDataTableColumn(label: 'Next Appointment', flex: 2, width: 148),
];

/// Dense patient data table with pagination footer.
class PatientsTable extends StatefulWidget {
  const PatientsTable({
    required this.rows,
    required this.totalCount,
    required this.filters,
    required this.onRowTap,
    required this.onPageChanged,
    super.key,
  });

  final List<PatientTableRow> rows;
  final int totalCount;
  final PatientListFilters filters;
  final void Function(PatientTableRow row, Rect? sourceRect) onRowTap;
  final ValueChanged<int> onPageChanged;

  @override
  State<PatientsTable> createState() => _PatientsTableState();
}

class _PatientsTableState extends State<PatientsTable> {
  var _slideDirection = 0;
  var _isPageAnimating = false;

  static final _dateFormat = DateFormat.yMMMd();
  static final _dateTimeFormat = DateFormat('MMM d · h:mm a');

  void _goToPage(int page) {
    final currentPage = widget.filters.page;
    if (page == currentPage || _isPageAnimating) {
      return;
    }
    setState(() => _slideDirection = page > currentPage ? 1 : -1);
    widget.onPageChanged(page);
  }

  void _onPageTransitionAnimating(bool animating) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isPageAnimating = animating;
      if (!animating) {
        _slideDirection = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final totalCount = widget.totalCount;
    final filters = widget.filters;
    final start = totalCount == 0 ? 0 : filters.offset + 1;
    final end = (filters.offset + rows.length).clamp(0, totalCount);
    final totalPages = (totalCount / filters.pageSize).ceil().clamp(1, 1 << 30);
    final currentPage = filters.page.clamp(1, totalPages);

    return AppDataTable(
      columns: patientTableColumns,
      rowCount: rows.length,
      bodyPageKey: currentPage,
      bodySlideDirection: _slideDirection,
      onBodyTransitionAnimating: _onPageTransitionAnimating,
      rowBuilder: (context, index) {
        final row = rows[index];
        return AppDataTableRow(
          columns: patientTableColumns,
          onTap: (rowContext) {
            final box = rowContext.findRenderObject() as RenderBox?;
            final sourceRect = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
            widget.onRowTap(row, sourceRect);
          },
          cells: [
            _PatientCell(row: row),
            Text(row.ageGenderLabel, style: _cellStyle(context)),
            Text(row.item.phone ?? '—', style: _cellStyle(context)),
            Text(row.lastVisitAt == null ? '—' : _dateFormat.format(row.lastVisitAt!), style: _cellStyle(context)),
            row.nextAppointmentAt == null
                ? _SchedulePlaceholder()
                : AppBadge(
                    label: _dateTimeFormat.format(row.nextAppointmentAt!),
                    variant: AppBadgeVariant.accent,
                    dense: true,
                  ),
          ],
        );
      },
      footer: _PatientsTableFooter(
        summary: 'Showing $start–$end of $totalCount',
        currentPage: currentPage,
        totalPages: totalPages,
        onPrevious: currentPage > 1 && !_isPageAnimating ? () => _goToPage(currentPage - 1) : null,
        onNext: currentPage < totalPages && !_isPageAnimating ? () => _goToPage(currentPage + 1) : null,
      ),
    );
  }

  TextStyle? _cellStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12.5);
  }
}

class _PatientCell extends StatelessWidget {
  const _PatientCell({required this.row});

  final PatientTableRow row;

  static const _avatarWidth = 30.0;
  static const _avatarGap = SpacingTokens.sm;
  static const _avatarLayoutWidth = _avatarWidth + _avatarGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    final nameStyle = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 13);
    final idStyle = theme.textTheme.labelSmall?.copyWith(color: colors.mutedForeground, fontSize: 11);
    final labels = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(row.item.fullName, style: nameStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text('ID ${row.displayId}', style: idStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final showAvatar = constraints.maxWidth > _avatarLayoutWidth;

        return Row(
          children: [
            if (showAvatar) ...[_PatientAvatar(name: row.item.fullName), const SizedBox(width: _avatarGap)],
            Expanded(child: labels),
          ],
        );
      },
    );
  }
}

class _PatientAvatar extends StatelessWidget {
  const _PatientAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final initials = _initialsFor(name);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(context.shapeTokens.sm),
        border: Border.all(color: colors.border),
      ),
      child: SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: Text(
            initials,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.secondaryForeground,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  static String _initialsFor(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _SchedulePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.event_available_outlined, size: 14, color: colors.mutedForeground),
        const SizedBox(width: SpacingTokens.xs),
        Text('Schedule', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.mutedForeground)),
      ],
    );
  }
}

class _PatientsTableFooter extends StatelessWidget {
  const _PatientsTableFooter({
    required this.summary,
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  });

  final String summary;
  final int currentPage;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
      child: Row(
        children: [
          Text(summary, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.mutedForeground)),
          const Spacer(),
          AppIconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            tooltip: 'Previous page',
            variant: AppIconButtonVariant.outline,
            onPressed: onPrevious,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
            child: Text(
              '$currentPage / $totalPages',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          AppIconButton(
            icon: const Icon(Icons.chevron_right, size: 18),
            tooltip: 'Next page',
            variant: AppIconButtonVariant.outline,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
