import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_pick.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';

/// Attachment staging state for a visit encounter.
@immutable
class VisitAttachmentsState {
  const VisitAttachmentsState({
    this.pendingAttachments = const [],
    this.deletedAttachmentIds = const {},
  });

  final List<PendingVisitAttachment> pendingAttachments;
  final Set<String> deletedAttachmentIds;

  bool get hasPendingDraft => pendingAttachments.isNotEmpty || deletedAttachmentIds.isNotEmpty;

  VisitEncounterDraft toEncounterDraftSlice() {
    return VisitEncounterDraft(
      pendingAttachments: pendingAttachments,
      deletedAttachmentIds: deletedAttachmentIds,
    );
  }

  VisitDetail applyTo(VisitDetail visit) => toEncounterDraftSlice().applyTo(visit);

  VisitAttachmentsState copyWith({
    List<PendingVisitAttachment>? pendingAttachments,
    Set<String>? deletedAttachmentIds,
  }) {
    return VisitAttachmentsState(
      pendingAttachments: pendingAttachments ?? this.pendingAttachments,
      deletedAttachmentIds: deletedAttachmentIds ?? this.deletedAttachmentIds,
    );
  }

  static VisitAttachmentsState fromEncounterDraft(VisitEncounterDraft draft) {
    return VisitAttachmentsState(
      pendingAttachments: draft.pendingAttachments,
      deletedAttachmentIds: draft.deletedAttachmentIds,
    );
  }
}

final visitAttachmentsProvider = NotifierProvider.family<VisitAttachmentsNotifier, VisitAttachmentsState, String>(
  VisitAttachmentsNotifier.new,
);

class VisitAttachmentsNotifier extends Notifier<VisitAttachmentsState> {
  VisitAttachmentsNotifier(this._visitId);

  final String _visitId;

  @override
  VisitAttachmentsState build() => const VisitAttachmentsState();

  void replaceFromEncounterDraft(VisitEncounterDraft draft) {
    state = VisitAttachmentsState.fromEncounterDraft(draft);
  }

  void clearDraft() {
    state = const VisitAttachmentsState();
  }

  void _apply(VisitAttachmentsState next) {
    state = next;
  }

  void stageAttachment({
    required VisitAttachmentPick pick,
    required String label,
    required String uploadedBy,
    String? uploadedByName,
  }) {
    final fileType = VisitAttachmentService.inferFileTypeFromFilename(pick.filename);
    if (fileType == null) return;
    final pending = PendingVisitAttachment(
      id: newVisitDraftId(),
      pick: pick,
      label: label,
      fileType: fileType,
      uploadedBy: uploadedBy,
      uploadedByName: uploadedByName,
    );
    _apply(state.copyWith(pendingAttachments: [...state.pendingAttachments, pending]));
  }

  void stageDeleteAttachment(String attachmentId) {
    if (isVisitDraftId(attachmentId)) {
      _apply(
        state.copyWith(
          pendingAttachments: state.pendingAttachments.where((item) => item.id != attachmentId).toList(),
        ),
      );
      return;
    }
    _apply(state.copyWith(deletedAttachmentIds: {...state.deletedAttachmentIds, attachmentId}));
  }
}
