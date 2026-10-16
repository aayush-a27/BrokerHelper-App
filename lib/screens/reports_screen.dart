import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/export_datasets.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

/// Reports — simple counts and summaries, plus the success measures the
/// report suggests tracking (pp. 4 and 8). Deliberately numbers-first: the
/// scope document asks for advanced charts only when they earn their place.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final total = state.leads.length;
    final byStage = state.leadsByStage;
    final bySource = state.leadsBySource;
    final byStatus = state.propertiesByStatus;

    final leadsWithVisit = state.leads
        .where((l) => state.visitsForLead(l.id).isNotEmpty)
        .length;
    final visitsWithDeal = state.deals.where((d) => d.leadId != null).length;

    return MainScaffold(
      title: 'Reports',
      subtitle: 'Business summary',
      embedded: embedded,
      showQuickAdd: false,
      exportBuilder: () => ExportDatasets.businessSummary(state),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const SectionHeader(
            'Headline numbers',
            subtitle: 'What the broker would check each morning',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisExtent: 148,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              children: [
                StatCard(
                  label: 'Total leads',
                  value: '$total',
                  icon: Icons.filter_alt_outlined,
                  caption: '${state.openLeads.length} still open',
                ),
                StatCard(
                  label: 'Properties',
                  value: '${state.properties.length}',
                  icon: Icons.home_work_outlined,
                  caption:
                      '${byStatus[PropertyStatus.available] ?? 0} available',
                ),
                StatCard(
                  label: 'Deals won',
                  value: '${state.dealsWon}',
                  icon: Icons.emoji_events_outlined,
                  tone: const Color(0xFF059669),
                  caption: '${state.dealsLost} lost',
                ),
                StatCard(
                  label: 'Commission pending',
                  value: formatMoney(state.totalPendingCommission),
                  icon: Icons.payments_outlined,
                  tone: const Color(0xFFDC2626),
                  caption:
                      '${formatMoney(state.totalReceivedCommission)} received',
                ),
              ],
            ),
          ),
          const SectionHeader('Leads by stage'),
          _BreakdownCard(
            rows: [
              for (final status in LeadStatus.values)
                (status.label, byStage[status] ?? 0, status.color),
            ],
            total: total,
          ),
          const SectionHeader('Leads by source'),
          _BreakdownCard(
            rows: [
              for (final source in LeadSource.values)
                (
                  source.label,
                  bySource[source] ?? 0,
                  Theme.of(context).colorScheme.primary
                ),
            ],
            total: total,
          ),
          const SectionHeader('Inventory by availability'),
          _BreakdownCard(
            rows: [
              for (final status in PropertyStatus.values)
                (status.label, byStatus[status] ?? 0, status.color),
            ],
            total: state.properties.length,
          ),
          const SectionHeader(
            'Is the app helping?',
            subtitle: 'The success measures from the scope report, page 8',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Card(
              child: Column(
                children: [
                  _Measure(
                    label: 'Leads with a recorded next action',
                    value:
                        '${(state.leadsWithNextActionRatio * 100).round()}%',
                    good: state.leadsWithNextActionRatio >= 0.8,
                  ),
                  _Measure(
                    label: 'Overdue follow-ups',
                    value: '${state.overdueTasks.length}',
                    good: state.overdueTasks.isEmpty,
                  ),
                  _Measure(
                    label: 'Lead → site visit',
                    value: total == 0
                        ? '—'
                        : '${(leadsWithVisit / total * 100).round()}%',
                    good: total > 0 && leadsWithVisit / total >= 0.3,
                  ),
                  _Measure(
                    label: 'Leads that became a deal',
                    value: total == 0
                        ? '—'
                        : '${(visitsWithDeal / total * 100).round()}%',
                    good: total > 0 && visitsWithDeal / total >= 0.2,
                  ),
                  _Measure(
                    label: 'Documents still to collect',
                    value: '${state.missingDocuments.length}',
                    good: state.missingDocuments.isEmpty,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Every figure is worked out from the diary on this '
                        'phone. Export it as Excel (CSV) or PDF from the '
                        'share icon.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.rows, required this.total});

  final List<(String, int, Color)> rows;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              for (final row in rows)
                BreakdownBar(
                  label: row.$1,
                  count: row.$2,
                  total: total,
                  color: row.$3,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Measure extends StatelessWidget {
  const _Measure({
    required this.label,
    required this.value,
    required this.good,
  });

  final String label;
  final String value;
  final bool good;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        good ? Icons.trending_up : Icons.trending_flat,
        color: good ? const Color(0xFF059669) : const Color(0xFFD97706),
      ),
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }
}
