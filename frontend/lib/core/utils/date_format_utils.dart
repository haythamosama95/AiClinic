/// Formats a [DateTime] as `YYYY-MM-DD`. Returns `'—'` for null.
String formatDate(DateTime? date) {
  if (date == null) return '—';
  final y = date.year.toString();
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Formats a [DateTime] as `YYYY-MM-DD HH:mm` in local time.
String formatDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final date = formatDate(local);
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$date $h:$min';
}
