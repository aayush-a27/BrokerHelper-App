import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../data/diary_storage.dart';
import '../models/models.dart';
import '../utils/formatters.dart';

/// Names of the files the diary is split into. Changing one edits only its
/// own file, so saving a lead never rewrites the whole diary.
abstract final class Collections {
  static const profile = 'profile';
  static const leads = 'leads';
  static const contacts = 'contacts';
  static const properties = 'properties';
  static const visits = 'visits';
  static const tasks = 'tasks';
  static const deals = 'deals';
  static const payments = 'payments';
  static const documents = 'documents';
  static const activity = 'activity';
  static const trash = 'trash';

  /// Everything a backup carries.
  static const all = <String>[
    profile, leads, contacts, properties, visits, tasks, deals, payments,
    documents, activity, trash,
  ];
}

/// What a notification's Snooze / Done button asks for.
enum ReminderActionType { snooze, done }

class ReminderAction {
  const ReminderAction({
    required this.type,
    required this.kind,
    required this.entityId,
    required this.at,
  });

  final ReminderActionType type;
  final EntityKind kind;
  final String entityId;

  /// When the button was pressed. A snooze counts from here, not from when
  /// the app next opens, so the re-armed reminder fires at the right time.
  final DateTime at;

  static const snoozeFor = Duration(hours: 1);

  factory ReminderAction.fromJson(Map<String, dynamic> j) => ReminderAction(
        type: enumFromName(
            ReminderActionType.values, j['type'], ReminderActionType.snooze),
        kind: enumFromName(EntityKind.values, j['kind'], EntityKind.task),
        entityId: j['id']?.toString() ?? '',
        at: DateTime.tryParse(j['at']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'kind': kind.name,
        'id': entityId,
        'at': at.toUtc().toIso8601String(),
      };
}

/// The diary. Holds every record in memory for instant reads, and writes
/// each change back to the phone's storage.
///
/// Saving is batched: a change marks its collection dirty and a save runs
/// [saveDelay] later, so five quick edits cost one write. [flush] forces the
/// save immediately — the app calls it whenever it goes to the background,
/// so closing the app never loses an entry.
class AppState extends ChangeNotifier {
  AppState(this._storage, {this.saveDelay = const Duration(milliseconds: 300)});

  final DiaryStorage _storage;
  final Duration saveDelay;

  static const _schemaVersion = 1;
  static const _maxActivity = 2000;
  static const _uuid = Uuid();

  bool _loading = true;
  String? _loadError;
  String? _saveError;

  BrokerProfile? _profile;
  final List<Contact> _contacts = [];
  final List<Property> _properties = [];
  final List<Lead> _leads = [];
  final List<SiteVisit> _visits = [];
  final List<BrokerTask> _tasks = [];
  final List<Deal> _deals = [];
  final List<PaymentRecord> _payments = [];
  final List<DocumentRecord> _documents = [];
  final List<ActivityEntry> _activities = [];
  final List<TrashEntry> _trash = [];

  final Set<String> _dirty = {};
  Timer? _saveTimer;
  Future<void>? _saving;
  int _revision = 0;

  DiaryStorage get storage => _storage;

  // --- lifecycle -----------------------------------------------------------

  bool get isLoading => _loading;
  String? get loadError => _loadError;

  /// Set when the last save failed (e.g. the phone is out of space). The
  /// change is still in memory and the next save retries it.
  String? get saveError => _saveError;

  /// Bumps on every change. The reminder scheduler watches it.
  int get revision => _revision;

  Future<void> bootstrap() async {
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final profile = await _storage.read(Collections.profile);
      final p = profile?['profile'];
      _profile = p is Map && (p['name']?.toString() ?? '').isNotEmpty
          ? BrokerProfile.fromJson(Map<String, dynamic>.from(p))
          : null;

      await Future.wait([
        _load(Collections.contacts, Contact.fromJson, _contacts),
        _load(Collections.properties, Property.fromJson, _properties),
        _load(Collections.leads, Lead.fromJson, _leads),
        _load(Collections.visits, SiteVisit.fromJson, _visits),
        _load(Collections.tasks, BrokerTask.fromJson, _tasks),
        _load(Collections.deals, Deal.fromJson, _deals),
        _load(Collections.payments, PaymentRecord.fromJson, _payments),
        _load(Collections.documents, DocumentRecord.fromJson, _documents),
        _load(Collections.activity, ActivityEntry.fromJson, _activities),
        _load(Collections.trash, TrashEntry.fromJson, _trash),
      ]);
      _activities.sort((a, b) => b.at.compareTo(a.at));
      _trash.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
      await _purgeExpiredTrash();
      unawaited(_sweepOrphanAttachments());
      _loading = false;
    } catch (e) {
      _loadError = e.toString();
      _loading = false;
    }
    _revision++;
    notifyListeners();
  }

  Future<void> _load<T>(String name, T Function(Map<String, dynamic>) fromJson,
      List<T> into) async {
    final json = await _storage.read(name);
    into.clear();
    final items = json?['items'];
    if (items is! List) return;
    for (final item in items) {
      if (item is! Map) continue;
      try {
        into.add(fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        // Skip one unreadable record rather than losing the whole file.
      }
    }
  }

  /// Writes every collection with unsaved changes. Safe to call at any time.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    // Wait for a save already in progress, then save whatever changed since.
    while (_saving != null) {
      await _saving;
    }
    if (_dirty.isEmpty) return;
    final names = _dirty.toList();
    _dirty.clear();
    final run = _write(names);
    _saving = run;
    try {
      await run;
    } finally {
      _saving = null;
    }
  }

