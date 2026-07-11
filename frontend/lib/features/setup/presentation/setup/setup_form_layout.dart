import 'package:flutter/material.dart';

/// Viewport breakpoint for two-column setup form rows (web Tailwind `sm`).
const setupFormTwoColumnBreakpoint = 640.0;

/// Whether setup form rows should render two fields side-by-side.
///
/// Matches the web reference, which uses viewport-based `sm:grid-cols-2` rather
/// than the local content width. This keeps two-column rows in the setup dialog
/// where the step rail reduces the available field area below 640px.
bool setupFormUseTwoColumns(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= setupFormTwoColumnBreakpoint;
}
