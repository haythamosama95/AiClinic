import '../../shape_tokens.dart';

/// eCarely variant border radii — soft clinical UI with generously rounded cards.
///
/// Card radius target: 16–24px. Button/search radius target: 8–12px.
/// Card padding target: 24px ([SpacingTokens.lg]).
/// Card gap target: 20–24px.
abstract final class ECarelyShapeTokens {
  static const values = ShapeTokens(sm: 8, md: 12, lg: 20, xl: 24);
}
