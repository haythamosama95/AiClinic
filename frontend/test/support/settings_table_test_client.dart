import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [SupabaseClient] fake for settings repository list/fetch queries.
class SettingsTableTestClient extends Fake implements SupabaseClient {
  SettingsTableTestClient(this._tables);

  final Map<String, List<Map<String, dynamic>>> _tables;

  @override
  SupabaseQueryBuilder from(String table) => _TableQueryBuilder(_tables[table] ?? []);
}

class _TableQueryBuilder extends Fake implements SupabaseQueryBuilder {
  _TableQueryBuilder(this._rows) : _working = List<Map<String, dynamic>>.from(_rows);

  final List<Map<String, dynamic>> _rows;
  List<Map<String, dynamic>> _working;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([String columns = '*']) {
    return _FilterBuilder(_working);
  }
}

class _FilterBuilder extends Fake implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _FilterBuilder(this._rows);

  List<Map<String, dynamic>> _rows;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(String column, Object value) {
    _rows = _rows.where((row) => row[column] == value).toList();
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) {
    _rows = List<Map<String, dynamic>>.from(_rows)
      ..sort((a, b) {
        final left = a[column]?.toString() ?? '';
        final right = b[column]?.toString() ?? '';
        return ascending ? left.compareTo(right) : right.compareTo(left);
      });
    return this;
  }

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    return _MaybeSingleBuilder(_rows.isEmpty ? null : _rows.first);
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {Function? onError}) {
    return Future<List<Map<String, dynamic>>>.value(_rows).then(onValue, onError: onError);
  }
}

class _MaybeSingleBuilder extends Fake implements PostgrestTransformBuilder<Map<String, dynamic>?> {
  _MaybeSingleBuilder(this._row);

  final Map<String, dynamic>? _row;

  @override
  Future<R> then<R>(FutureOr<R> Function(Map<String, dynamic>? value) onValue, {Function? onError}) {
    return Future<Map<String, dynamic>?>.value(_row).then(onValue, onError: onError);
  }
}
