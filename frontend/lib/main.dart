import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

/// Boots the app inside Riverpod's global provider scope.
void main() {
  runApp(const ProviderScope(child: AiClinicApp()));
}
