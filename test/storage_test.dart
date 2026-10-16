import 'dart:io';

import 'package:broker_demo_app/data/diary_storage.dart';
import 'package:broker_demo_app/models/models.dart';
import 'package:broker_demo_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The diary's promise is "what you write stays written". These tests hold
/// it to that against real files in a temp folder.
void main() {
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('diary_test_');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  group('FileDiaryStorage', () {
    test('writes and reads back a collection', () async {
      final storage = await FileDiaryStorage.open(base: base);
      await storage.write('leads', {
        'version': 1,
        'items': [
          {'id': 'a', 'name': 'Rohit'},
        ],
      });
      final back = await storage.read('leads');
      expect(back?['items'], [
        {'id': 'a', 'name': 'Rohit'},
      ]);
    });

    test('returns null for a collection never written', () async {
      final storage = await FileDiaryStorage.open(base: base);
      expect(await storage.read('nothing'), isNull);
    });

    test('keeps the previous version as .bak', () async {
      final storage = await FileDiaryStorage.open(base: base);
      await storage.write('leads', {'version': 1, 'n': 1});
      await storage.write('leads', {'version': 1, 'n': 2});
      final bak = File(p.join(storage.root.path, 'leads.json.bak'));
      expect(await bak.exists(), isTrue);
      expect(await bak.readAsString(), contains('"n":1'));
      expect((await storage.read('leads'))?['n'], 2);
    });

    test('falls back to the backup copy when the main file is damaged',
        () async {
      final storage = await FileDiaryStorage.open(base: base);
      await storage.write('leads', {'version': 1, 'n': 1});
      await storage.write('leads', {'version': 1, 'n': 2});
      // Simulate a file cut short by the battery dying mid-write.
      await File(p.join(storage.root.path, 'leads.json'))
          .writeAsString('{"version": 1, "n": ');
      expect((await storage.read('leads'))?['n'], 1);
    });

    test('a leftover .tmp from an interrupted save is still readable',
        () async {
      final storage = await FileDiaryStorage.open(base: base);
      // Crash between "move old to .bak" and "move .tmp into place".
      await File(p.join(storage.root.path, 'leads.json.tmp'))
          .writeAsString('{"version": 1, "n": 7}');
      expect((await storage.read('leads'))?['n'], 7);
    });

    test('parallel writes to one collection land in order', () async {
      final storage = await FileDiaryStorage.open(base: base);
      await Future.wait([
        for (var i = 0; i < 20; i++) storage.write('leads', {'n': i}),
      ]);
      expect((await storage.read('leads'))?['n'], 19);
    });

    test('eraseAll removes everything but leaves a usable folder', () async {
      final storage = await FileDiaryStorage.open(base: base);
      await storage.write('leads', {'n': 1});
      await File(p.join(storage.attachmentsDir.path, 'x.jpg'))
          .writeAsString('img');
      await storage.eraseAll();
      expect(await storage.read('leads'), isNull);
      expect(await storage.attachmentsDir.exists(), isTrue);
      expect(storage.attachmentsDir.listSync(), isEmpty);
    });
  });

  group('AppState persistence', () {
    Future<AppState> open(DiaryStorage storage) async {
      final s = AppState(storage, saveDelay: Duration.zero);
      await s.bootstrap();
      return s;
    }

    test('a fresh phone starts with no profile and an empty diary', () async {
      final state = await open(MemoryDiaryStorage());
      expect(state.isSetUp, isFalse);
      expect(state.isEmpty, isTrue);
      expect(state.loadError, isNull);
    });

    test('every kind of record survives a restart', () async {
      final storage = await FileDiaryStorage.open(base: base);
      final first = await open(storage);
      first.saveProfile(BrokerProfile(name: 'Aarav Mehta', agency: 'Mehta'));
      final lead = first.addLead(Lead(
        id: first.nextId('ld'),
        name: 'Rohit Agarwal',
        phone: '98210 34567',
        budgetMax: 12000000,
        preferredLocation: 'Baner',
        nextFollowUpAt: DateTime(2030, 1, 2, 10, 30),
      ));
      final property = first.addProperty(Property(
        id: first.nextId('pr'),
        title: '3 BHK, Baner',
        price: 11500000,
        features: ['Parking', 'Gym'],
        photo: 'abc.jpg',
      ));
      first.addVisit(SiteVisit(
        id: first.nextId('vs'),
        propertyId: property.id,
        leadId: lead.id,
        scheduledAt: DateTime(2030, 1, 3, 11),
      ));
      final deal = first.addDeal(Deal(
        id: first.nextId('dl'),
        title: 'Rohit · 3 BHK',
        agreedValue: 11000000,
        milestones: [Milestone(label: 'Token', done: true)],
      ));
      first.addPayment(PaymentRecord(
          id: first.nextId('pm'),
          dealId: deal.id,
          amount: 110000,
          dueDate: DateTime(2030, 2, 1)));
      first.logInteraction(
          first.contact(lead.contactId)!, 'Call', 'Wants east facing');
      await first.flush();

      final second = await open(storage);
      expect(second.profile?.name, 'Aarav Mehta');
      expect(second.leads.single.name, 'Rohit Agarwal');
      expect(second.leads.single.nextFollowUpAt, DateTime(2030, 1, 2, 10, 30));
      expect(second.properties.single.features, ['Parking', 'Gym']);
      expect(second.properties.single.photo, 'abc.jpg');
      expect(second.visits.single.leadId, lead.id);
      // addVisit also creates the "confirm visit" follow-up.
      expect(second.tasks, hasLength(1));
      expect(second.deals.single.milestones.single.done, isTrue);
      expect(second.payments.single.amount, 110000);
      expect(second.contacts.single.interactions.single.note,
          'Wants east facing');
      expect(second.activities, isNotEmpty);
    });

    test('edits made in place are saved by update*', () async {
      final storage = MemoryDiaryStorage();
      final first = await open(storage);
      final lead = first.addLead(
          Lead(id: first.nextId('ld'), name: 'A', phone: '9000000001'));
      lead.name = 'A. Sharma';
      first.updateLead(lead);
      await first.flush();

      final second = await open(storage);
      expect(second.leads.single.name, 'A. Sharma');
    });

    test('quick edits are batched into one write per collection', () async {
      final storage = MemoryDiaryStorage();
      final state = AppState(storage,
          saveDelay: const Duration(milliseconds: 50));
      await state.bootstrap();
      final before = storage.writeCount;
      for (var i = 0; i < 10; i++) {
        state.addTask(BrokerTask(
            id: state.nextId('tk'), title: 'T$i', dueAt: DateTime(2030)));
      }
      await state.flush();
      // tasks + activity, once each — not twenty writes.
      expect(storage.writeCount - before, 2);
    });

    test('ids are unique, even across restarts', () async {
      final storage = MemoryDiaryStorage();
      final ids = <String>{};
      for (var run = 0; run < 3; run++) {
        final state = await open(storage);
        for (var i = 0; i < 50; i++) {
          ids.add(state.nextId('ld'));
        }
      }
      expect(ids, hasLength(150));
    });

    test('one unreadable record does not lose the rest', () async {
      final storage = MemoryDiaryStorage({
        Collections.leads: {
          'version': 1,
          'items': [
            {'id': 'ok-1', 'name': 'Good', 'phone': '9000000001'},
            'not a record',
            {'id': 'ok-2', 'name': 'Also good', 'phone': '9000000002'},
          ],
        },
      });
      final state = await open(storage);
      expect(state.leads.map((e) => e.id), ['ok-1', 'ok-2']);
    });

    test('a save failure is reported and retried', () async {
      final storage = _FlakyStorage();
      final state = await open(storage);
      storage.failNext = true;
      state.addLead(Lead(id: 'x', name: 'X', phone: '9000000001'));
      await state.flush();
      expect(state.saveError, isNotNull);

      await state.flush();
      expect(state.saveError, isNull);
      expect(storage.snapshot[Collections.leads]?['items'], hasLength(1));
    });

    test('erasing the diary removes everything', () async {
      final storage = MemoryDiaryStorage();
      final state = await open(storage);
      state.saveProfile(BrokerProfile(name: 'Me'));
      state.addLead(Lead(id: 'x', name: 'X', phone: '9000000001'));
      await state.flush();
      await state.eraseAllData();
      expect(state.isSetUp, isFalse);
      expect(state.leads, isEmpty);
      final again = await open(storage);
      expect(again.isSetUp, isFalse);
      expect(again.leads, isEmpty);
    });
  });

  group('Recently deleted', () {
    late AppState state;

    setUp(() async {
      state = AppState(MemoryDiaryStorage(), saveDelay: Duration.zero);
      await state.bootstrap();
    });

    test('a deleted lead can be restored', () {
      final lead = state.addLead(
          Lead(id: 'ld-1', name: 'Rohit', phone: '9821034567'),
          createContact: false);
      final trashId = state.deleteLead(lead.id)!;
      expect(state.leads, isEmpty);
      expect(state.trash.single.title, 'Rohit');

      state.restoreFromTrash(trashId);
      expect(state.leads.single.id, 'ld-1');
      expect(state.trash, isEmpty);
    });

    test('deleting a deal takes its payments with it, and brings them back',
        () {
      final deal = state.addDeal(Deal(id: 'dl-1', title: 'D'));
      state.addPayment(PaymentRecord(
          id: 'pm-1', dealId: 'dl-1', amount: 5, dueDate: DateTime(2030)));
      final trashId = state.deleteDeal(deal.id)!;
      expect(state.payments, isEmpty);
      state.restoreFromTrash(trashId);
      expect(state.payments.single.id, 'pm-1');
    });

    test('deleting a visit removes its confirm-visit follow-up too', () {
      state.addProperty(Property(id: 'pr-1', title: 'Flat'));
      final visit = state.addVisit(SiteVisit(
          id: 'vs-1', propertyId: 'pr-1', scheduledAt: DateTime(2030)));
      expect(state.tasks, hasLength(1));
      final trashId = state.deleteVisit(visit.id)!;
      expect(state.tasks, isEmpty);
      state.restoreFromTrash(trashId);
      expect(state.tasks, hasLength(1));
    });

    test('restoring does not duplicate a record that already came back', () {
      state.addLead(Lead(id: 'ld-1', name: 'R', phone: '9821034567'),
          createContact: false);
      final trashId = state.deleteLead('ld-1')!;
      state.addLead(Lead(id: 'ld-1', name: 'R', phone: '9821034567'),
          createContact: false);
      state.restoreFromTrash(trashId);
      expect(state.leads, hasLength(1));
    });

    test('items older than 30 days are purged on start-up', () async {
      final storage = MemoryDiaryStorage({
        Collections.trash: {
          'version': 1,
          'items': [
            TrashEntry(
              id: 'old',
              kind: EntityKind.lead,
              title: 'Old',
              records: const {},
              deletedAt: DateTime.now().subtract(const Duration(days: 31)),
            ).toJson(),
            TrashEntry(
              id: 'new',
              kind: EntityKind.lead,
              title: 'New',
              records: const {},
              deletedAt: DateTime.now().subtract(const Duration(days: 2)),
            ).toJson(),
          ],
        },
      });
      final s = AppState(storage, saveDelay: Duration.zero);
      await s.bootstrap();
      expect(s.trash.map((e) => e.id), ['new']);
    });
  });

  group('lead follow-ups', () {
    late AppState state;

    setUp(() async {
      state = AppState(MemoryDiaryStorage(), saveDelay: Duration.zero);
      await state.bootstrap();
    });

    test('moving a lead follow-up moves its follow-up task', () {
      final at = DateTime(2030, 1, 1, 10);
      final lead = state.addLead(
          Lead(id: 'l', name: 'R', phone: '9821034567', nextFollowUpAt: at),
          createContact: false);
      state.addTask(BrokerTask(
          id: 't',
          title: 'Follow up with R',
          dueAt: at,
          relatedKind: EntityKind.lead,
          relatedId: 'l'));

      lead.nextFollowUpAt = DateTime(2030, 1, 5, 16);
      state.updateLead(lead, previousFollowUp: at);
      expect(state.task('t')!.dueAt, DateTime(2030, 1, 5, 16));
    });

    test('Snooze from a notification moves the task and its lead', () {
      final at = DateTime(2030, 1, 1, 10);
      state.addLead(
          Lead(id: 'l', name: 'R', phone: '9821034567', nextFollowUpAt: at),
          createContact: false);
      state.addTask(BrokerTask(
          id: 't',
          title: 'Call R',
          dueAt: at,
          relatedKind: EntityKind.lead,
          relatedId: 'l'));
      final pressed = DateTime(2030, 1, 1, 10, 2);
      state.applyReminderAction(ReminderAction(
          type: ReminderActionType.snooze,
          kind: EntityKind.task,
          entityId: 't',
          at: pressed));
      expect(state.task('t')!.dueAt, pressed.add(const Duration(hours: 1)));
      expect(state.lead('l')!.nextFollowUpAt,
          pressed.add(const Duration(hours: 1)));
    });

    test('Done from a notification completes the task', () {
      state.addTask(
          BrokerTask(id: 't', title: 'Call', dueAt: DateTime(2030)));
      state.applyReminderAction(ReminderAction(
          type: ReminderActionType.done,
          kind: EntityKind.task,
          entityId: 't',
          at: DateTime(2030)));
      expect(state.task('t')!.done, isTrue);
    });

    test('an action for a deleted record is ignored', () {
      expect(
        state.applyReminderAction(ReminderAction(
            type: ReminderActionType.done,
            kind: EntityKind.task,
            entityId: 'gone',
            at: DateTime(2030))),
        isFalse,
      );
    });
  });
}

class _FlakyStorage extends MemoryDiaryStorage {
  bool failNext = false;

  @override
  Future<void> write(String name, Map<String, dynamic> json) async {
    if (failNext) {
      failNext = false;
      throw const FileSystemException('No space left on device');
    }
    return super.write(name, json);
  }
}
