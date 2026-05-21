import 'package:flutter/foundation.dart';

/// Branch row shown when assigning staff to locations.
@immutable
class BranchSummary {
  const BranchSummary({required this.id, required this.name, this.code, this.address, this.phone, this.mapsUrl});

  final String id;
  final String name;
  final String? code;
  final String? address;
  final String? phone;
  final String? mapsUrl;

  static BranchSummary? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final name = row['name']?.toString().trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      return null;
    }

    String? optionalString(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    return BranchSummary(
      id: id,
      name: name,
      code: optionalString(row['code']),
      address: optionalString(row['address']),
      phone: optionalString(row['phone']),
      mapsUrl: optionalString(row['maps_url']),
    );
  }

  /// Multi-line details for the info icon tooltip.
  String get detailTooltip {
    final lines = <String>[
      'Branch ID: $id',
      if (code != null) 'Code: $code',
      if (address != null) 'Address: $address',
      if (phone != null) 'Phone: $phone',
      if (mapsUrl != null) 'Maps: $mapsUrl',
    ];
    return lines.join('\n');
  }
}
