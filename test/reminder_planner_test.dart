import 'package:broker_demo_app/data/diary_storage.dart';
import 'package:broker_demo_app/models/models.dart';
import 'package:broker_demo_app/services/reminder_planner.dart';
import 'package:broker_demo_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppState state;
  final now = DateTime(2030, 3, 10, 9, 0); // 9 am
  const planner = ReminderPlanner();

  List<PlannedReminder> plan({
    bool digest = false,
    int visitLead = 60,
    DateTime? at,
  }) =>
      planner.plan(
        state,
        now: at ?? now,
        digestEnabled: digest,
        digestHour: 8,
        digestMinute: 30,
        visitLeadMinutes: visitLead,
      );

  setUp(() async {
    state = AppState(MemoryDiaryStorage(), saveDelay: Duration.zero);
    await state.bootstrap();
    state.addProperty(Property(id: 'pr', title: '2 BHK Kharadi'));
  });

  test('an open follow-up task becomes a reminder at its due time', () {
    state.addTask(BrokerTask(
        id: 't1', title: 'Call Priya', dueAt: now.add(const Duration(hours: 3))));
    final r = plan().single;
    expect(r.at, now.add(const Duration(hours: 3)));
    expect(r.title, 'Call Priya');
    expect(r.actionable, isTrue);
  });

  test('done, overdue and far-future tasks are not scheduled', () {
    state.addTask(BrokerTask(
        id: 'done', title: 'x', dueAt: now.add(const Duration(hours: 1)), done: true));
    state.addTask(BrokerTask(
        id: 'past', title: 'x', dueAt: now.subtract(const Duration(hours: 1))));
    state.addTask(BrokerTask(
        id: 'far', title: 'x', dueAt: now.add(const Duration(days: 45))));
    expect(plan(), isEmpty);
  });

  test('a site visit reminds the chosen time beforehand', () {
    state.addVisit(
      SiteVisit(
          id: 'v1', propertyId: 'pr', scheduledAt: DateTime(2030, 3, 10, 16)),
      createReminder: false,
    );
    final r = plan(visitLead: 30).single;
    expect(r.at, DateTime(2030, 3, 10, 15, 30));
    expect(r.body, contains('2 BHK Kharadi'));
    expect(r.actionable, isFalse);
  });

  test('cancelled visits are not reminded', () {
    state.addVisit(
      SiteVisit(
          id: 'v1',
          propertyId: 'pr',
          scheduledAt: DateTime(2030, 3, 10, 16),
          status: VisitStatus.cancelled),
      createReminder: false,
    );
    expect(plan(), isEmpty);
  });

  test('a lead follow-up is reminded once, not twice, when it has a task', () {
    final at = DateTime(2030, 3, 11, 11);
    state.addLead(
        Lead(id: 'l1', name: 'Rohit', phone: '9821034567', nextFollowUpAt: at),
        createContact: false);
    state.addTask(BrokerTask(
        id: 't1',
        title: 'Follow up with Rohit',
        dueAt: at,
        relatedKind: EntityKind.lead,
        relatedId: 'l1'));
    final reminders = plan();
    expect(reminders, hasLength(1));
    expect(reminders.single.key, 'task:t1');
  });

  test('a lead follow-up on its own is reminded', () {
    state.addLead(
        Lead(
            id: 'l1',
            name: 'Rohit',
            phone: '9821034567',
            nextFollowUpAt: DateTime(2030, 3, 11, 11)),
        createContact: false);
    final r = plan().single;
    expect(r.key, 'lead:l1');
    expect(r.title, 'Follow up: Rohit');
    expect(r.body, contains('9821034567'));
  });

  test('closed leads are not reminded', () {
    state.addLead(
        Lead(
            id: 'l1',
            name: 'Rohit',
            phone: '9821034567',
            status: LeadStatus.lost,
            nextFollowUpAt: DateTime(2030, 3, 11, 11)),
        createContact: false);
    expect(plan(), isEmpty);
  });

  test('unpaid commission is reminded on its due morning', () {
    state.addDeal(Deal(id: 'd1', title: 'Rohit · 3 BHK'));
    state.addPayment(PaymentRecord(
        id: 'p1', dealId: 'd1', amount: 50000, dueDate: DateTime(2030, 3, 12)));
    final r = plan().single;
    expect(r.at, DateTime(2030, 3, 12, 10));
    expect(r.title, contains('50'));
  });

  test('a document is reminded a week before it expires', () {
    state.addDocument(DocumentRecord(
        id: 'doc', name: 'Rent agreement', expiryDate: DateTime(2030, 3, 25)));
    final r = plan().single;
    expect(r.at, DateTime(2030, 3, 18, 10));
  });

  test('the morning summary counts the day and skips empty days', () {
    state.addTask(BrokerTask(
        id: 't1', title: 'Call', dueAt: DateTime(2030, 3, 11, 12)));
    state.addTask(BrokerTask(
        id: 't2', title: 'Call', dueAt: DateTime(2030, 3, 11, 15)));
    final digests =
        plan(digest: true).where((r) => r.source == ReminderSource.digest);
    // Today's 8:30 has passed; tomorrow has two calls; the rest are empty.
    expect(digests, hasLength(1));
    expect(digests.single.at, DateTime(2030, 3, 11, 8, 30));
    expect(digests.single.body, '2 follow-ups');
  });

  test('ids are stable between runs and differ between records', () {
    state.addTask(BrokerTask(
        id: 't1', title: 'A', dueAt: now.add(const Duration(hours: 1))));
    state.addTask(BrokerTask(
        id: 't2', title: 'B', dueAt: now.add(const Duration(hours: 2))));
    final a = plan().map((r) => r.id).toList();
    final b = plan().map((r) => r.id).toList();
    expect(a, b);
    expect(a.toSet(), hasLength(2));
    expect(a.every((id) => id > 0 && id <= 0x7fffffff), isTrue);
  });

  test('changing the time changes the fingerprint (so it is re-scheduled)', () {
    final t = state.addTask(BrokerTask(
        id: 't1', title: 'A', dueAt: now.add(const Duration(hours: 1))));
    final before = plan().single.fingerprint;
    t.dueAt = now.add(const Duration(hours: 2));
    state.updateTask(t);
    expect(plan().single.fingerprint, isNot(before));
  });

  test('never schedules more than the cap, nearest first', () {
    for (var i = 0; i < 100; i++) {
      state.addTask(BrokerTask(
          id: 't$i', title: 'T$i', dueAt: now.add(Duration(hours: i + 1))));
    }
    final reminders = plan();
    expect(reminders, hasLength(planner.maxScheduled));
    expect(reminders.first.title, 'T0');
  });
}
