import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the diary keeps its data: one JSON document per collection
/// (`leads`, `contacts`, `settings`, …) plus a folder of attached files.
///
/// Everything is on the phone. Nothing here can reach a network.
abstract class DiaryStorage {
  /// Reads a collection, or null when it has never been written.
  Future<Map<String, dynamic>?> read(String name);

  /// Replaces a collection on disk. Never leaves a half-written file behind.
  Future<void> write(String name, Map<String, dynamic> json);

  /// Removes every collection and attachment — "erase all data".
  Future<void> eraseAll();

  /// Folder holding photos and documents, or null where there is no file
  /// system (widget tests).
  Directory? get attachmentsDir;

  /// The folder that holds the JSON files, for backups.
  Directory? get dataDir;
}

/// The real thing: files in the app's private documents folder.
///
/// Every write goes `name.json.tmp` → (old file kept as `name.json.bak`) →
/// `name.json`. A rename is atomic, so if the phone dies mid-save the diary
/// still opens with either the new or the previous version — never a
/// truncated file. [read] falls back through those three in order.
class FileDiaryStorage implements DiaryStorage {
  FileDiaryStorage._(this.root);

  /// The `diary/` folder inside the app's documents directory.
  final Directory root;

  /// Encoding over this many bytes is moved off the UI thread.
  static const _isolateThreshold = 256 * 1024;

  static Future<FileDiaryStorage> open({Directory? base}) async {
    final docs = base ?? await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'diary'));
    await Directory(p.join(root.path, 'attachments')).create(recursive: true);
    return FileDiaryStorage._(root);
  }

  @override
  Directory get attachmentsDir => Directory(p.join(root.path, 'attachments'));

  @override
  Directory get dataDir => root;

  File _file(String name, [String suffix = '']) =>
      File(p.join(root.path, '$name.json$suffix'));

  // One write per collection at a time; a second save of the same file waits
  // for the first, so two quick edits can't interleave their renames.
  final Map<String, Future<void>> _pending = {};

  @override
  Future<Map<String, dynamic>?> read(String name) async {
    for (final candidate in [_file(name), _file(name, '.tmp'), _file(name, '.bak')]) {
      if (!await candidate.exists()) continue;
      try {
        final text = await candidate.readAsString();
        final decoded = text.length > _isolateThreshold
            ? await Isolate.run(() => jsonDecode(text))
            : jsonDecode(text);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        // Damaged — try the next copy.
      } on FileSystemException {
        // Unreadable — try the next copy.
      }
    }
    return null;
  }

  @override
  Future<void> write(String name, Map<String, dynamic> json) {
    final previous = _pending[name] ?? Future<void>.value();
    final next = previous.then((_) => _writeNow(name, json));
    _pending[name] = next;
    return next.whenComplete(() {
      if (identical(_pending[name], next)) _pending.remove(name);
    });
  }

  Future<void> _writeNow(String name, Map<String, dynamic> json) async {
    final text = await _encode(json);
    final target = _file(name);
    final tmp = _file(name, '.tmp');
    final bak = _file(name, '.bak');

    await tmp.writeAsString(text, flush: true);
    if (await target.exists()) {
      if (await bak.exists()) await bak.delete();
      await target.rename(bak.path);
    }
    await tmp.rename(target.path);
  }

  static Future<String> _encode(Map<String, dynamic> json) async {
    // A rough size guess without encoding twice: big lists go to an isolate.
    final items = json['items'];
    if (items is List && items.length > 1500) {
      return Isolate.run(() => jsonEncode(json));
    }
    return jsonEncode(json);
  }

  @override
  Future<void> eraseAll() async {
    await Future.wait(_pending.values);
    if (await root.exists()) await root.delete(recursive: true);
    await attachmentsDir.create(recursive: true);
  }
}

/// Keeps everything in memory. Used by tests, and as a fallback if the
/// documents folder can't be opened at all.
class MemoryDiaryStorage implements DiaryStorage {
  MemoryDiaryStorage([Map<String, Map<String, dynamic>>? initial])
      : _data = {...?initial};

  final Map<String, Map<String, dynamic>> _data;

  /// Number of writes, so tests can check that saves are batched.
  int writeCount = 0;

  Map<String, Map<String, dynamic>> get snapshot => Map.unmodifiable(_data);

  @override
  Future<Map<String, dynamic>?> read(String name) async {
    final value = _data[name];
    // Round-trip through JSON so tests catch anything that won't serialise.
    return value == null
        ? null
        : jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }

  @override
  Future<void> write(String name, Map<String, dynamic> json) async {
    writeCount++;
    _data[name] = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
  }

  @override
  Future<void> eraseAll() async => _data.clear();

  @override
  Directory? get attachmentsDir => null;

  @override
  Directory? get dataDir => null;
}
