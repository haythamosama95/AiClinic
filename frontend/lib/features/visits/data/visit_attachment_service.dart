import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart' show supabaseClientProvider;
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';

/// Client-side validation failure before storage upload (V1-5).
class VisitAttachmentValidationException implements Exception {
  const VisitAttachmentValidationException(this.message, {required this.errorCode});

  final String message;
  final String errorCode;

  @override
  String toString() => message;
}

/// Bytes picked for upload (tests inject this without platform file picker).
class VisitAttachmentPickInput {
  const VisitAttachmentPickInput({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;
}

/// Storage upload + register/download for visit attachments (V1-5).
class VisitAttachmentService {
  VisitAttachmentService(this._client, this._visitRepository);

  static const bucketName = 'visit-attachments';
  static const maxBytes = 26214400;

  final SupabaseClient _client;
  final VisitRepository _visitRepository;
  final Random _random = Random.secure();

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

  /// Resolves allowed file type from filename extension.
  static VisitAttachmentFileType? inferFileTypeFromFilename(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot >= filename.length - 1) {
      return null;
    }
    final ext = filename.substring(dot + 1).trim().toLowerCase();
    return switch (ext) {
      'pdf' => VisitAttachmentFileType.pdf,
      'docx' => VisitAttachmentFileType.docx,
      'jpg' || 'jpeg' => VisitAttachmentFileType.jpeg,
      'png' => VisitAttachmentFileType.png,
      _ => null,
    };
  }

  /// Validates pick before upload; throws [VisitAttachmentValidationException] on failure.
  static void validatePick(VisitAttachmentPickInput pick) {
    if (pick.bytes.isEmpty) {
      throw const VisitAttachmentValidationException('The selected file is empty.', errorCode: 'INVALID_INPUT');
    }
    if (pick.bytes.length > maxBytes) {
      throw const VisitAttachmentValidationException(
        'Each attachment must be 25 MB or smaller.',
        errorCode: 'FILE_TOO_LARGE',
      );
    }
    if (inferFileTypeFromFilename(pick.filename) == null) {
      throw const VisitAttachmentValidationException(
        'Only PDF, Word (DOCX), JPEG, and PNG files are allowed.',
        errorCode: 'INVALID_FILE_TYPE',
      );
    }
  }

  static String contentTypeFor(VisitAttachmentFileType fileType) {
    return switch (fileType) {
      VisitAttachmentFileType.pdf => 'application/pdf',
      VisitAttachmentFileType.docx => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      VisitAttachmentFileType.jpeg => 'image/jpeg',
      VisitAttachmentFileType.png => 'image/png',
    };
  }

  /// Upload bytes to storage (caller supplies [path] from [buildStoragePath]).
  Future<void> uploadToStorage({required String path, required Uint8List bytes, required String contentType}) async {
    await _client.storage
        .from(bucketName)
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: false));
  }

  /// Uploads to storage then registers metadata via RPC.
  Future<String> uploadAndRegister({
    required String organizationId,
    required String branchId,
    required String visitId,
    required VisitAttachmentPickInput pick,
    String? label,
  }) async {
    validatePick(pick);
    final fileType = inferFileTypeFromFilename(pick.filename)!;
    final uniqueId = _newStorageUniqueId();
    final path = buildStoragePath(
      organizationId: organizationId,
      branchId: branchId,
      visitId: visitId,
      originalFilename: pick.filename,
      uniqueId: uniqueId,
    );

    await uploadToStorage(path: path, bytes: pick.bytes, contentType: contentTypeFor(fileType));

    try {
      return await registerVisitAttachment(
        visitId: visitId,
        filePath: path,
        fileType: fileType,
        sizeBytes: pick.bytes.length,
        label: label,
      );
    } catch (error) {
      try {
        await _client.storage.from(bucketName).remove([path]);
      } catch (_) {
        // Best-effort cleanup when register fails after storage upload.
      }
      rethrow;
    }
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

  /// Downloads attachment bytes after [getVisitAttachmentDownload] authorizes access.
  ///
  /// Uses authenticated storage download when [VisitAttachmentDownloadResult.filePath] is set
  /// (reliable on desktop). Falls back to HTTP only for absolute signed URLs.
  Future<Uint8List> downloadAttachmentBytes(VisitAttachmentDownloadResult download, {http.Client? client}) async {
    final path = download.filePath?.trim();
    if (path != null && path.isNotEmpty) {
      return _client.storage.from(bucketName).download(path);
    }
    return downloadBytesFromSignedUrl(download.signedUrl, client: client);
  }

  /// Fetches attachment bytes from an absolute signed storage URL.
  Future<Uint8List> downloadBytesFromSignedUrl(String signedUrl, {http.Client? client}) async {
    final uri = Uri.tryParse(signedUrl);
    if (uri == null || !uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw StateError('Download URL was invalid.');
    }
    final response = client == null ? await http.get(uri) : await client.get(uri);
    if (response.statusCode != 200) {
      throw StateError('Could not download the file (${response.statusCode}).');
    }
    return response.bodyBytes;
  }

  String _sanitizeFilename(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'attachment';
    }
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  }

  String _newStorageUniqueId() {
    String hex(int count) => List.generate(count, (_) => _random.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}';
  }
}

final visitAttachmentServiceProvider = Provider<VisitAttachmentService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final visits = ref.watch(visitRepositoryProvider);
  return VisitAttachmentService(client, visits);
});
