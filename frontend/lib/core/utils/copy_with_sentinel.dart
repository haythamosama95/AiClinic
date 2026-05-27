/// Sentinel value used in copyWith methods to distinguish
/// "not provided" from "explicitly set to null".
///
/// Usage in copyWith:
/// ```dart
/// PatientDetail copyWith({
///   Object? phone = copyWithSentinel,
/// }) {
///   return PatientDetail(
///     phone: identical(phone, copyWithSentinel) ? this.phone : phone as String?,
///   );
/// }
/// ```
const Object copyWithSentinel = _Sentinel();

class _Sentinel {
  const _Sentinel();
}
