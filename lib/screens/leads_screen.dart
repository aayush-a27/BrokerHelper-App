import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/export_datasets.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import 'lead_detail_screen.dart';
import 'lead_form_screen.dart';

/// Leads — enquiry list, status pipeline, source and follow-up date
/// (report p. 6).
class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

enum _LeadSort { followUp, newest, priority, name }

class _LeadsScreenState extends State<LeadsScreen> {
  final _search = TextEditingController();
  LeadStatus? _status;
  LeadSource? _source;
  _LeadSort _sort = _LeadSort.followUp;
  bool _onlyOverdue = false;
  bool _onlyIncomplete = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Lead> _filtered(AppState state) {
    final q = _search.text.trim().toLowerCase();
    var list = state.leads.where((lead) {
      if (_status != null && lead.status != _status) return false;
      if (_source != null && lead.source != _source) return false;
      if (_onlyOverdue && !lead.isFollowUpOverdue) return false;
      if (_onlyIncomplete && !lead.isIncomplete) return false;
      if (q.isEmpty) return true;
      return lead.name.toLowerCase().contains(q) ||
          lead.phone.contains(q) ||
          lead.preferredLocation.toLowerCase().contains(q) ||
          lead.requirements.toLowerCase().contains(q);
    }).toList();

    switch (_sort) {
      case _LeadSort.followUp:
        list.sort((a, b) {
          final av = a.nextFollowUpAt;
          final bv = b.nextFollowUpAt;
          if (av == null && bv == null) return b.createdAt.compareTo(a.createdAt);
          if (av == null) return 1;
          if (bv == null) return -1;
          return av.compareTo(bv);
        });
      case _LeadSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _LeadSort.priority:
        list.sort((a, b) => b.priority.index.compareTo(a.priority.index));
      case _LeadSort.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final leads = _filtered(state);
    final byStage = state.leadsByStage;

    return MainScaffold(
      title: 'Leads',
      subtitle: '${pluralise(leads.length, 'lead')} shown · '
          '${state.openLeads.length} open',
      embedded: widget.embedded,
      exportBuilder: () => ExportDatasets.leads(state, leads),
      actions: [
        PopupMenuButton<_LeadSort>(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort),
          initialValue: _sort,
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (context) => const [
            PopupMenuItem(
                value: _LeadSort.followUp, child: Text('Next follow-up')),
            PopupMenuItem(value: _LeadSort.newest, child: Text('Newest first')),
            PopupMenuItem(value: _LeadSort.priority, child: Text('Priority')),
            PopupMenuItem(value: _LeadSort.name, child: Text('Name')),
          ],
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search name, phone or area',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                FilterChip(
                  label: const Text('Overdue'),
                  selected: _onlyOverdue,
                  avatar: const Icon(Icons.schedule, size: 16),
                  onSelected: (v) => setState(() => _onlyOverdue = v),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Needs details'),
                  avatar: const Icon(Icons.edit_note, size: 16),
                  selected: _onlyIncomplete,
                  onSelected: (v) => setState(() => _onlyIncomplete = v),
                ),
                const SizedBox(width: 8),
                for (final status in LeadStatus.values) ...[
                  FilterChip(
                    label: Text('${status.label} ${byStage[status] ?? 0}'),
                    selected: _status == status,
                    selectedColor: status.color.withValues(alpha: 0.18),
                    onSelected: (v) =>
                        setState(() => _status = v ? status : null),
                  ),
                  const SizedBox(width: 8),
                ],
                for (final source in LeadSource.values) ...[
                  FilterChip(
                    label: Text(source.label),
                    avatar: Icon(source.icon, size: 16),
                    selected: _source == source,
                    onSelected: (v) =>
                        setState(() => _source = v ? source : null),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: leads.isEmpty
                ? EmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'No leads match',
                    message: _search.text.isEmpty
                        ? 'Add an enquiry with the + button and it will show up here.'
                        : 'Try a different search or clear the filters.',
                    action: OutlinedButton(
                      onPressed: () => setState(() {
                        _search.clear();
                        _status = null;
                        _source = null;
                        _onlyOverdue = false;
                        _onlyIncomplete = false;
                      }),
                      child: const Text('Clear filters'),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: leads.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: LeadCard(lead: leads[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The standard lead row: who, what they want, and when to act next.
class LeadCard extends StatelessWidget {
  const LeadCard({super.key, required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = lead.isFollowUpOverdue;

    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => LeadDetailScreen(leadId: lead.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: lead.status.color.withValues(alpha: 0.15),
                    child: Text(
                      lead.name.isEmpty ? '?' : lead.name[0].toUpperCase(),
                      style: TextStyle(
                        color: lead.status.color,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lead.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (lead.priority == Priority.high)
                              Icon(Icons.priority_high,
                                  size: 18, color: lead.priority.color),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lead.phone,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  StatusChip(
                    label: lead.status.label,
                    color: lead.status.color,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Tag(
                    icon: Icons.account_balance_wallet_outlined,
                    text: formatBudgetRange(lead.budgetMin, lead.budgetMax),
                  ),
                  if (lead.preferredLocation.isNotEmpty)
                    _Tag(
                        icon: Icons.place_outlined,
                        text: lead.preferredLocation),
                  _Tag(
                    icon: lead.propertyType.icon,
                    text: lead.bedrooms > 0
                        ? '${formatBedrooms(lead.bedrooms)} ${lead.propertyType.label}'
                        : lead.propertyType.label,
                  ),
                  _Tag(icon: lead.source.icon, text: lead.source.label),
                  if (lead.isIncomplete)
                    const _Tag(icon: Icons.edit_note, text: 'Needs details'),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    overdue ? Icons.warning_amber_rounded : Icons.event_outlined,
                    size: 16,
                    color: overdue ? scheme.error : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      lead.nextFollowUpAt == null
                          ? 'No next action set'
                          : 'Follow up ${formatRelativeDay(lead.nextFollowUpAt)}'
                              ' · ${formatTime(lead.nextFollowUpAt)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: overdue ? FontWeight.w700 : FontWeight.w500,
                        color: overdue ? scheme.error : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Pushes the lead form and returns the created lead, if any.
Future<Lead?> openLeadForm(BuildContext context, {Lead? existing}) {
  return Navigator.push<Lead>(
    context,
    MaterialPageRoute<Lead>(
      builder: (_) => LeadFormScreen(existing: existing),
    ),
  );
}
