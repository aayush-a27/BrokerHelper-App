import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import 'export_service.dart';

/// Turns the in-memory records into the flat tables the CSV/PDF export needs.
/// Each list screen passes its *filtered* rows in, so what the broker sees is
/// what gets exported (report p. 5, "Export selected records").
class ExportDatasets {
  const ExportDatasets._();

  static ExportDataset leads(AppState state, List<Lead> leads) => ExportDataset(
        name: 'leads',
        title: 'Leads',
        subtitle: '${pluralise(leads.length, 'record')} · exported ${formatIso(DateTime.now())}',
        headers: const [
          'Name',
          'Phone',
          'Source',
          'Status',
          'Priority',
          'Budget',
          'Location',
          'Type',
          'Next follow-up',
        ],
        rows: [
          for (final l in leads)
            [
              l.name,
              l.phone,
              l.source.label,
              l.status.label,
              l.priority.label,
              formatBudgetRange(l.budgetMin, l.budgetMax),
              l.preferredLocation,
              l.propertyType.label,
              formatDate(l.nextFollowUpAt),
            ],
        ],
      );

  static ExportDataset contacts(AppState state, List<Contact> contacts) =>
      ExportDataset(
        name: 'contacts',
        title: 'Contacts',
        subtitle:
            '${pluralise(contacts.length, 'record')} · exported ${formatIso(DateTime.now())}',
        headers: const [
          'Name',
          'Phone',
          'Email',
          'Role',
          'Locality',
          'Budget',
          'Linked leads',
          'Owned properties',
        ],
        rows: [
          for (final c in contacts)
            [
              c.name,
              c.phone,
              c.email,
              c.role.label,
              c.locality,
              c.role.isBuyer
                  ? formatBudgetRange(c.buyer.budgetMin, c.buyer.budgetMax)
                  : formatMoney(c.seller.askingPrice),
              state.leadsForContact(c.id).length.toString(),
              state.propertiesForOwner(c.id).length.toString(),
            ],
        ],
      );

  static ExportDataset properties(AppState state, List<Property> properties) =>
      ExportDataset(
        name: 'properties',
        title: 'Property inventory',
        subtitle:
            '${pluralise(properties.length, 'record')} · exported ${formatIso(DateTime.now())}',
        headers: const [
          'Title',
          'Type',
          'Listing',
          'Status',
          'Locality',
          'City',
          'Beds',
          'Area',
          'Price',
          'Owner',
          'Interested',
        ],
        rows: [
          for (final p in properties)
            [
              p.title,
              p.type.label,
              p.listing.label,
              p.status.label,
              p.locality,
              p.city,
              p.bedrooms.toString(),
              formatArea(p.areaSqft),
              formatMoney(p.price),
              state.contact(p.ownerContactId)?.name ?? '—',
              p.interestedContactIds.length.toString(),
            ],
        ],
      );

  static ExportDataset visits(AppState state, List<SiteVisit> visits) =>
      ExportDataset(
        name: 'site_visits',
        title: 'Site visits',
        subtitle:
            '${pluralise(visits.length, 'record')} · exported ${formatIso(DateTime.now())}',
        headers: const [
          'When',
          'Property',
          'Buyer',
          'Status',
          'Outcome',
          'Feedback',
        ],
        rows: [
          for (final v in visits)
            [
              formatIso(v.scheduledAt),
              state.propertyTitle(v.propertyId),
              state.contactName(v.contactId),
              v.status.label,
              v.outcome.label,
              v.feedback,
            ],
        ],
      );

  static ExportDataset tasks(AppState state, List<BrokerTask> tasks) =>
      ExportDataset(
        name: 'follow_ups',
        title: 'Follow-ups and tasks',
        subtitle:
            '${pluralise(tasks.length, 'record')} · exported ${formatIso(DateTime.now())}',
        headers: const ['Due', 'Title', 'Type', 'Status', 'Notes'],
        rows: [
          for (final t in tasks)
            [
              formatIso(t.dueAt),
              t.title,
              t.type.label,
              t.done
                  ? 'Done'
                  : t.isOverdue
                      ? 'Overdue'
                      : 'Pending',
              t.notes,
            ],
        ],
      );

