import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/matching_service.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/whatsapp_sheet.dart';
import 'property_detail_screen.dart';
import 'visit_form_screen.dart';

/// Rule-based buyer → property matching.
///
/// Every row shows why it matched and what does not fit. The broker decides
/// what to share — nothing here is presented as a perfect match
/// (report p. 4, 3.5).
class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key, required this.leadId});

  final String leadId;

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  bool _strongOnly = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final lead = state.lead(widget.leadId);
    if (lead == null) {
      return const Scaffold(body: Center(child: Text('Lead not found')));
    }

    const matcher = MatchingService();
    var matches = matcher.matchForLead(lead, state.properties);
    if (_strongOnly) matches = matches.where((m) => m.isStrong).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matching properties'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(66),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'For ${lead.name} · '
                  '${formatBudgetRange(lead.budgetMin, lead.budgetMax)} · '
                  '${lead.preferredLocation.isEmpty ? 'any area' : lead.preferredLocation}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Flexible(
                      child: FilterChip(
                        label: const Text(
                          'Strong matches only',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: _strongOnly,
                        onSelected: (v) => setState(() => _strongOnly = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${matches.length} shown',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: matches.isEmpty
          ? EmptyState(
              icon: Icons.search_off,
              title: 'Nothing fits yet',
              message: _strongOnly
                  ? 'No property clears 75% on this buyer\'s criteria. Turn '
                      'the filter off to see partial matches.'
                  : 'Nothing in the inventory overlaps with what this buyer '
                      'asked for. Widen the budget or add inventory.',
              action: _strongOnly
                  ? OutlinedButton(
                      onPressed: () => setState(() => _strongOnly = false),
                      child: const Text('Show partial matches'),
                    )
                  : null,
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: matches.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MatchCard(lead: lead, match: matches[i]),
              ),
            ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.lead, required this.match});

  final Lead lead;
  final PropertyMatch match;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final property = match.property;
    final scheme = Theme.of(context).colorScheme;
    final shared = lead.sharedPropertyIds.contains(property.id);
    final shortlisted = lead.shortlistedPropertyIds.contains(property.id);
    final scoreColor = match.isStrong
        ? const Color(0xFF059669)
        : match.score >= 0.5
            ? const Color(0xFFD97706)
            : scheme.outline;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => PropertyDetailScreen(propertyId: property.id),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PropertyThumb(
                      photo: property.photo, icon: property.type.icon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          property.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${property.shortAddress} · ${formatBedrooms(property.bedrooms)} · ${formatArea(property.areaSqft)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatMoney(property.price),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      StatusChip(
                        label: '${match.percent}%',
                        color: scoreColor,
                      ),
                      const SizedBox(height: 6),
                      StatusChip(
                        label: property.status.label,
                        color: property.status.color,
                        dense: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final criterion in match.criteria)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          criterion.ok
                              ? Icons.check_circle
                              : Icons.cancel_outlined,
                          size: 15,
                          color: criterion.ok
                              ? const Color(0xFF059669)
                              : scheme.error,
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 90,
                          child: Text(
                            criterion.label,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            criterion.detail,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => state.toggleShortlist(lead, property),
                  icon: Icon(
                    shortlisted ? Icons.star : Icons.star_border,
                    size: 18,
                  ),
                  label: Text(shortlisted ? 'Shortlisted' : 'Shortlist'),
                ),
                TextButton.icon(
                  onPressed: () {
                    state.sharePropertyWithLead(lead, property);
                    showWhatsAppSheet(
                      context,
                      phone: lead.phone,
                      lead: lead,
                      property: property,
                      contact: state.contact(lead.contactId),
                      initialTemplateId: 'match',
                    );
                  },
                  icon: Icon(
                    shared ? Icons.check_circle_outline : Icons.send_outlined,
                    size: 18,
                  ),
                  label: Text(shared ? 'Shared' : 'Share'),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => VisitFormScreen(
                        property: property,
                        lead: lead,
                        contact: state.contact(lead.contactId),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: const Text('Visit'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
