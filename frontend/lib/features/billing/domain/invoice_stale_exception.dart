/// Thrown when optimistic concurrency detects a stale invoice revision.
class InvoiceStaleException implements Exception {
  const InvoiceStaleException();

  @override
  String toString() => 'Invoice was updated elsewhere.';
}