  Future<void> _write(List<String> names) async {
    try {
      await Future.wait(names.map((n) => _storage.write(n, _encode(n))));
      if (_saveError != null) {
        _saveError = null;
        notifyListeners();
      }
    } catch (e) {
      // Keep them dirty so the next change (or app pause) retries.
      _dirty.addAll(names);
      _saveError = 'Could not save to the phone: $e';
      notifyListeners();
    }
  }

  Map<String, dynamic> _encode(String name) {
    List<Map<String, dynamic>> items(Iterable<Object> xs) =>
        xs.map((e) => (e as dynamic).toJson() as Map<String, dynamic>).toList();
    if (name == Collections.profile) {
      return {'version': _schemaVersion, 'profile': _profile?.toJson()};
    }
    final list = switch (name) {
      Collections.leads => items(_leads),
      Collections.contacts => items(_contacts),
      Collections.properties => items(_properties),
      Collections.visits => items(_visits),
      Collections.tasks => items(_tasks),
      Collections.deals => items(_deals),
      Collections.payments => items(_payments),
      Collections.documents => items(_documents),
      Collections.activity => items(_activities),
      Collections.trash => items(_trash),
      _ => throw ArgumentError('Unknown collection $name'),
    };
    return {'version': _schemaVersion, 'items': list};
  }

  /// Every mutation ends here: remember what to save, tell the UI, and
  /// schedule the write.
  void _commit(Set<String> touched) {
    _dirty
      ..addAll(touched)
      ..add(Collections.activity);
    _revision++;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () => unawaited(flush()));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  // --- the broker on this phone -------------------------------------------

  BrokerProfile? get profile => _profile;

  /// False until the first-run setup has been completed.
  bool get isSetUp => _profile != null;

  String get brokerName => _profile?.name ?? 'Me';

  void saveProfile(BrokerProfile profile) {
    final first = _profile == null;
    _profile = profile;
    _log(first ? 'Diary started' : 'Profile updated', profile.name,
        EntityKind.contact, null);
    _commit({Collections.profile});
  }

  /// Deletes the whole diary from this phone. Used by "Erase all data" and
  /// by "Forgot PIN".
  Future<void> eraseAllData() async {
    _saveTimer?.cancel();
    while (_saving != null) {
      await _saving;
    }
    _dirty.clear();
    await _storage.eraseAll();
    _profile = null;
    for (final list in <List<Object>>[
      _contacts, _properties, _leads, _visits, _tasks, _deals, _payments,
      _documents, _activities, _trash,
    ]) {
      list.clear();
    }
    _revision++;
    notifyListeners();
  }

  // --- collections ---------------------------------------------------------

  List<Lead> get leads => List.unmodifiable(_leads);
  List<Contact> get contacts => List.unmodifiable(_contacts);
  List<Property> get properties => List.unmodifiable(_properties);
  List<SiteVisit> get visits => List.unmodifiable(_visits);
  List<BrokerTask> get tasks => List.unmodifiable(_tasks);
  List<Deal> get deals => List.unmodifiable(_deals);
  List<PaymentRecord> get payments => List.unmodifiable(_payments);
  List<DocumentRecord> get documents => List.unmodifiable(_documents);
  List<ActivityEntry> get activities => List.unmodifiable(_activities);
  List<TrashEntry> get trash => List.unmodifiable(_trash);

  bool get isEmpty =>
      _leads.isEmpty &&
      _contacts.isEmpty &&
      _properties.isEmpty &&
      _deals.isEmpty &&
      _tasks.isEmpty;

  Lead? lead(String? id) =>
      id == null ? null : _firstWhereOrNull(_leads, (e) => e.id == id);
  Contact? contact(String? id) =>
      id == null ? null : _firstWhereOrNull(_contacts, (e) => e.id == id);
  Property? property(String? id) =>
      id == null ? null : _firstWhereOrNull(_properties, (e) => e.id == id);
  SiteVisit? visit(String? id) =>
      id == null ? null : _firstWhereOrNull(_visits, (e) => e.id == id);
  BrokerTask? task(String? id) =>
      id == null ? null : _firstWhereOrNull(_tasks, (e) => e.id == id);
  Deal? deal(String? id) =>
      id == null ? null : _firstWhereOrNull(_deals, (e) => e.id == id);
  PaymentRecord? payment(String? id) =>
      id == null ? null : _firstWhereOrNull(_payments, (e) => e.id == id);
  DocumentRecord? document(String? id) =>
      id == null ? null : _firstWhereOrNull(_documents, (e) => e.id == id);

  String propertyTitle(String? id) => property(id)?.title ?? 'No property';
  String contactName(String? id) => contact(id)?.name ?? 'No contact';

  // --- leads ---------------------------------------------------------------

  /// Creates a lead and, unless one already exists for the phone number, the
  /// matching buyer contact — so the two records stay linked from the start.
  Lead addLead(Lead lead, {bool createContact = true}) {
    final touched = {Collections.leads};
    if (createContact && lead.contactId == null) {
      final existing = _firstWhereOrNull(
          _contacts, (c) => samePhone(c.phone, lead.phone));
      if (existing != null) {
        lead.contactId = existing.id;
      } else {
        final c = Contact(
          id: nextId('ct'),
          name: lead.name,
          phone: lead.phone,
          email: lead.email,
          role: ContactRole.buyer,
          locality: lead.preferredLocation,
          buyer: BuyerProfile(
            budgetMin: lead.budgetMin,
            budgetMax: lead.budgetMax,
            preferredLocations:
                lead.preferredLocation.isEmpty ? [] : [lead.preferredLocation],
            propertyTypes: [lead.propertyType],
            bedrooms: lead.bedrooms,
          ),
        );
        _contacts.insert(0, c);
        lead.contactId = c.id;
        touched.add(Collections.contacts);
        _log('Contact added', '${c.name} created from a lead',
            EntityKind.contact, c.id);
      }
    }
    _leads.insert(0, lead);
    _log('Lead added', '${lead.name} · ${lead.source.label}', EntityKind.lead,
        lead.id);
    _commit(touched);
    return lead;
  }

