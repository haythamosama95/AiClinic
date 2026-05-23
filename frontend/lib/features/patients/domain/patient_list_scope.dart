/// List/search scope for patient browse (V1-3).
enum PatientListScope {
  /// Active branch only (`search_patients` scope `branch`).
  thisBranch,

  /// All branches in the organization (`search_patients` scope `organization`).
  allBranches;

  static PatientListScope? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return switch (normalized) {
      'thisbranch' || 'this_branch' || 'branch' => PatientListScope.thisBranch,
      'allbranches' || 'all_branches' || 'organization' => PatientListScope.allBranches,
      _ => null,
    };
  }

  /// Wire value for `search_patients.p_scope`.
  String get rpcScopeValue => switch (this) {
    PatientListScope.thisBranch => 'branch',
    PatientListScope.allBranches => 'organization',
  };
}
