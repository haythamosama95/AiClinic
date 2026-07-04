import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

/// Configures bundled typography before the first frame.
///
/// Fonts are declared in [pubspec.yaml] so [GoogleFonts] does not need runtime
/// network access or [AssetManifest.bin] lookups during hot restart.
Future<void> configureAppFonts() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
}