  /// Saves an edited lead. When the follow-up date moved, the follow-up
  /// task created with the lead moves with it, so the broker isn't reminded
  /// twice (once at the old time, once at the new).
  void updateLead(Lead lead, {DateTime? previousFollowUp}) {
    final touched = {Collections.leads};
    if (previousFollowUp != null && previousFollowUp != lead.nextFollowUpAt) {
      for (final t in _tasks) {
        if (!t.done &&
            t.relatedKind == EntityKind.lead &&
            t.relatedId == lead.id &&
            t.dueAt == previousFollowUp) {
          if (lead.nextFollowUpAt == null) {
            t.done = true;
            t.completedAt = DateTime.now();
          } else {
            t.dueAt = lead.nextFollowUpAt!;
          }
          touched.add(Collections.tasks);
        }
      }
    }
    _log('Lead updated', '${lead.name} · ${lead.status.label}', EntityKind.lead,
        lead.id);
    _commit(touched);
  }

  void setLeadStatus(Lead lead, LeadStatus status) {
    if (lead.status == status) return;
    lead.status = status;
    _log('Lead stage changed', '${lead.name} moved to ${status.label}',
        EntityKind.lead, lead.id);
    _commit({Collections.leads});
  }

  /// Sets or clears the next follow-up — the date the reminder fires.
  void setLeadFollowUp(Lead lead, DateTime? at) {
    lead.nextFollowUpAt = at;
    _log(
        at == null ? 'Follow-up cleared' : 'Follow-up set',
        at == null ? lead.name : '${lead.name} · ${formatDateTime(at)}',
        EntityKind.lead,
        lead.id);
    _commit({Collections.leads});
  }

  /// Moves the record to Recently deleted. Returns the bin entry's id, for
  /// an Undo button, or null if there was nothing to delete.
  String? deleteLead(String id) {
    final l = lead(id);
    if (l == null) return null;
    _leads.removeWhere((e) => e.id == id);
    final trashId = _toTrash(EntityKind.lead, l.name, {
      Collections.leads: [l.toJson()],
    });
    _log('Lead deleted', l.name, EntityKind.lead, id);
    _commit({Collections.leads, Collections.trash});
    return trashId;
  }

  /// Possible duplicates, matched on phone number then on name.
  List<Lead> duplicateLeadsFor(Lead lead) => _leads
      .where((e) =>
          e.id != lead.id &&
          (samePhone(e.phone, lead.phone) ||
              e.name.trim().toLowerCase() == lead.name.trim().toLowerCase()))
      .toList();

  List<Contact> duplicateContactsFor(Contact contact) => _contacts
      .where((e) =>
          e.id != contact.id &&
          (samePhone(e.phone, contact.phone) ||
              e.name.trim().toLowerCase() == contact.name.trim().toLowerCase()))
      .toList();

  /// Marks a property as shared with a lead's buyer and links it both ways.
  void sharePropertyWithLead(Lead lead, Property property) {
    if (!lead.sharedPropertyIds.contains(property.id)) {
      lead.sharedPropertyIds.add(property.id);
    }
    final contactId = lead.contactId;
    if (contactId != null &&
        !property.interestedContactIds.contains(contactId)) {
      property.interestedContactIds.add(contactId);
    }
    _log('Property shared', '${property.title} shared with ${lead.name}',
        EntityKind.property, property.id);
    _commit({Collections.leads, Collections.properties});
  }

  void toggleShortlist(Lead lead, Property property) {
    if (lead.shortlistedPropertyIds.remove(property.id)) {
      _log('Shortlist updated', '${property.title} removed from ${lead.name}',
          EntityKind.lead, lead.id);
    } else {
      lead.shortlistedPropertyIds.add(property.id);
      final contactId = lead.contactId;
      if (contactId != null &&
          !property.interestedContactIds.contains(contactId)) {
        property.interestedContactIds.add(contactId);
      }
      _log('Shortlist updated', '${property.title} shortlisted for ${lead.name}',
          EntityKind.lead, lead.id);
    }
    _commit({Collections.leads, Collections.properties});
  }

  // --- contacts ------------------------------------------------------------

  Contact addContact(Contact contact) {
    _contacts.insert(0, contact);
    _log('Contact added', '${contact.name} · ${contact.role.label}',
        EntityKind.contact, contact.id);
    _commit({Collections.contacts});
    return contact;
  }

  void updateContact(Contact contact) {
    _log('Contact updated', contact.name, EntityKind.contact, contact.id);
    _commit({Collections.contacts});
  }

  /// Moves the record to Recently deleted. Returns the bin entry's id, for
  /// an Undo button, or null if there was nothing to delete.
  String? deleteContact(String id) {
    final c = contact(id);
    if (c == null) return null;
    _contacts.removeWhere((e) => e.id == id);
    final trashId = _toTrash(EntityKind.contact, c.name, {
      Collections.contacts: [c.toJson()],
    });
    _log('Contact deleted', c.name, EntityKind.contact, id);
    _commit({Collections.contacts, Collections.trash});
    return trashId;
  }