  static ExportDataset deals(AppState state, List<Deal> deals) => ExportDataset(
        name: 'deals',
        title: 'Deals and commission',
        subtitle:
            '${pluralise(deals.length, 'record')} · exported ${formatIso(DateTime.now())}',
        headers: const [
          'Deal',
          'Stage',
          'Property',
          'Buyer',
          'Seller',
          'Value',
          'Token',
          'Commission',
          'Received',
          'Pending',
        ],
        rows: [
          for (final d in deals)
            [
              d.title,
              d.stage.label,
              state.propertyTitle(d.propertyId),
              state.contactName(d.buyerContactId),
              state.contactName(d.sellerContactId),
              formatMoney(d.agreedValue),
              formatMoney(d.tokenAmount),
              formatMoney(d.expectedCommission),
              formatMoney(state.commissionReceivedFor(d.id)),
              formatMoney(state.commissionPendingFor(d)),
            ],
        ],
      );

  static ExportDataset documents(
          AppState state, List<DocumentRecord> documents) =>
      ExportDataset(
        name: 'documents',
        title: 'Document vault',
        subtitle:
            '${pluralise(documents.length, 'record')} · exported ${formatIso(DateTime.now())}',
        headers: const [
          'File',
          'Kind',
          'Linked to',
          'Size',
          'Uploaded',
          'Expires',
          'Status',
        ],
        rows: [
          for (final d in documents)
            [
              d.name,
              d.kind.label,
              [
                if (d.propertyId != null) state.propertyTitle(d.propertyId),
                if (d.contactId != null) state.contactName(d.contactId),
                if (d.dealId != null) state.deal(d.dealId)?.title ?? '',
              ].where((e) => e.isNotEmpty).join(' / '),
              d.missing ? '—' : '${d.sizeKb} KB',
              d.missing ? '—' : formatDate(d.uploadedAt),
              formatDate(d.expiryDate),
              d.missing ? 'Missing' : 'On file',
            ],
        ],
      );

  /// A one-page business summary rather than a record list.
  static ExportDataset businessSummary(AppState state) {
    final stage = state.leadsByStage;
    final source = state.leadsBySource;
    return ExportDataset(
      name: 'business_summary',
      title: 'Business summary',
      subtitle: 'Generated ${formatIso(DateTime.now())}',
      headers: const ['Measure', 'Value'],
      rows: [
        ['Total leads', state.leads.length.toString()],
        ['Open leads', state.openLeads.length.toString()],
        ['New leads (7 days)', state.newLeadsThisWeek.length.toString()],
        ['Follow-ups due today', state.todaysTasks.length.toString()],
        ['Overdue follow-ups', state.overdueTasks.length.toString()],
        ['Upcoming site visits', state.upcomingVisits.length.toString()],
        ['Properties in inventory', state.properties.length.toString()],
        ['Open deals', state.openDeals.length.toString()],
        ['Deals won', state.dealsWon.toString()],
        ['Deals lost', state.dealsLost.toString()],
        ['Commission expected', formatMoney(state.totalExpectedCommission)],
        ['Commission received', formatMoney(state.totalReceivedCommission)],
        ['Commission pending', formatMoney(state.totalPendingCommission)],
        [
          'Leads with a next action',
          '${(state.leadsWithNextActionRatio * 100).round()}%',
        ],
        ['Missing documents', state.missingDocuments.length.toString()],
        ...LeadStatus.values
            .map((s) => ['Leads — ${s.label}', '${stage[s] ?? 0}']),
        ...LeadSource.values
            .map((s) => ['Source — ${s.label}', '${source[s] ?? 0}']),
      ],
    );
  }
}
