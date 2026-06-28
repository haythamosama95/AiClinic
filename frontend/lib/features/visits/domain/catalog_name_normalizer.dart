/// Normalizes custom catalog names before save and display (013 FR-006a).
abstract final class CatalogNameNormalizer {
  /// Trims, collapses internal whitespace, and capitalizes the first character.
  static String normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    final collapsed = trimmed.replaceAll(RegExp(r'\s+'), ' ');
    return collapsed[0].toUpperCase() + collapsed.substring(1);
  }
}