  void logInteraction(Contact contact, String channel, String note) {
    contact.interactions.insert(
        0, Interaction(at: DateTime.now(), channel: channel, note: note));
    _log('Interaction logged', '$channel with ${contact.name}',
        EntityKind.contact, contact.id);
    _commit({Collections.contacts});
  }

  List<Lead> leadsForContact(String contactId) =>
      _leads.where((e) => e.contactId == contactId).toList();

  List<Property> propertiesForOwner(String contactId) =>
      _properties.where((e) => e.ownerContactId == contactId).toList();

  List<Deal> dealsForContact(String contactId) => _deals
      .where((e) =>
          e.buyerContactId == contactId || e.sellerContactId == contactId)
      .toList();

  // --- properties ----------------------------------------------------------

  Property addProperty(Property property) {
    _properties.insert(0, property);
    _log('Property added', '${property.title} · ${property.shortAddress}',
        EntityKind.property, property.id);
    _commit({Collections.properties});
    return property;
  }

  void updateProperty(Property property) {
    _log('Property updated', property.title, EntityKind.property, property.id);
    _commit({Collections.properties});
  }

  void setPropertyStatus(Property property, PropertyStatus status) {
    if (property.status == status) return;
    property.status = status;
    _log('Availability changed', '${property.title} is now ${status.label}',
        EntityKind.property, property.id);
    _commit({Collections.properties});
  }

  /// Moves the record to Recently deleted. Returns the bin entry's id, for
  /// an Undo button, or null if there was nothing to delete.
  String? deleteProperty(String id) {
    final p = property(id);
    if (p == null) return null;
    _properties.removeWhere((e) => e.id == id);
    final trashId = _toTrash(EntityKind.property, p.title, {
      Collections.properties: [p.toJson()],
    });
    _log('Property deleted', p.title, EntityKind.property, id);
    _commit({Collections.properties, Collections.trash});
    return trashId;
  }

  List<Contact> interestedIn(Property property) => property.interestedContactIds
      .map(contact)
      .whereType<Contact>()
      .toList();

  // --- visits --------------------------------------------------------------

  SiteVisit addVisit(SiteVisit visit, {bool createReminder = true}) {
    _visits.insert(0, visit);
    final touched = {Collections.visits};
    if (createReminder) {
      _tasks.insert(
        0,
        BrokerTask(
          id: nextId('tk'),
          title: 'Confirm visit — ${propertyTitle(visit.propertyId)}',
          type: TaskType.visit,
          dueAt: visit.scheduledAt.subtract(const Duration(hours: 2)),
          relatedKind: EntityKind.visit,
          relatedId: visit.id,
        ),
      );
      touched.add(Collections.tasks);
    }
    _log(
        'Visit scheduled',
        '${propertyTitle(visit.propertyId)} on ${formatDateTime(visit.scheduledAt)}',
        EntityKind.visit,
        visit.id);
    _commit(touched);
    return visit;
  }

  void updateVisit(SiteVisit visit) {
    _log('Visit updated', propertyTitle(visit.propertyId), EntityKind.visit,
        visit.id);
    _commit({Collections.visits});
  }

  void rescheduleVisit(SiteVisit visit, DateTime newTime) {
    final old = visit.scheduledAt;
    visit.scheduledAt = newTime;
    visit.status = VisitStatus.scheduled;
    // Move the "confirm visit" reminder with it.
    for (final t in _tasks) {
      if (!t.done &&
          t.relatedKind == EntityKind.visit &&
          t.relatedId == visit.id &&
          t.type == TaskType.visit) {
        t.dueAt = newTime.subtract(const Duration(hours: 2));
      }
    }
    _log('Visit rescheduled',
        '${formatDateTime(old)} → ${formatDateTime(newTime)}', EntityKind.visit,
        visit.id);
    _commit({Collections.visits, Collections.tasks});
  }

  /// Records the outcome and nudges the linked lead forward.
  void recordVisitOutcome(
      SiteVisit visit, VisitOutcome outcome, String feedback) {
    visit.outcome = outcome;
    visit.feedback = feedback;
    visit.status = VisitStatus.completed;
    final linked = lead(visit.leadId);
    if (linked != null && linked.status.isOpen) {
      linked.status = outcome == VisitOutcome.offerMade
          ? LeadStatus.negotiation
          : LeadStatus.siteVisit;
    }
    _log('Visit outcome recorded',
        '${outcome.label} — ${propertyTitle(visit.propertyId)}',
        EntityKind.visit, visit.id);
    _commit({Collections.visits, Collections.leads});
  }

  /// Moves the record to Recently deleted. Returns the bin entry's id, for
  /// an Undo button, or null if there was nothing to delete.
  String? deleteVisit(String id) {
    final v = visit(id);
    if (v == null) return null;
    final linkedTasks = _tasks
        .where((t) => t.relatedKind == EntityKind.visit && t.relatedId == id)
        .toList();
    _visits.removeWhere((e) => e.id == id);
    _tasks.removeWhere(linkedTasks.contains);
    final title =
        '${propertyTitle(v.propertyId)} · ${formatDateTime(v.scheduledAt)}';
    final trashId = _toTrash(EntityKind.visit, title, {
      Collections.visits: [v.toJson()],
      if (linkedTasks.isNotEmpty)
        Collections.tasks: linkedTasks.map((t) => t.toJson()).toList(),
    });
    _log('Visit deleted', title, EntityKind.visit, id);
    _commit({Collections.visits, Collections.tasks, Collections.trash});
    return trashId;
  }

