import '../../shape_tokens.dart';

/// Med Spectra variant border radii — soft UI with generously rounded cards.
///
/// Card padding target: 24px ([SpacingTokens.lg]).
/// Card gap target: 20px (between [SpacingTokens.md] and [SpacingTokens.lg]).
abstract final class MedSpectraShapeTokens {
  static const values = ShapeTokens(sm: 12, md: 20, lg: 24, xl: 28);
}
