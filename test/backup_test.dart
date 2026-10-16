import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:broker_demo_app/data/diary_storage.dart';
import 'package:broker_demo_app/models/models.dart';
import 'package:broker_demo_app/services/backup_service.dart';
import 'package:broker_demo_app/state/app_state.dart';
import 'package:broker_demo_app/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Backup → new phone → restore, end to end on real files.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('diary_backup_test_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<(AppState, BackupService)> phone(String name) async {
    final storage =
        await FileDiaryStorage.open(base: Directory(p.join(root.path, name)));
    final settings = SettingsState(storage);
    await settings.load();
    final app = AppState(storage, saveDelay: Duration.zero);
    await app.bootstrap();
    final tmp = Directory(p.join(root.path, name, 'tmp'));
    final safety = Directory(p.join(root.path, name, 'safety'));
    return (
      app,
      BackupService(app, settings,
          tempDir: () async => tmp..createSync(recursive: true),
          safetyDir: () async => safety),
    );
  }

  test('a backup restores the whole diary, photos included, on a new phone',
      () async {
    final (oldPhone, oldBackup) = await phone('old');
    oldPhone.saveProfile(BrokerProfile(name: 'Aarav Mehta'));
    await File(p.join(oldPhone.storage.attachmentsDir!.path, 'flat.jpg'))
        .writeAsBytes([1, 2, 3, 4]);
    oldPhone.addProperty(
        Property(id: 'pr-1', title: '3 BHK Baner', photo: 'flat.jpg'));
    oldPhone.addLead(Lead(id: 'ld-1', name: 'Rohit', phone: '9821034567'));

    final file = await oldBackup.createBackupFile();
    final bytes = await file.readAsBytes();

    final (newPhone, newBackup) = await phone('new');
    final summary = newBackup.inspect(bytes);
    expect(summary.brokerName, 'Aarav Mehta');
    expect(summary.count(Collections.leads), 1);
    expect(summary.attachments, 1);

    await newBackup.restore(bytes);
    expect(newPhone.profile?.name, 'Aarav Mehta');
    expect(newPhone.leads.single.name, 'Rohit');
    expect(newPhone.contacts.single.name, 'Rohit');
    expect(newPhone.properties.single.photo, 'flat.jpg');
    final photo =
        File(p.join(newPhone.storage.attachmentsDir!.path, 'flat.jpg'));
    expect(await photo.readAsBytes(), [1, 2, 3, 4]);
  });

  test('restoring over a diary keeps a safety copy of it first', () async {
    final (source, sourceBackup) = await phone('source');
    source.saveProfile(BrokerProfile(name: 'From backup'));
    final bytes = await (await sourceBackup.createBackupFile()).readAsBytes();

    final (target, targetBackup) = await phone('target');
    target.saveProfile(BrokerProfile(name: 'Was here first'));
    target.addLead(Lead(id: 'mine', name: 'Mine', phone: '9000000001'));
    await targetBackup.restore(bytes);

    expect(target.profile?.name, 'From backup');
    expect(target.leads, isEmpty);
    final copies = await targetBackup.safetyCopies();
    expect(copies, hasLength(1));

    // …and the safety copy brings the old diary back.
    await targetBackup.restore(await copies.single.readAsBytes());
    expect(target.profile?.name, 'Was here first');
    expect(target.leads.single.id, 'mine');
  });

  test('repeated backups leave only the newest zip in the temp folder',
      () async {
    final (app, backup) = await phone('p');
    app.saveProfile(BrokerProfile(name: 'Me'));
    final first = await backup.createBackupFile();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final second = await backup.createBackupFile();
    expect(await first.exists(), isFalse);
    expect(await second.exists(), isTrue);
    final zips = first.parent
        .listSync()
        .where((e) => e.path.endsWith('.zip'))
        .toList();
    expect(zips, hasLength(1));
  });

  test('a file that is not a backup is refused without changing anything',
      () async {
    final (app, backup) = await phone('p');
    app.saveProfile(BrokerProfile(name: 'Me'));
    app.addLead(Lead(id: 'x', name: 'X', phone: '9000000001'));

    expect(() => backup.inspect(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<BackupException>()));

    final otherZip = ZipEncoder().encode(Archive()
      ..addFile(ArchiveFile.string('hello.txt', 'not a diary')));
    await expectLater(backup.restore(Uint8List.fromList(otherZip)),
        throwsA(isA<BackupException>()));
    expect(app.leads.single.id, 'x');
  });

  test('a backup from a newer app version is refused', () async {
    final (_, backup) = await phone('p');
    final zip = ZipEncoder().encode(Archive()
      ..addFile(ArchiveFile.string('manifest.json',
          '{"app": "${BackupService.marker}", "format": 99}')));
    expect(() => backup.inspect(Uint8List.fromList(zip)),
        throwsA(isA<BackupException>()
            .having((e) => e.message, 'message', contains('newer'))));
  });

  test('a damaged data file is caught before anything is overwritten',
      () async {
    final (app, backup) = await phone('p');
    app.saveProfile(BrokerProfile(name: 'Me'));
    final zip = ZipEncoder().encode(Archive()
      ..addFile(ArchiveFile.string('manifest.json',
          '{"app": "${BackupService.marker}", "format": 1}'))
      ..addFile(ArchiveFile.string('data/profile.json', '{"profile": {"name": "B"}}'))
      ..addFile(ArchiveFile.string('data/leads.json', '{"items": [')));
    await expectLater(backup.restore(Uint8List.fromList(zip)),
        throwsA(isA<BackupException>()));
    expect(app.profile?.name, 'Me');
  });
}