  List<SiteVisit> visitsForProperty(String propertyId) =>
      _visits.where((e) => e.propertyId == propertyId).toList();

  List<SiteVisit> visitsForLead(String leadId) =>
      _visits.where((e) => e.leadId == leadId).toList();

  List<SiteVisit> visitsOn(DateTime day) =>
      _visits.where((e) => DateUtilsX.isSameDay(e.scheduledAt, day)).toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  // --- tasks ---------------------------------------------------------------

  BrokerTask addTask(BrokerTask task) {
    _tasks.insert(0, task);
    _log('Follow-up added', '${task.title} · ${formatRelativeDay(task.dueAt)}',
        EntityKind.task, task.id);
    _commit({Collections.tasks});
    return task;
  }

  void updateTask(BrokerTask task) {
    _log('Follow-up updated', task.title, EntityKind.task, task.id);
    _commit({Collections.tasks});
  }

  void toggleTaskDone(BrokerTask task) {
    task.done = !task.done;
    task.completedAt = task.done ? DateTime.now() : null;
    _log(task.done ? 'Follow-up completed' : 'Follow-up reopened', task.title,
        EntityKind.task, task.id);
    _commit({Collections.tasks});
  }

  /// Moves the record to Recently deleted. Returns the bin entry's id, for
  /// an Undo button, or null if there was nothing to delete.
  String? deleteTask(String id) {
    final t = task(id);
    if (t == null) return null;
    _tasks.removeWhere((e) => e.id == id);
    final trashId = _toTrash(EntityKind.task, t.title, {
      Collections.tasks: [t.toJson()],
    });
    _log('Follow-up deleted', t.title, EntityKind.task, id);
    _commit({Collections.tasks, Collections.trash});
    return trashId;
  }

  List<BrokerTask> tasksFor(EntityKind kind, String id) => _tasks
      .where((e) => e.relatedKind == kind && e.relatedId == id)
      .toList()
    ..sort((a, b) => a.dueAt.compareTo(b.dueAt));

  List<BrokerTask> get todaysTasks => _tasks
      .where((e) => !e.done && DateUtilsX.isToday(e.dueAt))
      .toList()
    ..sort((a, b) => a.dueAt.compareTo(b.dueAt));

  List<BrokerTask> get overdueTasks => _tasks.where((e) => e.isOverdue).toList()
    ..sort((a, b) => a.dueAt.compareTo(b.dueAt));

  List<BrokerTask> get upcomingTasks => _tasks
      .where((e) =>
          !e.done &&
          e.dueAt.isAfter(DateTime.now()) &&
          !DateUtilsX.isToday(e.dueAt))
      .toList()
    ..sort((a, b) => a.dueAt.compareTo(b.dueAt));

  /// Leads whose next follow-up falls today (and is still open).
  List<Lead> get leadFollowUpsToday => _leads
      .where((l) =>
          l.status.isOpen &&
          l.nextFollowUpAt != null &&
          DateUtilsX.isToday(l.nextFollowUpAt!))
      .toList()
    ..sort((a, b) => a.nextFollowUpAt!.compareTo(b.nextFollowUpAt!));

  /// Leads whose follow-up date has passed without being moved or cleared.
  List<Lead> get overdueLeadFollowUps => _leads
      .where((l) =>
          l.isFollowUpOverdue && !DateUtilsX.isToday(l.nextFollowUpAt!))
      .toList()
    ..sort((a, b) => a.nextFollowUpAt!.compareTo(b.nextFollowUpAt!));

  /// Today's and overdue lead follow-ups that don't have a matching
  /// follow-up task (those are listed with the tasks).
  List<Lead> get leadFollowUpsWithoutTask {
    final now = DateTime.now();
    final endOfToday = DateUtilsX.startOfDay(now).add(const Duration(days: 1));
    return _leads.where((l) {
      final at = l.nextFollowUpAt;
      if (at == null || !l.status.isOpen || !at.isBefore(endOfToday)) {
        return false;
      }
      return !_tasks.any((t) =>
          !t.done &&
          t.relatedKind == EntityKind.lead &&
          t.relatedId == l.id &&
          t.dueAt.difference(at).inMinutes.abs() < 1);
    }).toList()
      ..sort((a, b) => a.nextFollowUpAt!.compareTo(b.nextFollowUpAt!));
  }

  /// Quick jots still waiting for budget, area or requirements.
  List<Lead> get incompleteLeads =>
      _leads.where((l) => l.isIncomplete).toList();

  // --- reminder actions ----------------------------------------------------

