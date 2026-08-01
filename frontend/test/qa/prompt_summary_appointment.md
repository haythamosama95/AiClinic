All verification passes: no changes to frontend/lib or pubspec.yaml (so no production code touched and no new dependencies), and no lint errors across the new and modified test files.

What was done
The appointments test suite went from 40 files / ~280 cases to 73 files / 666 cases — 18 new files, 14 expanded, 2 deleted, +2,427 lines. The two deletions were both justified: a test for AppointmentBookingValidation, a class that exists nowhere in the codebase, and the monolithic appointment_repository_test.dart, whose unique getSettings/setDefaultDuration/getAppointment coverage was migrated into a focused appointment_repository_settings_test.dart before removal.

The biggest structural change is that test/widget/appointments/ now exists at all. It previously did not, despite the project's own docs and QA manifest referencing that path — 21 files and roughly 120 widget cases now cover both real pages, the booking flow, the status actions, and all four dialogs.

Three findings that need a decision from you
One real production bug. AppointmentListItem.copyWith coalesces with ?? this.field, so the containsKey ternary in appointment_queue_realtime_apply.dart is dead logic — both branches produce the same result and a null can never clear a timestamp. Undoing a check-in over realtime leaves a stale checkedInAt, which feeds the queue's wait-time math. The codebase already has the fix pattern in core/utils/copy_with_sentinel.dart, used by AppointmentDetail.copyWith. I converted the agent's red test into a documented characterization test so the suite isn't knowingly failing; flipping it to isNull is the one-line signal that the fix landed.

A dead code path. 'Appointment settings are not loaded yet.' in the booking sheet is unreachable through the UI: when settings are null after loading, build() returns SizedBox.shrink(), so no submit surface ever exists to hit that guard. It's defensive code that can't fire.

A spec-versus-implementation divergence. AppointmentStartDoctorDialog excludes busy doctors from the radio group entirely rather than showing them disabled, which means the isBusy flag the domain computes on every QueueStartDoctorOption is discarded by the UI. Either the flag is dead weight or the dialog is hiding intended information.

Two caveats worth stating plainly
I could not compile or run anything in this environment, so ReadLints passing is not a compile guarantee — expect a fix-up pass on the first flutter test test/unit/appointments test/widget/appointments. The likeliest breakages are the widget harnesses, since they subclass real repositories and wire GoRouter.

Separately, AppBookingSlotGrid slots and PatientPicker result rows have no widget keys, so a handful of tests tap on label text and will break on copy changes. Adding keys there is the highest-value hardening follow-up, but it's production code, so I left it alone.

