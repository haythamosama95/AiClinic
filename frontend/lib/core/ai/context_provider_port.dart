/// Injectable clinic-read port for registered context provider RPCs.
abstract class ContextProviderPort {
  /// Returns the `visit.chief_complaint@v1` payload under caller RLS.
  Future<Map<String, Object?>> fetchVisitChiefComplaint();
}
