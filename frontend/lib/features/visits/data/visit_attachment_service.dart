import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart' show supabaseClientProvider;
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';

/// Storage upload + register/download for visit attachments (V1-5).
class VisitAttachmentService {
  VisitAttachmentService(this._client, this._visitRepository);

  static const bucketName = 'visit-attachments';
  static const maxBytes = 26214400;

  final SupabaseClient _client;
  final VisitRepository _visitRepository;

  /// `{organizationId}/{branchId}/{visitId}/{uuid}_{sanitizedName}`
  String buildStoragePath({
    required String organizationId,
    required String branchId,
    required String visitId,
    required String originalFilename,
    required String uniqueId,
  }) {
    final sanitized = _sanitizeFilename(originalFilename);
    return '${organizationId.trim()}/${branchId.trim()}/${visitId.trim()}/${uniqueId.trim()}_$sanitized';
  }

  /// Upload bytes to storage (caller supplies [path] from [buildStoragePath]).
  Future<void> uploadToStorage({required String path, required Uint8List bytes, required String contentType}) async {
    await _client.storage
        .from(bucketName)
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: false));
  }

  Future<String> registerVisitAttachment({
    required String visitId,
    required String filePath,
    required VisitAttachmentFileType fileType,
    required int sizeBytes,
    String? label,
  }) {
    return _visitRepository.registerVisitAttachment(
      visitId: visitId,
      filePath: filePath,
      fileType: fileType.wireValue,
      sizeBytes: sizeBytes,
      label: label,
    );
  }

  Future<VisitAttachmentDownloadResult> getVisitAttachmentDownload({required String attachmentId}) {
    return _visitRepository.getVisitAttachmentDownload(attachmentId: attachmentId);
  }

  String _sanitizeFilename(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'attachment';
    }
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  }
}

final visitAttachmentServiceProvider = Provider<VisitAttachmentService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final visits = ref.watch(visitRepositoryProvider);
  return VisitAttachmentService(client, visits);
});
