/// Injectable clinic-read port for registered context provider RPCs.
///
/// Production: construct [SupabaseContextProviderPort] per visit (visit id is
/// constructor-injected; [fetchVisitChiefComplaint] takes no arguments).
abstract class ContextProviderPort {
  /// Returns the `visit.chief_complaint@v1` payload under caller permissions.
  Future<Map<String, Object?>> fetchVisitChiefComplaint();
}