  /// Applies a Snooze / Done pressed on a notification. Returns false when
  /// the record no longer exists.
  bool applyReminderAction(ReminderAction action) {
    switch (action.kind) {
      case EntityKind.task:
        final t = task(action.entityId);
        if (t == null) return false;
        // Keep the lead's follow-up date in step with its follow-up task.
        final l = t.relatedKind == EntityKind.lead ? lead(t.relatedId) : null;
        if (l != null && l.nextFollowUpAt == t.dueAt) {
          l.nextFollowUpAt = action.type == ReminderActionType.done
              ? null
              : action.at.add(ReminderAction.snoozeFor);
          _dirty.add(Collections.leads);
        }
        if (action.type == ReminderActionType.done) {
          if (!t.done) {
            t.done = true;
            t.completedAt = action.at;
            _log('Follow-up completed', '${t.title} (from notification)',
                EntityKind.task, t.id);
          }
        } else {
          t.dueAt = action.at.add(ReminderAction.snoozeFor);
          _log('Follow-up snoozed', '${t.title} → ${formatDateTime(t.dueAt)}',
              EntityKind.task, t.id);
        }
        _commit({Collections.tasks});
        return true;
      case EntityKind.lead:
        final l = lead(action.entityId);
        if (l == null) return false;
        if (action.type == ReminderActionType.done) {
          l.nextFollowUpAt = null;
          if (l.status == LeadStatus.newLead) l.status = LeadStatus.contacted;
          _log('Follow-up done', '${l.name} (from notification)',
              EntityKind.lead, l.id);
        } else {
          l.nextFollowUpAt = action.at.add(ReminderAction.snoozeFor);
          _log('Follow-up snoozed',
              '${l.name} → ${formatDateTime(l.nextFollowUpAt)}',
              EntityKind.lead, l.id);
        }
        _commit({Collections.leads});
        return true;
      default:
        return false;
    }
  }

  // --- deals and commission ------------------------------------------------

  Deal addDeal(Deal deal) {
    _deals.insert(0, deal);
    _log('Deal created', '${deal.title} · ${formatMoney(deal.agreedValue)}',
        EntityKind.deal, deal.id);
    _commit({Collections.deals});
    return deal;
  }

  void updateDeal(Deal deal) {
    _log('Deal updated', deal.title, EntityKind.deal, deal.id);
    _commit({Collections.deals});
  }

  void setDealStage(Deal deal, DealStage stage) {
    if (deal.stage == stage) return;
    deal.stage = stage;
    deal.closedAt = stage.isOpen ? null : DateTime.now();
    final linked = lead(deal.leadId);
    if (linked != null) {
      if (stage == DealStage.closedWon) linked.status = LeadStatus.won;
      if (stage == DealStage.closedLost) linked.status = LeadStatus.lost;
    }
    final prop = property(deal.propertyId);
    if (prop != null && stage == DealStage.closedWon) {
      prop.status = prop.listing == ListingType.rent
          ? PropertyStatus.rented
          : PropertyStatus.sold;
    }
    _log('Deal stage changed', '${deal.title} → ${stage.label}',
        EntityKind.deal, deal.id);
    _commit({Collections.deals, Collections.leads, Collections.properties});
  }

  /// Moves the record to Recently deleted. Returns the bin entry's id, for
  /// an Undo button, or null if there was nothing to delete.
  String? deleteDeal(String id) {
    final d = deal(id);
    if (d == null) return null;
    final linked = _payments.where((e) => e.dealId == id).toList();
    _deals.removeWhere((e) => e.id == id);
    _payments.removeWhere((e) => e.dealId == id);
    final trashId = _toTrash(EntityKind.deal, d.title, {
      Collections.deals: [d.toJson()],
      if (linked.isNotEmpty)
        Collections.payments: linked.map((e) => e.toJson()).toList(),
    });
    _log('Deal deleted', d.title, EntityKind.deal, id);
    _commit({Collections.deals, Collections.payments, Collections.trash});
    return trashId;
  }

  List<PaymentRecord> paymentsForDeal(String dealId) =>
      _payments.where((e) => e.dealId == dealId).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  PaymentRecord addPayment(PaymentRecord payment) {
    _payments.add(payment);
    _log('Commission record added',
        '${formatMoney(payment.amount)} due ${formatDate(payment.dueDate)}',
        EntityKind.payment, payment.id);
    _commit({Collections.payments});
    return payment;
  }

  void togglePaymentPaid(PaymentRecord payment) {
    if (payment.isPaid) {
      payment.status = PaymentStatus.pending;
      payment.paidDate = null;
    } else {
      payment.status = PaymentStatus.paid;
      payment.paidDate = DateTime.now();
    }
    _log(payment.isPaid ? 'Commission received' : 'Payment marked pending',
        formatMoney(payment.amount), EntityKind.payment, payment.id);
    _commit({Collections.payments});
  }

  /// Moves the record to Recently deleted. Returns the bin entry's id, for
  /// an Undo button, or null if there was nothing to delete.
  String? deletePayment(String id) {
    final pay = payment(id);
    if (pay == null) return null;
    _payments.removeWhere((e) => e.id == id);
    final title = '${formatMoney(pay.amount)} · ${deal(pay.dealId)?.title ?? ''}';
    final trashId = _toTrash(EntityKind.payment, title, {
      Collections.payments: [pay.toJson()],
    });
    _log('Commission record deleted', title, EntityKind.payment, id);
    _commit({Collections.payments, Collections.trash});
    return trashId;
  }

  double commissionReceivedFor(String dealId) => paymentsForDeal(dealId)
      .where((e) => e.isPaid)
      .fold<double>(0, (sum, e) => sum + e.amount);

  double commissionPendingFor(Deal deal) {
    final pending = deal.expectedCommission - commissionReceivedFor(deal.id);
    return pending < 0 ? 0 : pending;
  }

  double get totalExpectedCommission => _deals
      .where((d) => d.stage != DealStage.closedLost)
      .fold<double>(0, (sum, d) => sum + d.expectedCommission);

  double get totalReceivedCommission =>
      _payments.where((e) => e.isPaid).fold<double>(0, (s, e) => s + e.amount);

  double get totalPendingCommission {
    final pending = totalExpectedCommission - totalReceivedCommission;
    return pending < 0 ? 0 : pending;
  }

  // --- documents -----------------------------------------------------------

