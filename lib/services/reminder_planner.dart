import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';

/// What a reminder points at, so a tap can open the right record.
enum ReminderSource { task, leadFollowUp, visit, payment, document, digest }

/// One notification the phone should be holding.
class PlannedReminder {
  const PlannedReminder({
    required this.key,
    required this.at,
    required this.title,
    required this.body,
    required this.source,
    this.kind,
    this.entityId,
  });

  /// Stable across app launches; [id] is derived from it.
  final String key;
  final DateTime at;
  final String title;
  final String body;
  final ReminderSource source;
  final EntityKind? kind;
  final String? entityId;

  /// Android needs a 32-bit id. FNV-1a of the key keeps it stable, so
  /// re-planning finds and updates the same notification instead of
  /// stacking a duplicate.
  int get id {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h & 0x7fffffff;
  }

  /// Follow-ups get Snooze / Done buttons; the digest and visits don't.
  bool get actionable =>
      source == ReminderSource.task || source == ReminderSource.leadFollowUp;

  /// Everything that changes what the user sees. If this differs from the
  /// pending notification's, it is re-scheduled.
  String get fingerprint =>
      '${at.toUtc().millisecondsSinceEpoch}|$title|$body';
}

/// Works out which reminders should be scheduled right now.
///
/// Pure: the same diary and clock always give the same plan, which is what
/// makes the reconcile in [ReminderService] safe to run as often as we like.
class ReminderPlanner {
  const ReminderPlanner({
    this.horizon = const Duration(days: 30),
    this.maxScheduled = 60,
    this.digestDays = 7,
  });

  /// How far ahead to schedule. Further reminders are added on a later
  /// app open — phones cope badly with hundreds of pending alarms (iOS
  /// caps it at 64), so we keep a rolling window.
  final Duration horizon;
  final int maxScheduled;
  final int digestDays;

  List<PlannedReminder> plan(
    AppState state, {
    required DateTime now,
    required bool digestEnabled,
    required int digestHour,
    required int digestMinute,
    required int visitLeadMinutes,
  }) {
    final until = now.add(horizon);
    bool inWindow(DateTime t) => t.isAfter(now) && !t.isAfter(until);
    final out = <PlannedReminder>[];

    for (final t in state.tasks) {
      if (t.done || !inWindow(t.dueAt)) continue;
      final related = _relatedLabel(state, t.relatedKind, t.relatedId);
      out.add(PlannedReminder(
        key: 'task:${t.id}',
        at: t.dueAt,
        title: t.title,
        body: [
          t.type.label,
          ?related,
          if (t.notes.isNotEmpty) t.notes,
        ].join(' · '),
        source: ReminderSource.task,
        kind: EntityKind.task,
        entityId: t.id,
      ));
    }

    // A lead's follow-up usually has a matching follow-up task (created with
    // the lead). Remind once, not twice.
    final taskSlots = {
      for (final t in state.tasks)
        if (!t.done && t.relatedKind == EntityKind.lead && t.relatedId != null)
          '${t.relatedId}@${t.dueAt.millisecondsSinceEpoch ~/ 60000}',
    };
    for (final l in state.leads) {
      final at = l.nextFollowUpAt;
      if (at == null || !l.status.isOpen || !inWindow(at)) continue;
      if (taskSlots.contains('${l.id}@${at.millisecondsSinceEpoch ~/ 60000}')) {
        continue;
      }
      out.add(PlannedReminder(
        key: 'lead:${l.id}',
        at: at,
        title: 'Follow up: ${l.name}',
        body: [
          if (l.phone.isNotEmpty) l.phone,
          l.status.label,
          if (l.preferredLocation.isNotEmpty) l.preferredLocation,
          if (l.budgetMax > 0) formatBudgetRange(l.budgetMin, l.budgetMax),
        ].join(' · '),
        source: ReminderSource.leadFollowUp,
        kind: EntityKind.lead,
        entityId: l.id,
      ));
    }

    for (final v in state.visits) {
      if (v.status == VisitStatus.cancelled ||
          v.status == VisitStatus.completed) {
        continue;
      }
      final at = v.scheduledAt.subtract(Duration(minutes: visitLeadMinutes));
      if (!inWindow(at)) continue;
      final who = state.contact(v.contactId)?.name ?? state.lead(v.leadId)?.name;
      out.add(PlannedReminder(
        key: 'visit:${v.id}',
        at: at,
        title: 'Site visit at ${formatTime(v.scheduledAt)}',
        body: [
          state.propertyTitle(v.propertyId),
          ?who,
        ].join(' · '),
        source: ReminderSource.visit,
        kind: EntityKind.visit,
        entityId: v.id,
      ));
    }

    for (final pay in state.payments) {
      if (pay.isPaid) continue;
      final at = _morningOf(pay.dueDate, 10);
      if (!inWindow(at)) continue;
      out.add(PlannedReminder(
        key: 'payment:${pay.id}',
        at: at,
        title: 'Commission due today: ${formatMoney(pay.amount)}',
        body: state.deal(pay.dealId)?.title ?? '',
        source: ReminderSource.payment,
        kind: EntityKind.deal,
        entityId: pay.dealId,
      ));
    }

    for (final d in state.documents) {
      final expiry = d.expiryDate;
      if (expiry == null) continue;
      final at = _morningOf(expiry.subtract(const Duration(days: 7)), 10);
      if (!inWindow(at)) continue;
      out.add(PlannedReminder(
        key: 'document:${d.id}',
        at: at,
        title: '${d.name} expires in a week',
        body: 'Expires ${formatDate(expiry)}',
        source: ReminderSource.document,
        kind: EntityKind.document,
        entityId: d.id,
      ));
    }

    // Nearest first, then cap. Digests are added after the cap is applied
    // to everything else, so a busy diary still gets its morning summary.
    out.sort((a, b) => a.at.compareTo(b.at));
    final capped = out.take(maxScheduled - (digestEnabled ? digestDays : 0)).toList();

    if (digestEnabled) {
      for (var day = 0; day < digestDays; day++) {
        final date = DateUtilsX.startOfDay(now).add(Duration(days: day));
        final at = DateTime(
            date.year, date.month, date.day, digestHour, digestMinute);
        if (!at.isAfter(now)) continue;
        final digest = _digestFor(state, date, includeOverdue: day == 0);
        if (digest == null) continue;
        capped.add(PlannedReminder(
          key: 'digest:${date.year}-${date.month}-${date.day}',
          at: at,
          title: digest.$1,
          body: digest.$2,
          source: ReminderSource.digest,
        ));
      }
    }
    return capped;
  }

