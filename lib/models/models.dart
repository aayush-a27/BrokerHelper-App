import 'enums.dart';

export 'enums.dart';

// ---------------------------------------------------------------------------
// JSON coercion helpers. The diary files live on the phone and are written by
// this app, but these keep one bad value (an older app version, a damaged
// backup) from making the whole diary unreadable.
// ---------------------------------------------------------------------------

String _str(Object? v, [String fallback = '']) => v?.toString() ?? fallback;

String? _strOrNull(Object? v) {
  final s = v?.toString();
  return s == null || s.isEmpty ? null : s;
}

int _int(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(_str(v)) ?? fallback;
}

double _dbl(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  return double.tryParse(_str(v)) ?? fallback;
}

bool _bool(Object? v, [bool fallback = false]) {
  if (v is bool) return v;
  final s = _str(v).toLowerCase();
  if (s == 'true') return true;
  if (s == 'false') return false;
  return fallback;
}

DateTime? _dateOrNull(Object? v) {
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  final s = _str(v);
  return s.isEmpty ? null : DateTime.tryParse(s)?.toLocal();
}

DateTime _date(Object? v) => _dateOrNull(v) ?? DateTime.now();

/// Dates are stored as UTC ISO-8601, so a diary restored on a phone in
/// another time zone still means the same instant.
String _iso(DateTime d) => d.toUtc().toIso8601String();
String? _isoOrNull(DateTime? d) => d == null ? null : _iso(d);

List<String> _strList(Object? v) =>
    v is List ? v.map((e) => e.toString()).toList() : <String>[];