  DocumentRecord addDocument(DocumentRecord doc) {
    _documents.insert(0, doc);
    _log(doc.missing ? 'Document requested' : 'Document added',
        '${doc.name} (${doc.kind.label})', EntityKind.document, doc.id);
    _commit({Collections.documents});
    return doc;
  }

  void updateDocument(DocumentRecord doc) {
    _log('Document updated', doc.name, EntityKind.document, doc.id);
    _commit({Collections.documents});
  }

  /// Moves the record to Recently deleted. Returns the bin entry's id, for
  /// an Undo button, or null if there was nothing to delete.
  String? deleteDocument(String id) {
    final d = document(id);
    if (d == null) return null;
    _documents.removeWhere((e) => e.id == id);
    final trashId = _toTrash(EntityKind.document, d.name, {
      Collections.documents: [d.toJson()],
    });
    _log('Document deleted', d.name, EntityKind.document, id);
    _commit({Collections.documents, Collections.trash});
    return trashId;
  }

  /// Attaches the real file to a placeholder that was waiting for it.
  void markDocumentCollected(DocumentRecord doc,
      {String? file, int? sizeKb, String? name}) {
    doc.missing = false;
    doc.uploadedAt = DateTime.now();
    if (file != null) doc.file = file;
    if (sizeKb != null) doc.sizeKb = sizeKb;
    if (name != null && name.isNotEmpty) doc.name = name;
    _log('Document collected', doc.name, EntityKind.document, doc.id);
    _commit({Collections.documents});
  }

  List<DocumentRecord> documentsFor(EntityKind kind, String id) =>
      _documents.where((e) {
        return switch (kind) {
          EntityKind.property => e.propertyId == id,
          EntityKind.contact => e.contactId == id,
          EntityKind.deal => e.dealId == id,
          _ => false,
        };
      }).toList();

  List<DocumentRecord> get missingDocuments =>
      _documents.where((e) => e.missing).toList();

  // --- recently deleted ----------------------------------------------------

  String _toTrash(EntityKind kind, String title,
      Map<String, List<Map<String, dynamic>>> records) {
    final entry =
        TrashEntry(id: nextId('tr'), kind: kind, title: title, records: records);
    _trash.insert(0, entry);
    return entry.id;
  }

  /// Puts a deleted record (and anything deleted with it) back.
  bool restoreFromTrash(String trashId) {
    final entry = _firstWhereOrNull(_trash, (e) => e.id == trashId);
    if (entry == null) return false;
    final touched = <String>{Collections.trash};
    entry.records.forEach((name, rows) {
      for (final row in rows) {
        if (_reinsert(name, row)) touched.add(name);
      }
    });
    _trash.remove(entry);
    _log('Restored', entry.title, entry.kind, null);
    _commit(touched);
    return true;
  }

  bool _reinsert(String name, Map<String, dynamic> row) {
    final id = row['id']?.toString();
    bool absent<T>(List<T> list, String Function(T) idOf) =>
        id != null && !list.any((e) => idOf(e) == id);
    switch (name) {
      case Collections.leads when absent(_leads, (e) => e.id):
        _leads.insert(0, Lead.fromJson(row));
      case Collections.contacts when absent(_contacts, (e) => e.id):
        _contacts.insert(0, Contact.fromJson(row));
      case Collections.properties when absent(_properties, (e) => e.id):
        _properties.insert(0, Property.fromJson(row));
      case Collections.visits when absent(_visits, (e) => e.id):
        _visits.insert(0, SiteVisit.fromJson(row));
      case Collections.tasks when absent(_tasks, (e) => e.id):
        _tasks.insert(0, BrokerTask.fromJson(row));
      case Collections.deals when absent(_deals, (e) => e.id):
        _deals.insert(0, Deal.fromJson(row));
      case Collections.payments when absent(_payments, (e) => e.id):
        _payments.add(PaymentRecord.fromJson(row));
      case Collections.documents when absent(_documents, (e) => e.id):
        _documents.insert(0, DocumentRecord.fromJson(row));
      default:
        return false;
    }
    return true;
  }

  /// Deletes a trashed record for good, including its photo or file.
  Future<void> deleteForever(String trashId) async {
    final entry = _firstWhereOrNull(_trash, (e) => e.id == trashId);
    if (entry == null) return;
    _trash.remove(entry);
    await _deleteFiles(_filesIn(entry).toList());
    _commit({Collections.trash});
  }

  Future<void> emptyTrash() async {
    if (_trash.isEmpty) return;
    final files = _trash.expand(_filesIn).toList();
    _trash.clear();
    await _deleteFiles(files);
    _log('Recently deleted emptied', '', EntityKind.document, null);
    _commit({Collections.trash});
  }

  Future<void> _purgeExpiredTrash() async {
    final now = DateTime.now();
    final expired = _trash.where((e) => e.purgeAt.isBefore(now)).toList();
    if (expired.isEmpty) return;
    _trash.removeWhere(expired.contains);
    await _deleteFiles(expired.expand(_filesIn).toList());
    _dirty.add(Collections.trash);
    unawaited(flush());
  }

  static Iterable<String> _filesIn(TrashEntry entry) sync* {
    for (final row in entry.records[Collections.documents] ?? const []) {
      final f = row['file'];
      if (f is String && f.isNotEmpty) yield f;
    }
    for (final row in entry.records[Collections.properties] ?? const []) {
      final f = row['photo'];
      if (f is String && f.isNotEmpty) yield f;
    }
  }

