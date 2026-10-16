import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../state/app_state.dart';
import '../state/settings_state.dart';

class BackupOutcome {
  const BackupOutcome(this.ok, this.message);

  final bool ok;
  final String message;
}

/// What a backup file holds, read before anything is overwritten.
class BackupSummary {
  const BackupSummary({
    required this.createdAt,
    required this.brokerName,
    required this.counts,
    required this.attachments,
  });

  final DateTime? createdAt;
  final String brokerName;
  final Map<String, int> counts;
  final int attachments;

  int count(String collection) => counts[collection] ?? 0;
}

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The diary's safety net. There is no server, so if the phone is lost or
/// the app is uninstalled, a backup file is the only way back.
///
/// A backup is one `.zip`:
///
/// ```
/// manifest.json            what this is, when, how many of each record
/// data/<collection>.json   the same files the app keeps on the phone
/// attachments/<file>       photos and documents
/// ```
///
/// The broker sends it wherever they like — WhatsApp to themselves, Google
/// Drive, a pen drive — using the phone's own share sheet. This app never
/// touches the network.
class BackupService {
  BackupService(
    this.app,
    this.settings, {
    Future<Directory> Function()? tempDir,
    Future<Directory> Function()? safetyDir,
  })  : _tempDir = tempDir ?? getTemporaryDirectory,
        _safetyDirFn = safetyDir ?? _defaultSafetyDir;

  final AppState app;
  final SettingsState settings;
  final Future<Directory> Function() _tempDir;
  final Future<Directory> Function() _safetyDirFn;

  static const marker = 'broker-diary-backup';
  static const format = 1;
  static const _keepSafetyCopies = 3;

  // --- create ---------------------------------------------------------------

  /// Writes a backup zip into the app's temporary folder and returns it.
  Future<File> createBackupFile() async {
    await app.flush();
    final tmp = await _tempDir();
    // Only the newest backup is kept here — once shared or saved, the copy
    // in the temp folder has done its job. Without this, every weekly
    // backup would leave a full-size zip behind.
    await _deleteOldBackups(tmp);
    final path = p.join(tmp.path, 'BrokerDiary_backup_${_stamp()}.zip');
    await _writeZip(path);
    return File(path);
  }

