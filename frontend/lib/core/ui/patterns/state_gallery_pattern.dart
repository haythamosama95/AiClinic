import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Canonical content-state discriminator for [AppAsyncStateView].
enum AppContentState {
  loading,
  emptyFirstRun,
  emptyNoResults,
  error,
  noAccess,
  degraded,
  ready,
}

/// Configuration for [AppAsyncStateView] treatments.
class AppContentStateConfig {
  const AppContentStateConfig({
    this.loadingLabel = 'Loading…',
    this.loadingSkeleton,
    this.emptyFirstRunTitle,
    this.emptyFirstRunDescription,
    this.emptyFirstRunActionLabel,
    this.onEmptyFirstRunAction,
    this.emptyNoResultsTitle,
    this.emptyNoResultsDescription,
    this.emptyNoResultsActionLabel,
    this.onEmptyNoResultsAction,
    this.noAccessTitle,
    this.noAccessDescription,
    this.errorTitle,
    this.errorMessage,
    this.onRetry,
    this.errorDetails,
    this.degradedTitle,
    this.degradedBody,
    this.degradedVariant = AppAlertVariant.warning,
    this.onDegradedDismiss,
  });

  final String loadingLabel;
  final Widget? loadingSkeleton;
  final String? emptyFirstRunTitle;
  final String? emptyFirstRunDescription;
  final String? emptyFirstRunActionLabel;
  final VoidCallback? onEmptyFirstRunAction;
  final String? emptyNoResultsTitle;
  final String? emptyNoResultsDescription;
  final String? emptyNoResultsActionLabel;
  final VoidCallback? onEmptyNoResultsAction;
  final String? noAccessTitle;
  final String? noAccessDescription;
  final String? errorTitle;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final String? errorDetails;
  final String? degradedTitle;
  final String? degradedBody;
  final AppAlertVariant degradedVariant;
  final VoidCallback? onDegradedDismiss;
}

/// Reusable async content-state switch for patterns and feature pages.
///
/// Given a [state], renders the appropriate treatment ([AppSkeleton] /
/// [AppEmptyState] variants / [AppErrorState] / [AppAlert]) or [child] when
/// [AppContentState.ready] or [AppContentState.degraded].
class AppAsyncStateView extends StatelessWidget {
  const AppAsyncStateView({
    required this.state,
    required this.child,
    this.config = const AppContentStateConfig(),
    this.degradedBannerAtTop = true,
    super.key,
  });

  final AppContentState state;
  final Widget child;
  final AppContentStateConfig config;
  final bool degradedBannerAtTop;

  @override
  Widget build(BuildContext context) {
    final degradedBanner = state == AppContentState.degraded &&
            config.degradedTitle != null
        ? AppAlert(
            variant: config.degradedVariant,
            title: config.degradedTitle!,
            body: config.degradedBody,
            dismissible: config.onDegradedDismiss != null,
            onDismiss: config.onDegradedDismiss,
          )
        : null;

    final content = switch (state) {
      AppContentState.loading => AppLoadingOverlay(
        isLoading: true,
        scope: AppLoadingOverlayScope.scoped,
        label: config.loadingLabel,
        skeleton: config.loadingSkeleton ?? _defaultLoadingSkeleton(context),
      ),
      AppContentState.emptyFirstRun => AppEmptyState(
        variant: AppEmptyStateVariant.firstRun,
        title: config.emptyFirstRunTitle,
        description: config.emptyFirstRunDescription,
        actionLabel: config.emptyFirstRunActionLabel,
        onAction: config.onEmptyFirstRunAction,
      ),
      AppContentState.emptyNoResults => AppEmptyState(
        variant: AppEmptyStateVariant.noResults,
        title: config.emptyNoResultsTitle,
        description: config.emptyNoResultsDescription,
        actionLabel: config.emptyNoResultsActionLabel,
        onAction: config.onEmptyNoResultsAction,
      ),
      AppContentState.error => AppErrorState(
        title: config.errorTitle ?? 'Failed to load',
        message: config.errorMessage ??
            "Can't reach the server. Check your connection and try again.",
        onRetry: config.onRetry,
        details: config.errorDetails,
      ),
      AppContentState.noAccess => AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: config.noAccessTitle,
        description: config.noAccessDescription,
      ),
      AppContentState.degraded || AppContentState.ready => child,
    };

    if (degradedBanner == null) {
      return content;
    }

    final body = state == AppContentState.degraded ? child : content;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (degradedBannerAtTop) degradedBanner,
        Expanded(child: body),
        if (!degradedBannerAtTop) degradedBanner,
      ],
    );
  }

  static Widget _defaultLoadingSkeleton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSkeleton(width: 192, height: AppSpacing.s8),
          const SizedBox(height: AppSpacing.s3),
          const AppSkeleton(height: AppSpacing.s10),
          for (var i = 0; i < 4; i++) ...[
            const SizedBox(height: AppSpacing.s3),
            const AppSkeleton(height: AppSpacing.s10),
          ],
        ],
      ),
    );
  }
}

/// Showcase-style state gallery wrapping [AppAsyncStateView] with a preview
/// [AppSegmentedControl] — useful for design-system demos; feature pages use
/// [AppAsyncStateView] directly.
class StateGalleryPattern extends StatelessWidget {
  const StateGalleryPattern({
    required this.state,
    required this.onStateChanged,
    required this.child,
    this.config = const AppContentStateConfig(),
    this.minHeight = 320,
    super.key,
  });

  final AppContentState state;
  final ValueChanged<AppContentState> onStateChanged;
  final Widget child;
  final AppContentStateConfig config;
  final double minHeight;

  static const List<AppSegmentedOption<AppContentState>> previewOptions = [
    AppSegmentedOption(value: AppContentState.loading, label: 'Loading'),
    AppSegmentedOption(
      value: AppContentState.emptyFirstRun,
      label: 'First-run',
    ),
    AppSegmentedOption(
      value: AppContentState.emptyNoResults,
      label: 'No results',
    ),
    AppSegmentedOption(value: AppContentState.error, label: 'Error'),
    AppSegmentedOption(value: AppContentState.noAccess, label: 'No access'),
    AppSegmentedOption(value: AppContentState.degraded, label: 'Degraded'),
    AppSegmentedOption(value: AppContentState.ready, label: 'Ready'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSegmentedControl<AppContentState>(
          options: previewOptions,
          value: state,
          onChanged: onStateChanged,
          semanticLabel: 'Preview content state',
          size: AppSegmentedControlSize.sm,
        ),
        const SizedBox(height: AppSpacing.s4),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: SizedBox(
            height: minHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.borderDefault),
                borderRadius: AppRadii.lgAll,
              ),
              child: ClipRRect(
                borderRadius: AppRadii.lgAll,
                child: AppAsyncStateView(
                  state: state,
                  config: config,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
