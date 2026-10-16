import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/models.dart';

/// A file now sitting in the diary's attachments folder.
class StoredAttachment {
  const StoredAttachment({
    required this.file,
    required this.displayName,
    required this.sizeKb,
    required this.kind,
  });

  /// Name inside the attachments folder — what records store.
  final String file;
  final String displayName;
  final int sizeKb;
  final DocumentKind kind;
}

/// Copies photos and documents into the app's private folder, so they stay
/// with the diary (and its backups) even if the original is deleted from the
/// gallery or Downloads.
class AttachmentService {
  AttachmentService._();

  static final instance = AttachmentService._();

  /// Set once at start-up from the storage. Null in tests.
  Directory? dir;

  static const _uuid = Uuid();

  /// Resolves a stored name to the file on disk, or null if it is gone.
  File? fileFor(String? name) {
    final d = dir;
    if (d == null || name == null || name.isEmpty) return null;
    final f = File(p.join(d.path, p.basename(name)));
    return f.existsSync() ? f : null;
  }

  /// Camera or gallery. Photos are scaled down — a 12 MP original is ~5 MB,
  /// this keeps a property photo around 200–400 KB.
  Future<StoredAttachment?> pickPhoto({required bool camera}) async {
    final picked = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (picked == null) return null;
    final ext = p.extension(picked.name).isEmpty ? '.jpg' : p.extension(picked.name);
    return _store(
      read: picked.openRead(),
      originalName: picked.name,
      ext: ext,
      kind: DocumentKind.photo,
    );
  }

  /// Any file — PDF, photo, Word document — from the phone's file picker.
  Future<StoredAttachment?> pickDocument() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null) return null;
    final ext = p.extension(picked.name);
    return _store(
      read: picked.readAsByteStream(),
      originalName: picked.name,
      ext: ext,
      kind: guessKind(picked.name),
    );
  }

  Future<StoredAttachment> _store({
    required Stream<List<int>> read,
    required String originalName,
    required String ext,
    required DocumentKind kind,
  }) async {
    final d = dir;
    if (d == null) throw StateError('Attachments folder is not available');
    await d.create(recursive: true);
    final stored = '${_uuid.v4()}${ext.toLowerCase()}';
    final target = File(p.join(d.path, stored));
    final sink = target.openWrite();
    try {
      await sink.addStream(read);
    } finally {
      await sink.close();
    }
    final bytes = await target.length();
    return StoredAttachment(
      file: stored,
      displayName: originalName,
      sizeKb: (bytes / 1024).ceil(),
      kind: kind,
    );
  }

  /// Opens the file in whichever app the phone uses for its type.
  Future<String?> open(String? name) async {
    final f = fileFor(name);
    if (f == null) return 'The file is no longer on this phone.';
    final result = await OpenFilex.open(f.path);
    return result.type == ResultType.done ? null : result.message;
  }

  static DocumentKind guessKind(String name) {
    final lower = name.toLowerCase();
    final ext = p.extension(lower);
    if (const {'.jpg', '.jpeg', '.png', '.heic', '.webp'}.contains(ext)) {
      return DocumentKind.photo;
    }
    if (lower.contains('agreement') || lower.contains('deed')) {
      return DocumentKind.agreement;
    }
    if (lower.contains('receipt') || lower.contains('invoice')) {
      return DocumentKind.receipt;
    }
    if (lower.contains('aadhaar') ||
        lower.contains('aadhar') ||
        lower.contains('pan') ||
        lower.contains('passport') ||
        lower.contains('id')) {
      return DocumentKind.idProof;
    }
    return DocumentKind.other;
  }
}
