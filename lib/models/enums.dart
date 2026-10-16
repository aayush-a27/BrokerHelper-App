import 'package:flutter/material.dart';

/// Resolves an enum value from its `name`, falling back when the JSON is
/// missing or holds something we no longer recognise.
T enumFromName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name == null) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

enum LeadSource { portal, referral, phoneCall, walkIn, other }

extension LeadSourceX on LeadSource {
  String get label => switch (this) {
        LeadSource.portal => 'Property portal',
        LeadSource.referral => 'Referral',
        LeadSource.phoneCall => 'Phone call',
        LeadSource.walkIn => 'Walk-in',
        LeadSource.other => 'Other',
      };

  IconData get icon => switch (this) {
        LeadSource.portal => Icons.public,
        LeadSource.referral => Icons.handshake_outlined,
        LeadSource.phoneCall => Icons.call_outlined,
        LeadSource.walkIn => Icons.directions_walk,
        LeadSource.other => Icons.more_horiz,
      };
}

enum LeadStatus { newLead, contacted, qualified, siteVisit, negotiation, won, lost }

extension LeadStatusX on LeadStatus {
  String get label => switch (this) {
        LeadStatus.newLead => 'New',
        LeadStatus.contacted => 'Contacted',
        LeadStatus.qualified => 'Qualified',
        LeadStatus.siteVisit => 'Site visit',
        LeadStatus.negotiation => 'Negotiation',
        LeadStatus.won => 'Won',
        LeadStatus.lost => 'Lost',
      };

  Color get color => switch (this) {
        LeadStatus.newLead => const Color(0xFF2563EB),
        LeadStatus.contacted => const Color(0xFF7C3AED),
        LeadStatus.qualified => const Color(0xFF0891B2),
        LeadStatus.siteVisit => const Color(0xFFD97706),
        LeadStatus.negotiation => const Color(0xFFDB2777),
        LeadStatus.won => const Color(0xFF059669),
        LeadStatus.lost => const Color(0xFF6B7280),
      };

  bool get isOpen => this != LeadStatus.won && this != LeadStatus.lost;
}

enum Priority { low, medium, high }

extension PriorityX on Priority {
  String get label => switch (this) {
        Priority.low => 'Low',
        Priority.medium => 'Medium',
        Priority.high => 'High',
      };

  Color get color => switch (this) {
        Priority.low => const Color(0xFF6B7280),
        Priority.medium => const Color(0xFFD97706),
        Priority.high => const Color(0xFFDC2626),
      };
}

enum ContactRole { buyer, seller, both }

extension ContactRoleX on ContactRole {
  String get label => switch (this) {
        ContactRole.buyer => 'Buyer',
        ContactRole.seller => 'Seller',
        ContactRole.both => 'Buyer & seller',
      };

  bool get isBuyer => this == ContactRole.buyer || this == ContactRole.both;
  bool get isSeller => this == ContactRole.seller || this == ContactRole.both;
}

enum PropertyType { apartment, villa, plot, house, office, shop }

extension PropertyTypeX on PropertyType {
  String get label => switch (this) {
        PropertyType.apartment => 'Apartment',
        PropertyType.villa => 'Villa',
        PropertyType.plot => 'Plot',
        PropertyType.house => 'Independent house',
        PropertyType.office => 'Office',
        PropertyType.shop => 'Shop',
      };

  IconData get icon => switch (this) {
        PropertyType.apartment => Icons.apartment,
        PropertyType.villa => Icons.villa_outlined,
        PropertyType.plot => Icons.crop_square,
        PropertyType.house => Icons.house_outlined,
        PropertyType.office => Icons.business_center_outlined,
        PropertyType.shop => Icons.storefront_outlined,
      };
}

enum ListingType { sale, rent }

extension ListingTypeX on ListingType {
  String get label => this == ListingType.sale ? 'For sale' : 'For rent';
}

enum PropertyStatus { available, onHold, underNegotiation, sold, rented }

extension PropertyStatusX on PropertyStatus {
  String get label => switch (this) {
        PropertyStatus.available => 'Available',
        PropertyStatus.onHold => 'On hold',
        PropertyStatus.underNegotiation => 'Under negotiation',
        PropertyStatus.sold => 'Sold',
        PropertyStatus.rented => 'Rented',
      };

  Color get color => switch (this) {
        PropertyStatus.available => const Color(0xFF059669),
        PropertyStatus.onHold => const Color(0xFFD97706),
        PropertyStatus.underNegotiation => const Color(0xFFDB2777),
        PropertyStatus.sold => const Color(0xFF6B7280),
        PropertyStatus.rented => const Color(0xFF6B7280),
      };

  /// Only these two can still be offered to a buyer.
  bool get isOfferable =>
      this == PropertyStatus.available || this == PropertyStatus.onHold;
}

enum VisitStatus { scheduled, confirmed, completed, cancelled }

