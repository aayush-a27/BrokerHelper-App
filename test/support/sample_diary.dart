import 'package:broker_demo_app/models/models.dart';
import 'package:broker_demo_app/state/app_state.dart';

/// A small diary for widget tests, built through the same public API the
/// screens use. Test-only — the app itself ships with an empty diary.
void seedSampleDiary(AppState state) {
  final now = DateTime.now();
  DateTime day(int offset, [int hour = 11]) =>
      DateTime(now.year, now.month, now.day + offset, hour);

  state.saveProfile(BrokerProfile(
      name: 'Aarav Mehta', phone: '98200 11111', agency: 'Mehta Realty'));

  final flat = state.addProperty(Property(
    id: 'pr-1',
    title: '3 BHK, Baner',
    locality: 'Baner',
    city: 'Pune',
    bedrooms: 3,
    price: 11500000,
    features: ['Covered parking', 'East facing'],
  ));
  state.addProperty(Property(
    id: 'pr-2',
    title: '2 BHK, Kharadi',
    locality: 'Kharadi',
    city: 'Pune',
    bedrooms: 2,
    price: 6500000,
  ));

  final rohit = state.addLead(Lead(
    id: 'ld-1',
    name: 'Rohit Agarwal',
    phone: '98210 34567',
    budgetMin: 10000000,
    budgetMax: 12000000,
    preferredLocation: 'Baner',
    bedrooms: 3,
    requirements: 'East facing, covered parking',
    nextFollowUpAt: day(0, 18),
  ));
  state.addLead(Lead(
    id: 'ld-2',
    name: 'Priya Sharma',
    phone: '99304 11228',
    status: LeadStatus.qualified,
    budgetMax: 7000000,
    preferredLocation: 'Kharadi',
    bedrooms: 2,
  ));
  state.addLead(Lead(id: 'ld-3', name: 'Quick jot', phone: '97000 00000'));

  state.addTask(BrokerTask(
    id: 'tk-1',
    title: 'Call Rohit about Baner flat',
    dueAt: day(1, 10),
    relatedKind: EntityKind.lead,
    relatedId: rohit.id,
  ));
  state.addTask(BrokerTask(
      id: 'tk-2', title: 'Collect NOC', dueAt: day(-1),
      type: TaskType.documentCollection));

  state.addVisit(SiteVisit(
    id: 'vs-1',
    propertyId: flat.id,
    leadId: rohit.id,
    contactId: rohit.contactId,
    scheduledAt: day(1),
  ));

  final deal = state.addDeal(Deal(
    id: 'dl-1',
    title: 'Rohit · 3 BHK Baner',
    propertyId: flat.id,
    buyerContactId: rohit.contactId,
    leadId: rohit.id,
    stage: DealStage.negotiation,
    agreedValue: 11200000,
  ));
  state.addPayment(PaymentRecord(
      id: 'pm-1', dealId: deal.id, amount: 112000, dueDate: day(10)));
  state.addDocument(DocumentRecord(
      id: 'doc-1', name: 'Society NOC', missing: true, propertyId: flat.id));
}