List<Map<String, dynamic>> _mapList(Object? v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Drops null values so the files on disk stay small.
Map<String, dynamic> _compact(Map<String, dynamic> m) =>
    m..removeWhere((_, v) => v == null);

// ---------------------------------------------------------------------------
// Entities
// ---------------------------------------------------------------------------

/// The broker who owns this phone. There is exactly one, set up on first
/// launch; buyers and sellers are [Contact]s.
class BrokerProfile {
  BrokerProfile({
    required this.name,
    this.phone = '',
    this.email = '',
    this.agency = '',
    this.reraNumber = '',
  });

  String name;
  String phone;
  String email;
  String agency;
  String reraNumber;

  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  factory BrokerProfile.fromJson(Map<String, dynamic> j) => BrokerProfile(
        name: _str(j['name']),
        phone: _str(j['phone']),
        email: _str(j['email']),
        agency: _str(j['agency']),
        reraNumber: _str(j['reraNumber']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'email': email,
        'agency': agency,
        'reraNumber': reraNumber,
      };
}

/// Buyer-specific requirements held on a contact.
class BuyerProfile {
  BuyerProfile({
    this.budgetMin = 0,
    this.budgetMax = 0,
    List<String>? preferredLocations,
    List<PropertyType>? propertyTypes,
    this.bedrooms = 0,
    List<String>? mustHaves,
  })  : preferredLocations = preferredLocations ?? <String>[],
        propertyTypes = propertyTypes ?? <PropertyType>[],
        mustHaves = mustHaves ?? <String>[];

  double budgetMin;
  double budgetMax;
  List<String> preferredLocations;
  List<PropertyType> propertyTypes;
  int bedrooms;
  List<String> mustHaves;

  factory BuyerProfile.fromJson(Map<String, dynamic> j) => BuyerProfile(
        budgetMin: _dbl(j['budgetMin']),
        budgetMax: _dbl(j['budgetMax']),
        preferredLocations: _strList(j['preferredLocations']),
        propertyTypes: _strList(j['propertyTypes'])
            .map((e) => enumFromName(
                PropertyType.values, e, PropertyType.apartment))
            .toList(),
        bedrooms: _int(j['bedrooms']),
        mustHaves: _strList(j['mustHaves']),
      );

  Map<String, dynamic> toJson() => {
        'budgetMin': budgetMin,
        'budgetMax': budgetMax,
        'preferredLocations': preferredLocations,
        'propertyTypes': propertyTypes.map((e) => e.name).toList(),
        'bedrooms': bedrooms,
        'mustHaves': mustHaves,
      };
}

/// Seller-specific fields held on a contact.
class SellerProfile {
  SellerProfile({
    this.askingPrice = 0,
    this.expectedMinPrice = 0,
    this.preferredContactTime = '',
    List<String>? propertyIds,
  }) : propertyIds = propertyIds ?? <String>[];

  double askingPrice;
  double expectedMinPrice;
  String preferredContactTime;
  List<String> propertyIds;

  factory SellerProfile.fromJson(Map<String, dynamic> j) => SellerProfile(
        askingPrice: _dbl(j['askingPrice']),
        expectedMinPrice: _dbl(j['expectedMinPrice']),
        preferredContactTime: _str(j['preferredContactTime']),
        propertyIds: _strList(j['propertyIds']),
      );

  Map<String, dynamic> toJson() => {
        'askingPrice': askingPrice,
        'expectedMinPrice': expectedMinPrice,
        'preferredContactTime': preferredContactTime,
        'propertyIds': propertyIds,
      };
}

/// One logged conversation with a contact.
class Interaction {
  Interaction({required this.at, required this.channel, required this.note});

  final DateTime at;
  final String channel;
  final String note;

  factory Interaction.fromJson(Map<String, dynamic> j) => Interaction(
        at: _date(j['at']),
        channel: _str(j['channel'], 'Call'),
        note: _str(j['note']),
      );

  Map<String, dynamic> toJson() =>
      {'at': _iso(at), 'channel': channel, 'note': note};
}

/// A buyer and/or seller. One person, one record.
class Contact {
  Contact({
    required this.id,
    required this.name,
    required this.phone,
    this.email = '',
    this.role = ContactRole.buyer,
    this.locality = '',
    this.notes = '',
    DateTime? createdAt,
    BuyerProfile? buyer,
    SellerProfile? seller,
    List<Interaction>? interactions,
  })  : createdAt = createdAt ?? DateTime.now(),
        buyer = buyer ?? BuyerProfile(),
        seller = seller ?? SellerProfile(),
        interactions = interactions ?? <Interaction>[];

  final String id;
  String name;
  String phone;
  String email;
  ContactRole role;
  String locality;
  String notes;
  DateTime createdAt;
  BuyerProfile buyer;
  SellerProfile seller;
  List<Interaction> interactions;

  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
        id: _str(j['id']),
        name: _str(j['name']),
        phone: _str(j['phone']),
        email: _str(j['email']),
        role: enumFromName(ContactRole.values, j['role'], ContactRole.buyer),
        locality: _str(j['locality']),
        notes: _str(j['notes']),
        createdAt: _date(j['createdAt']),
        buyer: BuyerProfile.fromJson(_map(j['buyer'])),
        seller: SellerProfile.fromJson(_map(j['seller'])),
        interactions:
            _mapList(j['interactions']).map(Interaction.fromJson).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'role': role.name,
        'locality': locality,
        'notes': notes,
        'createdAt': _iso(createdAt),
        'buyer': buyer.toJson(),
        'seller': seller.toJson(),
        'interactions': interactions.map((e) => e.toJson()).toList(),
      };
}

/// A unit of inventory the broker can offer.
class Property {
  Property({
    required this.id,
    required this.title,
    this.type = PropertyType.apartment,
    this.listing = ListingType.sale,
    this.status = PropertyStatus.available,
    this.address = '',
    this.locality = '',
    this.city = '',
    this.areaSqft = 0,
    this.bedrooms = 0,
    this.bathrooms = 0,
    this.price = 0,
    this.photo,
    this.ownerContactId,
    this.source = '',
    List<String>? features,
    this.visitInstructions = '',
    this.notes = '',
    DateTime? createdAt,
    List<String>? interestedContactIds,
  })  : features = features ?? <String>[],
        interestedContactIds = interestedContactIds ?? <String>[],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String title;
  PropertyType type;
  ListingType listing;
  PropertyStatus status;
  String address;
  String locality;
  String city;
  int areaSqft;
  int bedrooms;
  int bathrooms;
  double price;

  /// File name of the cover photo inside the app's attachments folder.
  /// Stored relative so a backup restored on another phone still resolves.
  String? photo;
  String? ownerContactId;
  String source;
  List<String> features;
  String visitInstructions;
  String notes;
  DateTime createdAt;

  /// Several buyers may be interested in the same property — we link ids
  /// rather than duplicating the property record.
  List<String> interestedContactIds;

  String get shortAddress =>
      [locality, city].where((e) => e.isNotEmpty).join(', ');

  factory Property.fromJson(Map<String, dynamic> j) => Property(
        id: _str(j['id']),
        title: _str(j['title']),
        type: enumFromName(PropertyType.values, j['type'], PropertyType.apartment),
        listing: enumFromName(ListingType.values, j['listing'], ListingType.sale),
        status: enumFromName(
            PropertyStatus.values, j['status'], PropertyStatus.available),
        address: _str(j['address']),
        locality: _str(j['locality']),
        city: _str(j['city']),
        areaSqft: _int(j['areaSqft']),
        bedrooms: _int(j['bedrooms']),
        bathrooms: _int(j['bathrooms']),
        price: _dbl(j['price']),
        photo: _strOrNull(j['photo']),
        ownerContactId: _strOrNull(j['ownerContactId']),
        source: _str(j['source']),
        features: _strList(j['features']),
        visitInstructions: _str(j['visitInstructions']),
        notes: _str(j['notes']),
        createdAt: _date(j['createdAt']),
        interestedContactIds: _strList(j['interestedContactIds']),
      );

  Map<String, dynamic> toJson() => _compact({
        'id': id,
        'title': title,
        'type': type.name,
        'listing': listing.name,
        'status': status.name,
        'address': address,
        'locality': locality,
        'city': city,
        'areaSqft': areaSqft,
        'bedrooms': bedrooms,
        'bathrooms': bathrooms,
        'price': price,
        'photo': photo,
        'ownerContactId': ownerContactId,
        'source': source,
        'features': features,
        'visitInstructions': visitInstructions,
        'notes': notes,
        'createdAt': _iso(createdAt),
        'interestedContactIds': interestedContactIds,
      });
}

/// An enquiry moving towards a next step.
class Lead {
  Lead({
    required this.id,
    required this.name,
    required this.phone,
    this.email = '',
    this.source = LeadSource.phoneCall,
    this.status = LeadStatus.newLead,
    this.priority = Priority.medium,
    this.budgetMin = 0,
    this.budgetMax = 0,
    this.preferredLocation = '',
    this.propertyType = PropertyType.apartment,
    this.bedrooms = 0,
    this.requirements = '',
    this.contactId,
    this.notes = '',
    this.nextFollowUpAt,
    DateTime? createdAt,
    List<String>? sharedPropertyIds,
    List<String>? shortlistedPropertyIds,
  })  : createdAt = createdAt ?? DateTime.now(),
        sharedPropertyIds = sharedPropertyIds ?? <String>[],
        shortlistedPropertyIds = shortlistedPropertyIds ?? <String>[];

  final String id;
  String name;
  String phone;
  String email;
  LeadSource source;
  LeadStatus status;
  Priority priority;
  double budgetMin;
  double budgetMax;
  String preferredLocation;
  PropertyType propertyType;
  int bedrooms;
  String requirements;
  String? contactId;
  String notes;
  DateTime? nextFollowUpAt;
  DateTime createdAt;
  List<String> sharedPropertyIds;
  List<String> shortlistedPropertyIds;

  bool get isFollowUpOverdue =>
      nextFollowUpAt != null &&
      status.isOpen &&
      nextFollowUpAt!.isBefore(DateTime.now());

  /// A quick jot — name and number only — still waiting for the details.
  bool get isIncomplete =>
      status.isOpen &&
      budgetMax <= 0 &&
      preferredLocation.trim().isEmpty &&
      requirements.trim().isEmpty;

  factory Lead.fromJson(Map<String, dynamic> j) => Lead(
        id: _str(j['id']),
        name: _str(j['name']),
        phone: _str(j['phone']),
        email: _str(j['email']),
        source: enumFromName(LeadSource.values, j['source'], LeadSource.other),
        status: enumFromName(LeadStatus.values, j['status'], LeadStatus.newLead),
        priority: enumFromName(Priority.values, j['priority'], Priority.medium),
        budgetMin: _dbl(j['budgetMin']),
        budgetMax: _dbl(j['budgetMax']),
        preferredLocation: _str(j['preferredLocation']),
        propertyType: enumFromName(
            PropertyType.values, j['propertyType'], PropertyType.apartment),
        bedrooms: _int(j['bedrooms']),
        requirements: _str(j['requirements']),
        contactId: _strOrNull(j['contactId']),
        notes: _str(j['notes']),
        nextFollowUpAt: _dateOrNull(j['nextFollowUpAt']),
        createdAt: _date(j['createdAt']),
        sharedPropertyIds: _strList(j['sharedPropertyIds']),
        shortlistedPropertyIds: _strList(j['shortlistedPropertyIds']),
      );

  Map<String, dynamic> toJson() => _compact({
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'source': source.name,
        'status': status.name,
        'priority': priority.name,
        'budgetMin': budgetMin,
        'budgetMax': budgetMax,
        'preferredLocation': preferredLocation,
        'propertyType': propertyType.name,
        'bedrooms': bedrooms,
        'requirements': requirements,
        'contactId': contactId,
        'notes': notes,
        'nextFollowUpAt': _isoOrNull(nextFollowUpAt),
        'createdAt': _iso(createdAt),
        'sharedPropertyIds': sharedPropertyIds,
        'shortlistedPropertyIds': shortlistedPropertyIds,
      });
}

/// A scheduled viewing.
class SiteVisit {
  SiteVisit({
    required this.id,
    required this.propertyId,
    this.contactId,
    this.leadId,
    required this.scheduledAt,
    this.status = VisitStatus.scheduled,
    this.outcome = VisitOutcome.pending,
    this.feedback = '',
    this.notes = '',
  });

  final String id;
  String propertyId;
  String? contactId;
  String? leadId;
  DateTime scheduledAt;
  VisitStatus status;
  VisitOutcome outcome;
  String feedback;
  String notes;

  bool get isUpcoming =>
      scheduledAt.isAfter(DateTime.now()) &&
      status != VisitStatus.cancelled &&
      status != VisitStatus.completed;

  factory SiteVisit.fromJson(Map<String, dynamic> j) => SiteVisit(
        id: _str(j['id']),
        propertyId: _str(j['propertyId']),
        contactId: _strOrNull(j['contactId']),
        leadId: _strOrNull(j['leadId']),
        scheduledAt: _date(j['scheduledAt']),
        status:
            enumFromName(VisitStatus.values, j['status'], VisitStatus.scheduled),
        outcome: enumFromName(
            VisitOutcome.values, j['outcome'], VisitOutcome.pending),
        feedback: _str(j['feedback']),
        notes: _str(j['notes']),
      );

  Map<String, dynamic> toJson() => _compact({
        'id': id,
        'propertyId': propertyId,
        'contactId': contactId,
        'leadId': leadId,
        'scheduledAt': _iso(scheduledAt),
        'status': status.name,
        'outcome': outcome.name,
        'feedback': feedback,
        'notes': notes,
      });
}

/// A reminder or follow-up. Can hang off any other record.
class BrokerTask {
  BrokerTask({
    required this.id,
    required this.title,
    this.type = TaskType.call,
    required this.dueAt,
    this.done = false,
    this.relatedKind,
    this.relatedId,
    this.notes = '',
    this.completedAt,
  });

  final String id;
  String title;
  TaskType type;
  DateTime dueAt;
  bool done;
  EntityKind? relatedKind;
  String? relatedId;
  String notes;
  DateTime? completedAt;

  bool get isOverdue => !done && dueAt.isBefore(DateTime.now());

  factory BrokerTask.fromJson(Map<String, dynamic> j) => BrokerTask(
        id: _str(j['id']),
        title: _str(j['title']),
        type: enumFromName(TaskType.values, j['type'], TaskType.other),
        dueAt: _date(j['dueAt']),
        done: _bool(j['done']),
        relatedKind: j['relatedKind'] == null
            ? null
            : enumFromName(EntityKind.values, j['relatedKind'], EntityKind.lead),
        relatedId: _strOrNull(j['relatedId']),
        notes: _str(j['notes']),
        completedAt: _dateOrNull(j['completedAt']),
      );

  Map<String, dynamic> toJson() => _compact({
        'id': id,
        'title': title,
        'type': type.name,
        'dueAt': _iso(dueAt),
        'done': done,
        'relatedKind': relatedKind?.name,
        'relatedId': relatedId,
        'notes': notes,
        'completedAt': _isoOrNull(completedAt),
      });
}

/// One step in a deal's progress.
class Milestone {
  Milestone({required this.label, this.at, this.done = false});

  String label;
  DateTime? at;
  bool done;

  factory Milestone.fromJson(Map<String, dynamic> j) => Milestone(
        label: _str(j['label']),
        at: _dateOrNull(j['at']),
        done: _bool(j['done']),
      );

  Map<String, dynamic> toJson() =>
      _compact({'label': label, 'at': _isoOrNull(at), 'done': done});
}

/// A transaction linking buyer, seller and property.
class Deal {
  Deal({
    required this.id,
    required this.title,
    this.propertyId,
    this.buyerContactId,
    this.sellerContactId,
    this.leadId,
    this.stage = DealStage.prospect,
    this.agreedValue = 0,
    this.tokenAmount = 0,
    this.commissionType = CommissionType.percentage,
    this.commissionValue = 2,
    this.closedAt,
    DateTime? createdAt,
    List<Milestone>? milestones,
    this.notes = '',
  })  : createdAt = createdAt ?? DateTime.now(),
        milestones = milestones ?? <Milestone>[];

  final String id;
  String title;
  String? propertyId;
  String? buyerContactId;
  String? sellerContactId;
  String? leadId;
  DealStage stage;
  double agreedValue;
  double tokenAmount;
  CommissionType commissionType;

  /// A rupee amount when [commissionType] is fixed, otherwise a percentage.
  double commissionValue;
  DateTime? closedAt;
  DateTime createdAt;
  List<Milestone> milestones;
  String notes;

  /// Commission the broker expects on this deal, as agreed by the parties.
  double get expectedCommission => commissionType == CommissionType.fixed
      ? commissionValue
      : agreedValue * commissionValue / 100;

  factory Deal.fromJson(Map<String, dynamic> j) => Deal(
        id: _str(j['id']),
        title: _str(j['title']),
        propertyId: _strOrNull(j['propertyId']),
        buyerContactId: _strOrNull(j['buyerContactId']),
        sellerContactId: _strOrNull(j['sellerContactId']),
        leadId: _strOrNull(j['leadId']),
        stage: enumFromName(DealStage.values, j['stage'], DealStage.prospect),
        agreedValue: _dbl(j['agreedValue']),
        tokenAmount: _dbl(j['tokenAmount']),
        commissionType: enumFromName(CommissionType.values, j['commissionType'],
            CommissionType.percentage),
        commissionValue: _dbl(j['commissionValue']),
        closedAt: _dateOrNull(j['closedAt']),
        createdAt: _date(j['createdAt']),
        milestones: _mapList(j['milestones']).map(Milestone.fromJson).toList(),
        notes: _str(j['notes']),
      );

  Map<String, dynamic> toJson() => _compact({
        'id': id,
        'title': title,
        'propertyId': propertyId,
        'buyerContactId': buyerContactId,
        'sellerContactId': sellerContactId,
        'leadId': leadId,
        'stage': stage.name,
        'agreedValue': agreedValue,
        'tokenAmount': tokenAmount,
        'commissionType': commissionType.name,
        'commissionValue': commissionValue,
        'closedAt': _isoOrNull(closedAt),
        'createdAt': _iso(createdAt),
        'milestones': milestones.map((e) => e.toJson()).toList(),
        'notes': notes,
      });
}

/// A commission instalment against a deal.
class PaymentRecord {
  PaymentRecord({
    required this.id,
    required this.dealId,
    this.amount = 0,
    required this.dueDate,
    this.paidDate,
    this.status = PaymentStatus.pending,
    this.note = '',
  });

  final String id;
  String dealId;
  double amount;
  DateTime dueDate;
  DateTime? paidDate;
  PaymentStatus status;
  String note;

  bool get isPaid => status == PaymentStatus.paid;

  factory PaymentRecord.fromJson(Map<String, dynamic> j) => PaymentRecord(
        id: _str(j['id']),
        dealId: _str(j['dealId']),
        amount: _dbl(j['amount']),
        dueDate: _date(j['dueDate']),
        paidDate: _dateOrNull(j['paidDate']),
        status: enumFromName(
            PaymentStatus.values, j['status'], PaymentStatus.pending),
        note: _str(j['note']),
      );

  Map<String, dynamic> toJson() => _compact({
        'id': id,
        'dealId': dealId,
        'amount': amount,
        'dueDate': _iso(dueDate),
        'paidDate': _isoOrNull(paidDate),
        'status': status.name,
        'note': note,
      });
}

/// A file kept in the diary's attachments folder, or a placeholder for one
/// the broker still has to collect.
class DocumentRecord {
  DocumentRecord({
    required this.id,
    required this.name,
    this.kind = DocumentKind.other,
    this.sizeKb = 0,
    this.file,
    DateTime? uploadedAt,
    this.propertyId,
    this.contactId,
    this.dealId,
    this.expiryDate,
    this.missing = false,
  }) : uploadedAt = uploadedAt ?? DateTime.now();

  final String id;
  String name;
  DocumentKind kind;
  int sizeKb;

  /// File name inside the attachments folder; null for a missing document.
  String? file;
  DateTime uploadedAt;
  String? propertyId;
  String? contactId;
  String? dealId;
  DateTime? expiryDate;

  /// A placeholder row for a document the broker still has to collect.
  bool missing;

  bool get isExpiringSoon {
    final e = expiryDate;
    if (e == null) return false;
    final days = e.difference(DateTime.now()).inDays;
    return days >= 0 && days <= 30;
  }

  factory DocumentRecord.fromJson(Map<String, dynamic> j) => DocumentRecord(
        id: _str(j['id']),
        name: _str(j['name']),
        kind: enumFromName(DocumentKind.values, j['kind'], DocumentKind.other),
        sizeKb: _int(j['sizeKb']),
        file: _strOrNull(j['file']),
        uploadedAt: _date(j['uploadedAt']),
        propertyId: _strOrNull(j['propertyId']),
        contactId: _strOrNull(j['contactId']),
        dealId: _strOrNull(j['dealId']),
        expiryDate: _dateOrNull(j['expiryDate']),
        missing: _bool(j['missing']),
      );

  Map<String, dynamic> toJson() => _compact({
        'id': id,
        'name': name,
        'kind': kind.name,
        'sizeKb': sizeKb,
        'file': file,
        'uploadedAt': _iso(uploadedAt),
        'propertyId': propertyId,
        'contactId': contactId,
        'dealId': dealId,
        'expiryDate': _isoOrNull(expiryDate),
        'missing': missing,
      });
}

/// One line in the diary's history. Every change in [AppState] writes one.
class ActivityEntry {
  ActivityEntry({
    required this.id,
    required this.action,
    required this.summary,
    required this.entityKind,
    this.entityId,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String id;
  final String action;
  final String summary;
  final EntityKind entityKind;
  final String? entityId;
  final DateTime at;

  factory ActivityEntry.fromJson(Map<String, dynamic> j) => ActivityEntry(
        id: _str(j['id']),
        action: _str(j['action']),
        summary: _str(j['summary']),
        entityKind:
            enumFromName(EntityKind.values, j['entityKind'], EntityKind.lead),
        entityId: _strOrNull(j['entityId']),
        at: _date(j['at']),
      );

  Map<String, dynamic> toJson() => _compact({
        'id': id,
        'action': action,
        'summary': summary,
        'entityKind': entityKind.name,
        'entityId': entityId,
        'at': _iso(at),
      });
}

/// A deleted record kept for [TrashEntry.retention] so a mistaken delete can
/// be undone. [records] holds every row the delete removed, grouped by
/// collection name — deleting a deal also removes its payments, for example.
class TrashEntry {
  TrashEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.records,
    DateTime? deletedAt,
  }) : deletedAt = deletedAt ?? DateTime.now();

  static const retention = Duration(days: 30);

  final String id;
  final EntityKind kind;
  final String title;
  final Map<String, List<Map<String, dynamic>>> records;
  final DateTime deletedAt;

  DateTime get purgeAt => deletedAt.add(retention);

  factory TrashEntry.fromJson(Map<String, dynamic> j) => TrashEntry(
        id: _str(j['id']),
        kind: enumFromName(EntityKind.values, j['kind'], EntityKind.lead),
        title: _str(j['title']),
        deletedAt: _date(j['deletedAt']),
        records: {
          for (final e in _map(j['records']).entries)
            e.key: _mapList(e.value),
        },
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'deletedAt': _iso(deletedAt),
        'records': records,
      };
}