  static Future<void> _deleteOldBackups(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final e in dir.list()) {
      final name = p.basename(e.path);
      if (e is File &&
          name.startsWith('BrokerDiary_backup_') &&
          name.endsWith('.zip')) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _writeZip(String path) async {
    final dataDir = app.storage.dataDir;
    final attachmentsDir = app.storage.attachmentsDir;
    if (dataDir == null) {
      throw const BackupException('Backups need the phone\'s storage.');
    }

    final counts = <String, int>{
      Collections.leads: app.leads.length,
      Collections.contacts: app.contacts.length,
      Collections.properties: app.properties.length,
      Collections.visits: app.visits.length,
      Collections.tasks: app.tasks.length,
      Collections.deals: app.deals.length,
      Collections.payments: app.payments.length,
      Collections.documents: app.documents.length,
    };
    final files = app.referencedFiles.toList();
    final manifest = {
      'app': marker,
      'format': format,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'broker': app.profile?.name ?? '',
      'counts': counts,
      'attachments': files.length,
    };

    // Zipping photos is CPU work; keep it off the UI thread.
    await Isolate.run(() async {
      final zip = ZipFileEncoder()..create(path);
      zip.addArchiveFile(ArchiveFile.string(
          'manifest.json', const JsonEncoder.withIndent('  ').convert(manifest)));
      for (final name in Collections.all) {
        final f = File(p.join(dataDir.path, '$name.json'));
        if (await f.exists()) await zip.addFile(f, 'data/$name.json');
      }
      if (attachmentsDir != null) {
        for (final name in files) {
          final f = File(p.join(attachmentsDir.path, p.basename(name)));
          if (await f.exists()) {
            await zip.addFile(f, 'attachments/${p.basename(name)}');
          }
        }
      }
      await zip.close();
    });
  }

  /// Opens the share sheet with a fresh backup (WhatsApp, Drive, email…).
  Future<BackupOutcome> share() async {
    try {
      final file = await createBackupFile();
      final name = p.basename(file.path);
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/zip', name: name)],
        fileNameOverrides: [name],
        subject: 'Broker Diary backup',
        text: 'Broker Diary backup — keep this file safe. '
            'Open Broker Diary › Settings › Restore to bring it back.',
      ));
      if (result.status == ShareResultStatus.dismissed) {
        return const BackupOutcome(false, 'Backup not sent');
      }
      await settings.markBackedUp();
      return BackupOutcome(true, 'Backup ready: $name');
    } catch (e) {
      return BackupOutcome(false, 'Backup failed: $e');
    }
  }

  /// Lets the broker pick a folder on the phone (e.g. Downloads) to keep
  /// the backup in.
  Future<BackupOutcome> saveToPhone() async {
    try {
      final file = await createBackupFile();
      final uri = await FilePicker.saveFile(
        fileName: p.basename(file.path),
        bytes: await file.readAsBytes(),
        mimeType: 'application/zip',
        dialogTitle: 'Save backup',
      );
      if (uri == null) return const BackupOutcome(false, 'Backup not saved');
      await settings.markBackedUp();
      return BackupOutcome(true, 'Backup saved: ${p.basename(file.path)}');
    } catch (e) {
      return BackupOutcome(false, 'Backup failed: $e');
    }
  }

  // --- restore --------------------------------------------------------------

  /// Asks the broker to choose a backup file. Returns its bytes, or null if
  /// they backed out.
  Future<Uint8List?> pickBackup() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null) return null;
    return picked.readAsBytes();
  }

  /// Checks a backup and says what's in it, without changing anything.
  BackupSummary inspect(Uint8List bytes) {
    final archive = _decode(bytes);
    final manifest = _manifest(archive);
    final counts = <String, int>{};
    final rawCounts = manifest['counts'];
    if (rawCounts is Map) {
      rawCounts.forEach((k, v) {
        if (v is int) counts[k.toString()] = v;
      });
    }
    return BackupSummary(
      createdAt:
          DateTime.tryParse(manifest['createdAt']?.toString() ?? '')?.toLocal(),
      brokerName: manifest['broker']?.toString() ?? '',
      counts: counts,
      attachments: archive.files
          .where((f) => f.isFile && f.name.startsWith('attachments/'))
          .length,
    );
  }

  /// Replaces the diary on this phone with the backup's contents.
  ///
  /// Before touching anything, the current diary is itself saved to a
  /// safety copy in the app's folder, so a restore of the wrong file can be
  /// undone from Settings.
  Future<void> restore(Uint8List bytes) async {
    // Nothing unsaved may land on top of the restored files afterwards.
    await app.flush();
    final archive = _decode(bytes);
    _manifest(archive); // validates

    // Parse every data file first: a damaged backup must fail *before* we
    // overwrite anything.
    final collections = <String, Map<String, dynamic>>{};
    for (final name in Collections.all) {
      final entry = archive.findFile('data/$name.json');
      if (entry == null) continue;
      try {
        final decoded = jsonDecode(utf8.decode(entry.content));
        if (decoded is! Map) throw const FormatException();
        collections[name] = Map<String, dynamic>.from(decoded);
      } on FormatException {
        throw BackupException('The backup is damaged ($name could not be read).');
      }
    }
    if (!collections.containsKey(Collections.profile)) {
      throw const BackupException('This backup has no diary in it.');
    }

    if (!app.isEmpty) await _writeSafetyCopy();

    final storage = app.storage;
    for (final name in Collections.all) {
      await storage.write(
          name, collections[name] ?? {'version': 1, 'items': <Object>[]});
    }

    final attachmentsDir = storage.attachmentsDir;
    if (attachmentsDir != null) {
      await attachmentsDir.create(recursive: true);
      for (final f in archive.files) {
        if (!f.isFile || !f.name.startsWith('attachments/')) continue;
        final name = p.basename(f.name);
        if (name.isEmpty || name.startsWith('.')) continue;
        await File(p.join(attachmentsDir.path, name))
            .writeAsBytes(f.content, flush: true);
      }
    }

    await app.bootstrap();
    await settings.markBackedUp();
  }

  /// Saved automatically before a restore. Newest first.
  Future<List<File>> safetyCopies() async {
    final dir = await _safetyDir();
    if (!await dir.exists()) return const [];
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.zip'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> _writeSafetyCopy() async {
    final dir = await _safetyDir();
    await dir.create(recursive: true);
    await _writeZip(p.join(dir.path, 'before_restore_${_stamp()}.zip'));
    final copies = await safetyCopies();
    for (final old in copies.skip(_keepSafetyCopies)) {
      try {
        await old.delete();
      } catch (_) {}
    }
  }

  Future<Directory> _safetyDir() => _safetyDirFn();

  static Future<Directory> _defaultSafetyDir() async {
    final docs = await getApplicationDocumentsDirectory();
    // Outside diary/ so "erase all data" and restores don't remove it.
    return Directory(p.join(docs.path, 'safety_copies'));
  }

  static Archive _decode(Uint8List bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const BackupException(
          'That file is not a Broker Diary backup (it is not a zip file).');
    }
  }

  static Map<String, dynamic> _manifest(Archive archive) {
    final entry = archive.findFile('manifest.json');
    if (entry == null) {
      throw const BackupException('That file is not a Broker Diary backup.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(entry.content));
    } on FormatException {
      throw const BackupException('The backup is damaged.');
    }
    if (decoded is! Map || decoded['app'] != marker) {
      throw const BackupException('That file is not a Broker Diary backup.');
    }
    final version = decoded['format'];
    if (version is! int || version > format) {
      throw const BackupException(
          'This backup was made by a newer version of Broker Diary. '
          'Update the app, then try again.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }
}
