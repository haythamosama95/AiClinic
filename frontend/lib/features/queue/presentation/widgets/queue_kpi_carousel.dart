import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/queue/domain/queue_display.dart';

/// Supplementary KPI counts and per-card trends for [QueueKpiCarousel].
///
/// Counts not present on [AppointmentQueueStats] are supplied here. Trend fields
/// are null when day-over-day comparison data is unavailable.
class QueueKpiCarouselTrends {
  const QueueKpiCarouselTrends({
    required this.waiting,
    required this.checkedIn,
    required this.inProgress,
    required this.cancelled,
    required this.queueLength,
    this.waitingTrend,
    this.checkedInTrend,
    this.inProgressTrend,
    this.queueLengthTrend,
    this.cancelledTrend,
  });

  final int waiting;
  final int checkedIn;
  final int inProgress;
  final int cancelled;
  final int queueLength;
  final AppointmentQueueStatTrend? waitingTrend;
  final AppointmentQueueStatTrend? checkedInTrend;
  final AppointmentQueueStatTrend? inProgressTrend;
  final AppointmentQueueStatTrend? queueLengthTrend;
  final AppointmentQueueStatTrend? cancelledTrend;
}

enum _KpiCardId {
  total,
  waiting,
  checkedIn,
  inProgress,
  completed,
  queueLength,
  avgWait,
  avgConsult,
  cancelled,
  noShow,
}

enum _TrendDirection { up, down, flat }

class _KpiTrendPresentation {
  const _KpiTrendPresentation({
    required this.direction,
    required this.favorableUp,
    this.label,
  });

  final _TrendDirection direction;
  final bool favorableUp;
  final String? label;

  bool get isGood =>
      (direction == _TrendDirection.up && favorableUp) ||
      (direction == _TrendDirection.down && !favorableUp);
}

class _KpiCardData {
  const _KpiCardData({
    required this.id,
    required this.label,
    required this.value,
    this.valueColor,
    this.trend,
  });

  final _KpiCardId id;
  final String label;
  final String value;
  final Color? valueColor;
  final _KpiTrendPresentation? trend;
}

/// Horizontal KPI statistics carousel (web `QueueStats`).
class QueueKpiCarousel extends StatefulWidget {
  const QueueKpiCarousel({
    required this.stats,
    required this.trends,
    super.key,
  });

  final AppointmentQueueStats stats;
  final QueueKpiCarouselTrends trends;

  @override
  State<QueueKpiCarousel> createState() => _QueueKpiCarouselState();
}

class _QueueKpiCarouselState extends State<QueueKpiCarousel> {
  static const _scrollEpsilon = 4.0;

