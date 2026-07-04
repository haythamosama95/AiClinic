import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_selector_notifier.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/service_price_preview.dart';

/// Type-ahead selector for eligible catalog services on draft invoices (015 US2).
class InvoiceServiceSelector extends ConsumerStatefulWidget {
  const InvoiceServiceSelector({
    required this.branchId,
    required this.currency,
    required this.enabled,
    required this.onServiceSelected,
    super.key,
  });

  final String branchId;
  final String currency;
  final bool enabled;
  final Future<void> Function(EligibleService service) onServiceSelected;

  @override
  ConsumerState<InvoiceServiceSelector> createState() => _InvoiceServiceSelectorState();
}

class _InvoiceServiceSelectorState extends ConsumerState<InvoiceServiceSelector> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _highlightedIndex = -1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onQueryChanged)
      ..dispose();
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      ref.read(serviceSelectorProvider(widget.branchId).notifier).search(_controller.text);
    }
  }

  void _onQueryChanged() {
    setState(() => _highlightedIndex = -1);
    ref.read(serviceSelectorProvider(widget.branchId).notifier).search(_controller.text);
  }

  Future<void> _selectService(EligibleService service) async {
    _controller.clear();
    setState(() => _highlightedIndex = -1);
    ref.read(serviceSelectorProvider(widget.branchId).notifier).search('');
    await widget.onServiceSelected(service);
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final results = ref.read(serviceSelectorProvider(widget.branchId)).value ?? const <EligibleService>[];
    if (results.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _highlightedIndex = (_highlightedIndex + 1).clamp(0, results.length - 1);
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedIndex = (_highlightedIndex - 1).clamp(0, results.length - 1);
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter && _highlightedIndex >= 0) {
      unawaited(_selectService(results[_highlightedIndex]));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final searchAsync = ref.watch(serviceSelectorProvider(widget.branchId));
    final results = searchAsync.value ?? const <EligibleService>[];

    return Focus(
      onKeyEvent: _handleKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            key: const Key('invoice_service_selector_field'),
            controller: _controller,
            focusNode: _focusNode,
            label: 'Add service from catalog',
            enabled: widget.enabled,
            hintText: 'Search eligible services…',
          ),
          if (searchAsync.isLoading) ...[const SizedBox(height: SpacingTokens.sm), const AppLinearProgress()],
          if (searchAsync.hasError) ...[
            const SizedBox(height: SpacingTokens.sm),
            Text('Could not search services.', style: theme.textTheme.bodySmall?.copyWith(color: colors.destructive)),
          ],
          if (results.isNotEmpty && widget.enabled) ...[
            const SizedBox(height: SpacingTokens.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: results.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: colors.border),
                  itemBuilder: (context, index) {
                    final service = results[index];
                    final highlighted = index == _highlightedIndex;
                    final priceLabel = ServicePricePreview.formatUnitPrice(
                      service.unitPrice,
                      currency: widget.currency,
                    );
                    final promoBadge = ServicePricePreview.promotionBadge(onPromotion: service.onPromotion);

                    return Material(
                      color: highlighted ? colors.muted.withValues(alpha: 0.5) : Colors.transparent,
                      child: ListTile(
                        key: Key('invoice_service_selector_result_$index'),
                        dense: true,
                        title: Text(service.name),
                        subtitle: Text(priceLabel),
                        trailing: promoBadge == null
                            ? null
                            : AppBadge(label: promoBadge, variant: AppBadgeVariant.accent),
                        onTap: widget.enabled ? () => unawaited(_selectService(service)) : null,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
