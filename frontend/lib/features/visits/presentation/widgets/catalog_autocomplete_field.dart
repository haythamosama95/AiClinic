import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_text_field.dart';
import 'package:ai_clinic/features/visits/domain/catalog_item.dart';

/// User selection from a debounced catalog search field.
@immutable
class CatalogFieldSelection {
  const CatalogFieldSelection({required this.name, this.catalogId});

  final String name;
  final String? catalogId;

  bool get isCustom => catalogId == null;
}

/// Debounced catalog search with overlay results and free-text commit (013 US3/US4).
class CatalogAutocompleteField extends StatefulWidget {
  const CatalogAutocompleteField({
    required this.label,
    required this.onSearch,
    required this.onSelectionChanged,
    this.initialName,
    this.initialCatalogId,
    this.hintText,
    this.enabled = true,
    this.validator,
    this.searchDebounce = const Duration(milliseconds: 300),
    super.key,
  });

  final String label;
  final Future<List<CatalogItem>> Function(String query) onSearch;
  final ValueChanged<CatalogFieldSelection> onSelectionChanged;
  final String? initialName;
  final String? initialCatalogId;
  final String? hintText;
  final bool enabled;
  final String? Function(String?)? validator;
  final Duration searchDebounce;

  @override
  State<CatalogAutocompleteField> createState() => CatalogAutocompleteFieldState();
}

class CatalogAutocompleteFieldState extends State<CatalogAutocompleteField> {
  late final TextEditingController _controller;
  Timer? _searchDebounce;
  String _lastQuery = '';
  String? _selectedCatalogId;
  String? _selectedCatalogName;
  List<CatalogItem> _results = const [];
  bool _searching = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _selectedCatalogId = widget.initialCatalogId;
    _controller = TextEditingController(text: widget.initialName ?? '');
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }

  CatalogFieldSelection get currentSelection =>
      CatalogFieldSelection(name: _controller.text.trim(), catalogId: _selectedCatalogId);

  void _onTextChanged() {
    final text = _controller.text;
    if (_selectedCatalogId != null && _selectedCatalogName != text) {
      _selectedCatalogId = null;
      _selectedCatalogName = null;
    }

    widget.onSelectionChanged(CatalogFieldSelection(name: text.trim(), catalogId: _selectedCatalogId));

    _searchDebounce?.cancel();
    _searchDebounce = Timer(widget.searchDebounce, () {
      if (!mounted) {
        return;
      }
      unawaited(_runSearch(text));
    });
  }

  Future<void> _runSearch(String query) async {
    _lastQuery = query;
    setState(() {
      _searching = true;
      _searchError = null;
    });

    try {
      final results = await widget.onSearch(query);
      if (!mounted || _lastQuery != query) {
        return;
      }
      setState(() {
        _searching = false;
        _results = results;
      });
    } catch (_) {
      if (!mounted || _lastQuery != query) {
        return;
      }
      setState(() {
        _searching = false;
        _results = const [];
        _searchError = 'Could not search catalog.';
      });
    }
  }

  void _selectItem(CatalogItem item) {
    setState(() {
      _selectedCatalogId = item.id;
      _selectedCatalogName = item.name;
      _controller.text = item.name;
      _results = const [];
      _lastQuery = item.name;
    });
    widget.onSelectionChanged(CatalogFieldSelection(name: item.name, catalogId: item.id));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VisitTextField(
          key: const Key('catalog_autocomplete_field'),
          label: widget.label,
          controller: _controller,
          hintText: widget.hintText ?? 'Type to search or enter a custom name',
          enabled: widget.enabled,
          validator: widget.validator,
          onChanged: (_) {},
        ),
        if (_searching) ...[const SizedBox(height: SpacingTokens.sm), const AppLinearProgress()],
        if (_searchError != null) ...[
          const SizedBox(height: SpacingTokens.sm),
          Text(_searchError!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.destructive)),
        ],
        if (_results.isNotEmpty && widget.enabled) ...[
          const SizedBox(height: SpacingTokens.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: colors.border),
                itemBuilder: (context, index) {
                  final item = _results[index];
                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      key: Key('catalog_autocomplete_result_$index'),
                      dense: true,
                      title: Text(item.name),
                      onTap: widget.enabled ? () => _selectItem(item) : null,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}