  late final ScrollController _scrollController;
  var _canScrollLeft = false;
  var _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_updateScrollState);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateScrollState)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant QueueKpiCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
  }

  void _updateScrollState() {
    if (!_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    final nextLeft = position.pixels > _scrollEpsilon;
    final nextRight =
        position.pixels + position.viewportDimension < position.maxScrollExtent - _scrollEpsilon;

    if (nextLeft != _canScrollLeft || nextRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = nextLeft;
        _canScrollRight = nextRight;
      });
    }
  }

  void _scrollByDirection(bool left) {
    if (!_scrollController.hasClients) {
      return;
    }

    final cardWidth = _estimateCardWidth(context);
    final delta = cardWidth * 2 * (left ? -1 : 1);
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    _scrollController.animateTo(
      (_scrollController.offset + delta).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      ),
      duration: tickerEnabled && !disableAnimations
          ? const Duration(milliseconds: 300)
          : Duration.zero,
      curve: Curves.easeOut,
    );
  }

  double _estimateCardWidth(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    return _cardMinWidth(viewportWidth);
  }

  List<_KpiCardData> _buildCards(BuildContext context) {
    final stats = widget.stats;
    final trends = widget.trends;

    return [
      _KpiCardData(
        id: _KpiCardId.total,
        label: 'Total today',
        value: '${stats.total}',
        trend: _trendFor(stats.totalTrend, favorableUp: true),
      ),
      _KpiCardData(
        id: _KpiCardId.waiting,
        label: 'Waiting',
        value: '${trends.waiting}',
        valueColor: context.appColors.statusWarningFg,
        trend: _trendFor(trends.waitingTrend, favorableUp: false),
      ),
      _KpiCardData(
        id: _KpiCardId.checkedIn,
        label: 'Checked in',
        value: '${trends.checkedIn}',
        valueColor: context.appColors.actionPrimary,
        trend: _trendFor(trends.checkedInTrend, favorableUp: true),
      ),
      _KpiCardData(
        id: _KpiCardId.inProgress,
        label: 'In progress',
        value: '${trends.inProgress}',
        valueColor: context.appColors.statusInfoFg,
        trend: _trendFor(trends.inProgressTrend, favorableUp: true),
      ),
      _KpiCardData(
        id: _KpiCardId.completed,
        label: 'Completed',
        value: '${stats.completed}',
        valueColor: context.appColors.statusSuccessFg,
        trend: _trendFor(stats.completedTrend, favorableUp: true),
      ),
      _KpiCardData(
        id: _KpiCardId.queueLength,
        label: 'Queue length',
        value: '${trends.queueLength}',
        trend: _trendFor(trends.queueLengthTrend, favorableUp: false),
      ),
      _KpiCardData(
        id: _KpiCardId.avgWait,
        label: 'Avg wait',
        value: _formatDurationMinutes(stats.avgWaitMinutes),
        trend: _trendFor(stats.avgWaitTrend, favorableUp: true),
      ),
      _KpiCardData(
        id: _KpiCardId.avgConsult,
        label: 'Avg consult',
        value: _formatDurationMinutes(stats.avgVisitMinutes),
        trend: _trendFor(stats.avgVisitTrend, favorableUp: false),
      ),
      _KpiCardData(
        id: _KpiCardId.cancelled,
        label: 'Cancelled',
        value: '${trends.cancelled}',
        trend: _trendFor(trends.cancelledTrend, favorableUp: true),
      ),
      _KpiCardData(
        id: _KpiCardId.noShow,
        label: 'No show',
        value: '${stats.noShow}',
        valueColor: context.appColors.statusDangerFg,
        trend: _trendFor(stats.noShowTrend, favorableUp: true),
      ),
    ];
  }

  String _formatDurationMinutes(int? minutes) {
    if (minutes == null) {
      return '—';
    }
    return AppointmentQueueDisplay.formatDurationLabel(Duration(minutes: minutes));
  }

  _KpiTrendPresentation? _trendFor(
    AppointmentQueueStatTrend? trend, {
    required bool favorableUp,
  }) {
    final percentChange = trend?.percentChange;
    if (percentChange == null) {
      return null;
    }

    final direction = switch (percentChange) {
      > 0.01 => _TrendDirection.up,
      < -0.01 => _TrendDirection.down,
      _ => _TrendDirection.flat,
    };

    return _KpiTrendPresentation(
      direction: direction,
      favorableUp: favorableUp,
      label: direction == _TrendDirection.flat
          ? 'same as yesterday'
          : _formatTrendLabel(percentChange),
    );
  }

  String _formatTrendLabel(double percentChange) {
    final sign = percentChange > 0 ? '+' : '−';
    final magnitude = percentChange.abs();
    final formatted = magnitude == magnitude.roundToDouble()
        ? magnitude.toInt().toString()
        : magnitude.toStringAsFixed(1);
    return '$sign$formatted% vs yesterday';
  }

  double _columnCount(double width) {
    if (width >= 1280) {
      return 6;
    }
    if (width >= 1024) {
      return 5;
    }
    if (width >= 768) {
      return 4;
    }
    if (width >= 640) {
      return 3;
    }
    return 2;
  }

  double _cardMinWidth(double width) {
    const gap = AppSpacing.space3;
    final columns = _columnCount(width);
    return (width - gap * (columns - 1)) / columns;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cards = _buildCards(context);

    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());

    return Semantics(
      label: 'Queue statistics',
      container: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardMinWidth = _cardMinWidth(constraints.maxWidth);
          final showEdgeFades = constraints.maxWidth >= 1024;

          return Stack(
            children: [
              if (showEdgeFades) ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: SizedBox(
                      width: AppSpacing.space10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              colors.surfaceCanvas,
                              colors.surfaceCanvas.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: SizedBox(
                      width: AppSpacing.space10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [
                              colors.surfaceCanvas,
                              colors.surfaceCanvas.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              Row(
                children: [
                  AppIconButton(
                    icon: const Icon(Icons.chevron_left),
                    label: 'Scroll statistics left',
                    size: AppIconButtonSize.sm,
                    variant: AppIconButtonVariant.secondary,
                    onPressed: _canScrollLeft ? () => _scrollByDirection(true) : null,
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  Expanded(
                    child: Semantics(
                      label: 'Queue KPI cards',
                      container: true,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (_) {
                          _updateScrollState();
                          return false;
                        },
                        child: ScrollConfiguration(
                          behavior: const _HiddenScrollbarBehavior(),
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            child: Row(
                              children: [
                                for (var i = 0; i < cards.length; i++) ...[
                                  if (i > 0) const SizedBox(width: AppSpacing.space3),
                                  SizedBox(
                                    width: cardMinWidth,
                                    child: _KpiCard(
                                      key: ValueKey(cards[i].id),
                                      data: cards[i],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  AppIconButton(
                    icon: const Icon(Icons.chevron_right),
                    label: 'Scroll statistics right',
                    size: AppIconButtonSize.sm,
                    variant: AppIconButtonVariant.secondary,
                    onPressed: _canScrollRight ? () => _scrollByDirection(false) : null,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data, super.key});

  final _KpiCardData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final trend = data.trend;
    final surface = _trendSurface(trend, colors);
    final semanticsValue = trend?.label == null
        ? '${data.label}: ${data.value}'
        : '${data.label}: ${data.value}, ${trend!.label}';

    return Semantics(
      label: semanticsValue,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: surface.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: AppCard(
            variant: CardVariant.flat,
            padding: CardPadding.md,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(decoration: BoxDecoration(gradient: surface.gradient)),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.value,
                      style: AppTypography.mono(context).copyWith(
                        fontSize: 24,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                        color: data.valueColor ?? colors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text(
                      data.label,
                      style: AppTypography.bodySm(context).copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                    if (trend != null) ...[
                      const SizedBox(height: AppSpacing.space2),
                      _TrendIndicator(trend: trend),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _TrendSurface _trendSurface(_KpiTrendPresentation? trend, AppSemanticColors colors) {
    if (trend == null || trend.direction == _TrendDirection.flat) {
      return _TrendSurface(
        border: colors.borderDefault,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.surfaceSunken.withValues(alpha: 0.4),
            colors.surfaceDefault,
            colors.surfaceDefault,
          ],
        ),
      );
    }

    if (trend.isGood) {
      return _TrendSurface(
        border: colors.statusSuccessBorder.withValues(alpha: 0.4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.statusSuccessSurface.withValues(alpha: 0.7),
            colors.surfaceDefault,
            colors.surfaceDefault,
          ],
        ),
      );
    }

    return _TrendSurface(
      border: colors.statusWarningBorder.withValues(alpha: 0.4),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colors.statusWarningSurface.withValues(alpha: 0.7),
          colors.surfaceDefault,
          colors.surfaceDefault,
        ],
      ),
    );
  }
}

class _TrendSurface {
  const _TrendSurface({required this.border, required this.gradient});

  final Color border;
  final Gradient gradient;
}

class _TrendIndicator extends StatelessWidget {
  const _TrendIndicator({required this.trend});

  final _KpiTrendPresentation trend;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = switch (trend.direction) {
      _TrendDirection.flat => colors.textTertiary,
      _ when trend.isGood => colors.statusSuccessFg,
      _ => colors.statusWarningFg,
    };

    final icon = switch (trend.direction) {
      _TrendDirection.up => Icons.trending_up,
      _TrendDirection.down => Icons.trending_down,
      _TrendDirection.flat => Icons.remove,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.space1),
        Flexible(
          child: Text(
            trend.label ?? 'same as yesterday',
            style: AppTypography.bodySm(context).copyWith(
              fontWeight: FontWeight.w500,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _HiddenScrollbarBehavior extends ScrollBehavior {
  const _HiddenScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
