import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_clinic/features/settings/presentation/setup/setup_draft_models.dart';

const _setupDraftKey = 'aiclinic:setup-draft';
const _setupCompleteKey = 'aiclinic:setup-complete';

@immutable
class ClinicSetupDraftState {
  const ClinicSetupDraftState({
    required this.draft,
    this.step = 0,
    this.completed = false,
  });

  final SetupDraft draft;
  final int step;
  final bool completed;

  ClinicSetupDraftState copyWith({
    SetupDraft? draft,
    int? step,
    bool? completed,
  }) {
    return ClinicSetupDraftState(
      draft: draft ?? this.draft,
      step: step ?? this.step,
      completed: completed ?? this.completed,
    );
  }
}

final clinicSetupDraftProvider = StateNotifierProvider<ClinicSetupDraftNotifier, ClinicSetupDraftState>(
  (ref) => ClinicSetupDraftNotifier(),
);

/// Whether the clinic setup wizard has been completed (mirrors web `isSetupComplete`).
final isSetupCompleteProvider = Provider<bool>((ref) {
  return ref.watch(clinicSetupDraftProvider).completed;
});

/// Page-local setup draft notifier mirroring web `SetupContext`.
class ClinicSetupDraftNotifier extends StateNotifier<ClinicSetupDraftState> {
  ClinicSetupDraftNotifier()
      : super(ClinicSetupDraftState(draft: createDefaultSetup())) {
    Future<void>.microtask(loadDraft);
  }

  /// Loads the persisted draft and completion flag from [SharedPreferences].
  ///
  /// Web does not persist wizard step — only the draft and completion flag are
  /// restored; [ClinicSetupDraftState.step] always starts at 0.
  Future<void> loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_setupDraftKey);
      final completed = prefs.getString(_setupCompleteKey) == 'true';

      final draft = raw == null || raw.isEmpty
          ? createDefaultSetup()
          : SetupDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);

      state = ClinicSetupDraftState(draft: draft, completed: completed);
    } on Object {
      state = ClinicSetupDraftState(draft: createDefaultSetup());
    }
  }

  /// Persists the current draft to [SharedPreferences].
  Future<void> persistDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_setupDraftKey, jsonEncode(state.draft.toJson()));
    } on Object {
      // No-op when preferences are unavailable.
    }
  }

  void setStep(int step) {
    state = state.copyWith(step: step < 0 ? 0 : step);
    persistDraft();
  }

  void updateOrganization({
    String? name,
    String? timezone,
    String? currency,
  }) {
    state = state.copyWith(
      draft: state.draft.copyWith(
        organization: state.draft.organization.copyWith(
          name: name,
          timezone: timezone,
          currency: currency,
        ),
      ),
    );
    persistDraft();
  }

  void setBranches(List<BranchDraft> branches) {
    state = state.copyWith(
      draft: state.draft.copyWith(branches: branches),
    );
    persistDraft();
  }

  void updateBranch(
    String id, {
    String? name,
    String? code,
    String? mobile,
    String? mapLocation,
    List<WorkingDay>? workingDays,
  }) {
    setBranches(
      state.draft.branches
          .map(
            (branch) => branch.id == id
                ? branch.copyWith(
                    name: name,
                    code: code,
                    mobile: mobile,
                    mapLocation: mapLocation,
                    workingDays: workingDays,
                  )
                : branch,
          )
          .toList(),
    );
  }

  BranchDraft addBranch() {
    final branch = createEmptyBranch();
    setBranches([...state.draft.branches, branch]);
    return branch;
  }

  void removeBranch(String id) {
    setBranches(state.draft.branches.where((branch) => branch.id != id).toList());
  }

  void setStaff(List<StaffDraft> staff) {
    state = state.copyWith(
      draft: state.draft.copyWith(staff: staff),
    );
    persistDraft();
  }

  void updateStaff(
    String id, {
    String? name,
    String? mobile,
    String? username,
    String? password,
    String? role,
    List<String>? branchIds,
  }) {
    setStaff(
      state.draft.staff
          .map(
            (member) => member.id == id
                ? member.copyWith(
                    name: name,
                    mobile: mobile,
                    username: username,
                    password: password,
                    role: role,
                    branchIds: branchIds,
                  )
                : member,
          )
          .toList(),
    );
  }

  StaffDraft addStaff() {
    final member = createEmptyStaff();
    setStaff([...state.draft.staff, member]);
    return member;
  }

  void removeStaff(String id) {
    setStaff(state.draft.staff.where((member) => member.id != id).toList());
  }

  void setServices(List<ServiceDraft> services) {
    state = state.copyWith(
      draft: state.draft.copyWith(services: services),
    );
    persistDraft();
  }

  void updateService(
    String id, {
    String? name,
    double? price,
    bool clearPrice = false,
  }) {
    setServices(
      state.draft.services
          .map(
            (service) => service.id == id
                ? service.copyWith(name: name, price: price, clearPrice: clearPrice)
                : service,
          )
          .toList(),
    );
  }

  ServiceDraft addService() {
    final service = createEmptyService();
    setServices([...state.draft.services, service]);
    return service;
  }

  void removeService(String id) {
    setServices(state.draft.services.where((service) => service.id != id).toList());
  }

  Future<void> completeSetup() async {
    state = state.copyWith(completed: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_setupCompleteKey, 'true');
    } on Object {
      // No-op when preferences are unavailable.
    }
    await persistDraft();
  }

  Future<void> resetSetup() async {
    final fresh = createDefaultSetup();
    state = ClinicSetupDraftState(draft: fresh, step: 0, completed: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_setupCompleteKey);
    } on Object {
      // No-op when preferences are unavailable.
    }
    await persistDraft();
  }
}