  /// The morning summary. Counts are fixed when scheduled; every app open
  /// re-plans, so they stay current for anyone who opens the diary daily.
  static (String, String)? _digestFor(AppState state, DateTime day,
      {required bool includeOverdue}) {
    final tasks = state.tasks
        .where((t) => !t.done && DateUtilsX.isSameDay(t.dueAt, day))
        .length;
    final followUps = state.leads
        .where((l) =>
            l.status.isOpen &&
            l.nextFollowUpAt != null &&
            DateUtilsX.isSameDay(l.nextFollowUpAt!, day))
        .length;
    final visits = state.visits
        .where((v) =>
            v.status != VisitStatus.cancelled &&
            v.status != VisitStatus.completed &&
            DateUtilsX.isSameDay(v.scheduledAt, day))
        .length;
    final overdue = includeOverdue
        ? state.tasks.where((t) => t.isOverdue).length +
            state.leads.where((l) => l.isFollowUpOverdue).length
        : 0;

    final calls = tasks + followUps;
    if (calls == 0 && visits == 0 && overdue == 0) return null;
    final parts = [
      if (calls > 0) pluralise(calls, 'follow-up'),
      if (visits > 0) pluralise(visits, 'site visit'),
      if (overdue > 0) '$overdue overdue',
    ];
    return ("Today's diary", parts.join(' · '));
  }

  static DateTime _morningOf(DateTime d, int hour) =>
      DateTime(d.year, d.month, d.day, hour);

  static String? _relatedLabel(AppState state, EntityKind? kind, String? id) {
    if (kind == null || id == null) return null;
    return switch (kind) {
      EntityKind.lead => state.lead(id)?.name,
      EntityKind.contact => state.contact(id)?.name,
      EntityKind.property => state.property(id)?.title,
      EntityKind.deal => state.deal(id)?.title,
      EntityKind.visit => () {
          final v = state.visit(id);
          return v == null ? null : state.propertyTitle(v.propertyId);
        }(),
      _ => null,
    };
  }
}