  /// Every attachment something still points at — live or in the bin.
  Set<String> get referencedFiles => {
        for (final d in _documents)
          if (d.file != null) d.file!,
        for (final p in _properties)
          if (p.photo != null) p.photo!,
        for (final t in _trash) ..._filesIn(t),
      };

  Future<void> _deleteFiles(List<String> names) async {
    final dir = _storage.attachmentsDir;
    if (dir == null) return;
    for (final name in names) {
      try {
        final f = File(p.join(dir.path, p.basename(name)));
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Removes files nothing points at any more — a photo replaced in a form,
  /// or one picked for a form that was then cancelled. Only files older than
  /// a day, so a form still open in the background keeps its pick.
  Future<void> _sweepOrphanAttachments() async {
    final dir = _storage.attachmentsDir;
    if (dir == null || !await dir.exists()) return;
    final keep = referencedFiles;
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (keep.contains(p.basename(entity.path))) continue;
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {}
    }
  }

  // --- search --------------------------------------------------------------

  /// One query across leads, contacts and properties.
  SearchResults search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return const SearchResults(leads: [], contacts: [], properties: []);
    }
    final digits = q.replaceAll(RegExp(r'\D'), '');
    bool phoneHit(String phone) =>
        digits.length >= 3 && phone.replaceAll(RegExp(r'\D'), '').contains(digits);

    return SearchResults(
      leads: _leads
          .where((e) =>
              e.name.toLowerCase().contains(q) ||
              phoneHit(e.phone) ||
              e.preferredLocation.toLowerCase().contains(q) ||
              e.requirements.toLowerCase().contains(q) ||
              e.notes.toLowerCase().contains(q))
          .toList(),
      contacts: _contacts
          .where((e) =>
              e.name.toLowerCase().contains(q) ||
              phoneHit(e.phone) ||
              e.email.toLowerCase().contains(q) ||
              e.locality.toLowerCase().contains(q) ||
              e.notes.toLowerCase().contains(q))
          .toList(),
      properties: _properties
          .where((e) =>
              e.title.toLowerCase().contains(q) ||
              e.address.toLowerCase().contains(q) ||
              e.locality.toLowerCase().contains(q) ||
              e.city.toLowerCase().contains(q) ||
              e.notes.toLowerCase().contains(q) ||
              e.features.any((f) => f.toLowerCase().contains(q)))
          .toList(),
    );
  }

  // --- dashboard figures ---------------------------------------------------

  List<Lead> get openLeads => _leads.where((e) => e.status.isOpen).toList();

  List<Lead> get newLeadsThisWeek => _leads
      .where((e) =>
          e.createdAt.isAfter(DateTime.now().subtract(const Duration(days: 7))))
      .toList();

  List<SiteVisit> get upcomingVisits => _visits
      .where((e) => e.isUpcoming)
      .toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  List<Deal> get openDeals => _deals.where((e) => e.stage.isOpen).toList();

  int get dealsWon =>
      _deals.where((e) => e.stage == DealStage.closedWon).length;

  int get dealsLost =>
      _deals.where((e) => e.stage == DealStage.closedLost).length;

  Map<LeadStatus, int> get leadsByStage {
    final map = {for (final s in LeadStatus.values) s: 0};
    for (final l in _leads) {
      map[l.status] = (map[l.status] ?? 0) + 1;
    }
    return map;
  }

  Map<LeadSource, int> get leadsBySource {
    final map = {for (final s in LeadSource.values) s: 0};
    for (final l in _leads) {
      map[l.source] = (map[l.source] ?? 0) + 1;
    }
    return map;
  }

  Map<PropertyStatus, int> get propertiesByStatus {
    final map = {for (final s in PropertyStatus.values) s: 0};
    for (final p in _properties) {
      map[p.status] = (map[p.status] ?? 0) + 1;
    }
    return map;
  }

  /// Share of open leads that have a next action recorded.
  double get leadsWithNextActionRatio {
    final open = openLeads;
    if (open.isEmpty) return 0;
    final withAction = open.where((l) =>
        l.nextFollowUpAt != null ||
        _tasks.any((t) =>
            !t.done && t.relatedKind == EntityKind.lead && t.relatedId == l.id));
    return withAction.length / open.length;
  }

  // --- activity log --------------------------------------------------------

  void recordActivity(
      String action, String summary, EntityKind kind, String? entityId) {
    _log(action, summary, kind, entityId);
    _commit(const {});
  }

  void _log(String action, String summary, EntityKind kind, String? entityId) {
    _activities.insert(
      0,
      ActivityEntry(
        id: nextId('act'),
        action: action,
        summary: summary,
        entityKind: kind,
        entityId: entityId,
        at: DateTime.now(),
      ),
    );
    if (_activities.length > _maxActivity) {
      _activities.removeRange(_maxActivity, _activities.length);
    }
  }

  // --- helpers -------------------------------------------------------------

  /// A new, globally unique id. Random (not sequential) so records from a
  /// restored backup can never collide with ones created since.
  String nextId(String prefix) => '$prefix-${_uuid.v4()}';

  static bool samePhone(String a, String b) {
    String tail(String s) {
      final digits = s.replaceAll(RegExp(r'\D'), '');
      return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
    }

    final ta = tail(a);
    return ta.isNotEmpty && ta == tail(b);
  }
}

class SearchResults {
  const SearchResults({
    required this.leads,
    required this.contacts,
    required this.properties,
  });

  final List<Lead> leads;
  final List<Contact> contacts;
  final List<Property> properties;

  int get total => leads.length + contacts.length + properties.length;
  bool get isEmpty => total == 0;
}

T? _firstWhereOrNull<T>(List<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}
