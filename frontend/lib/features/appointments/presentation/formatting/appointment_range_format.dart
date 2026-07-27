import 'package:intl/intl.dart';

/// Formats an appointment time range for display (V1-4).
///
/// Example: `Mon, Jul 27 · 9:00 AM – 9:30 AM`
String formatAppointmentRange(DateTime start, DateTime end) {
  final localStart = start.toLocal();
  final localEnd = end.toLocal();
  final day = DateFormat('EEE, MMM d').format(localStart);
  final from = DateFormat('h:mm a').format(localStart);
  final to = DateFormat('h:mm a').format(localEnd);
  return '$day · $from – $to';
}