extension VisitStatusX on VisitStatus {
  String get label => switch (this) {
        VisitStatus.scheduled => 'Scheduled',
        VisitStatus.confirmed => 'Confirmed',
        VisitStatus.completed => 'Completed',
        VisitStatus.cancelled => 'Cancelled',
      };

  Color get color => switch (this) {
        VisitStatus.scheduled => const Color(0xFF2563EB),
        VisitStatus.confirmed => const Color(0xFF059669),
        VisitStatus.completed => const Color(0xFF6B7280),
        VisitStatus.cancelled => const Color(0xFFDC2626),
      };
}

enum VisitOutcome { pending, interested, notInterested, needsFollowUp, offerMade }

extension VisitOutcomeX on VisitOutcome {
  String get label => switch (this) {
        VisitOutcome.pending => 'Not recorded yet',
        VisitOutcome.interested => 'Interested',
        VisitOutcome.notInterested => 'Not interested',
        VisitOutcome.needsFollowUp => 'Needs follow-up',
        VisitOutcome.offerMade => 'Offer made',
      };
}

enum TaskType { call, visit, negotiation, documentCollection, other }

extension TaskTypeX on TaskType {
  String get label => switch (this) {
        TaskType.call => 'Call',
        TaskType.visit => 'Visit',
        TaskType.negotiation => 'Negotiation',
        TaskType.documentCollection => 'Document collection',
        TaskType.other => 'Other',
      };

  IconData get icon => switch (this) {
        TaskType.call => Icons.call_outlined,
        TaskType.visit => Icons.directions_car_outlined,
        TaskType.negotiation => Icons.gavel_outlined,
        TaskType.documentCollection => Icons.folder_open_outlined,
        TaskType.other => Icons.check_circle_outline,
      };
}

enum DealStage { prospect, negotiation, agreement, closedWon, closedLost }

extension DealStageX on DealStage {
  String get label => switch (this) {
        DealStage.prospect => 'Prospect',
        DealStage.negotiation => 'Negotiation',
        DealStage.agreement => 'Agreement',
        DealStage.closedWon => 'Closed — won',
        DealStage.closedLost => 'Closed — lost',
      };

  Color get color => switch (this) {
        DealStage.prospect => const Color(0xFF2563EB),
        DealStage.negotiation => const Color(0xFFDB2777),
        DealStage.agreement => const Color(0xFFD97706),
        DealStage.closedWon => const Color(0xFF059669),
        DealStage.closedLost => const Color(0xFF6B7280),
      };

  bool get isOpen => this != DealStage.closedWon && this != DealStage.closedLost;
}

enum CommissionType { fixed, percentage }

extension CommissionTypeX on CommissionType {
  String get label =>
      this == CommissionType.fixed ? 'Fixed fee' : 'Percentage of value';
}

enum PaymentStatus { pending, partial, paid }

extension PaymentStatusX on PaymentStatus {
  String get label => switch (this) {
        PaymentStatus.pending => 'Pending',
        PaymentStatus.partial => 'Partially paid',
        PaymentStatus.paid => 'Paid',
      };

  Color get color => switch (this) {
        PaymentStatus.pending => const Color(0xFFDC2626),
        PaymentStatus.partial => const Color(0xFFD97706),
        PaymentStatus.paid => const Color(0xFF059669),
      };
}

enum DocumentKind { photo, agreement, receipt, idProof, other }

extension DocumentKindX on DocumentKind {
  String get label => switch (this) {
        DocumentKind.photo => 'Photo',
        DocumentKind.agreement => 'Agreement',
        DocumentKind.receipt => 'Receipt',
        DocumentKind.idProof => 'ID proof',
        DocumentKind.other => 'Other',
      };

  IconData get icon => switch (this) {
        DocumentKind.photo => Icons.image_outlined,
        DocumentKind.agreement => Icons.description_outlined,
        DocumentKind.receipt => Icons.receipt_long_outlined,
        DocumentKind.idProof => Icons.badge_outlined,
        DocumentKind.other => Icons.insert_drive_file_outlined,
      };
}

/// The kinds of record an activity-log entry or a document can point at.
enum EntityKind { lead, contact, property, visit, task, deal, document, payment }

extension EntityKindX on EntityKind {
  String get label => switch (this) {
        EntityKind.lead => 'Lead',
        EntityKind.contact => 'Contact',
        EntityKind.property => 'Property',
        EntityKind.visit => 'Site visit',
        EntityKind.task => 'Task',
        EntityKind.deal => 'Deal',
        EntityKind.document => 'Document',
        EntityKind.payment => 'Payment',
      };

  IconData get icon => switch (this) {
        EntityKind.lead => Icons.person_add_alt_1_outlined,
        EntityKind.contact => Icons.contacts_outlined,
        EntityKind.property => Icons.home_work_outlined,
        EntityKind.visit => Icons.event_outlined,
        EntityKind.task => Icons.task_alt,
        EntityKind.deal => Icons.handshake_outlined,
        EntityKind.document => Icons.folder_outlined,
        EntityKind.payment => Icons.payments_outlined,
      };
}
