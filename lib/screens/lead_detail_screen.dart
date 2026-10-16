import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/whatsapp_sheet.dart';
import 'contact_detail_screen.dart';
import 'deal_form_screen.dart';
import 'lead_form_screen.dart';
import 'match_screen.dart';
import 'property_detail_screen.dart';
import 'task_form_screen.dart';
import 'tasks_screen.dart';
import 'visit_form_screen.dart';
import 'visits_screen.dart';

/// Everything about one enquiry, with the next action always in reach.
class LeadDetailScreen extends StatelessWidget {
  const LeadDetailScreen({super.key, required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final lead = state.lead(leadId);
    if (lead == null) {
      return const Scaffold(body: Center(child: Text('Lead not found')));
    }

    final contact = state.contact(lead.contactId);
    final visits = state.visitsForLead(lead.id);
    final tasks = state.tasksFor(EntityKind.lead, lead.id);
    final shared = lead.sharedPropertyIds
        .map(state.property)
        .whereType<Property>()
        .toList();
    final shortlisted = lead.shortlistedPropertyIds.toSet();

    return Scaffold(
      appBar: AppBar(
        title: Text(lead.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LeadFormScreen(existing: lead),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'delete':
                  final ok = await _confirmDelete(context, lead.name);
                  if (ok && context.mounted) {
                    final trashId = state.deleteLead(lead.id);
                    if (trashId != null) {
                      showDeletedToast(context, lead.name,
                          () => state.restoreFromTrash(trashId));
                    }
                    Navigator.pop(context);
                  }
                case 'duplicate-check':
                  final dupes = state.duplicateLeadsFor(lead);
                  if (context.mounted) {
                    showToast(
                      context,
                      dupes.isEmpty
                          ? 'No duplicates found for this number'
                          : 'Possible duplicates: ${dupes.map((e) => e.name).join(', ')}',
                      icon: Icons.copy_all_outlined,
                    );
                  }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                  value: 'duplicate-check', child: Text('Check for duplicates')),
              PopupMenuItem(value: 'delete', child: Text('Delete lead')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _Header(lead: lead),
          QuickContactActions(
            phone: lead.phone,
            lead: lead,
            contact: contact,
          ),
          _StagePicker(lead: lead),
          _ActionRow(lead: lead, contact: contact),
          DetailCard(
            title: 'Requirement',
            children: [
              InfoRow(
                label: 'Budget',
                value: formatBudgetRange(lead.budgetMin, lead.budgetMax),
                icon: Icons.account_balance_wallet_outlined,
              ),
              InfoRow(
                label: 'Location',
                value: lead.preferredLocation,
                icon: Icons.place_outlined,
              ),
              InfoRow(
                label: 'Property type',
                value:
                    '${lead.propertyType.label}${lead.bedrooms > 0 ? ' · ${formatBedrooms(lead.bedrooms)}' : ''}',
                icon: lead.propertyType.icon,
              ),
              InfoRow(
                label: 'Must-haves',
                value: lead.requirements,
                icon: Icons.checklist_outlined,
              ),
            ],
          ),
          DetailCard(
            title: 'Lead record',
            children: [
              InfoRow(
                label: 'Source',
                value: lead.source.label,
                icon: lead.source.icon,
              ),
              InfoRow(
                label: 'Priority',
                value: lead.priority.label,
                valueColor: lead.priority.color,
                icon: Icons.flag_outlined,
              ),
              InfoRow(
                label: 'Created',
                value: formatDate(lead.createdAt),
                icon: Icons.schedule_outlined,
              ),
              InfoRow(
                label: 'Next follow-up',
                value: lead.nextFollowUpAt == null
                    ? 'Not set'
                    : '${formatDateTime(lead.nextFollowUpAt)} (${formatRelativeDay(lead.nextFollowUpAt)})',
                valueColor: lead.isFollowUpOverdue
                    ? Theme.of(context).colorScheme.error
                    : null,
                icon: Icons.event_outlined,
              ),
              if (contact != null)
                InfoRow(
                  label: 'Contact record',
                  value: '${contact.name} · ${contact.role.label}',
                  icon: Icons.contacts_outlined,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ContactDetailScreen(contactId: contact.id),
                    ),
                  ),
                ),
            ],
          ),
          if (lead.notes.isNotEmpty)
            DetailCard(
              title: 'Notes',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(lead.notes, style: const TextStyle(height: 1.45)),
                ),
              ],
            ),
          DetailCard(
            title: 'Properties shared (${shared.length})',
            trailing: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MatchScreen(leadId: lead.id),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('Match'),
            ),
            children: [
              if (shared.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Nothing shared yet. Tap Match to see which properties '
                    'fit this buyer and why.',
                  ),
                )
              else
                for (final property in shared)
                  ListTile(
                    leading: PropertyThumb(
                      photo: property.photo,
                      icon: property.type.icon,
                      size: 44,
                    ),
                    title: Text(property.title),
                    subtitle: Text(
                      '${property.shortAddress} · ${formatMoney(property.price)}',
                    ),
                    trailing: shortlisted.contains(property.id)
                        ? const Icon(Icons.star, size: 18)
                        : null,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PropertyDetailScreen(propertyId: property.id),
                      ),
                    ),
                  ),
            ],
          ),
          DetailCard(
            title: 'Site visits (${visits.length})',
            trailing: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => VisitFormScreen(lead: lead, contact: contact),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Schedule'),
            ),
            children: [
              if (visits.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text('No visits booked for this lead yet.'),
                )
              else
                for (final visit in visits)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: VisitTile(visit: visit),
                  ),
            ],
          ),
          DetailCard(
            title: 'Follow-ups (${tasks.where((t) => !t.done).length} open)',
            trailing: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => TaskFormScreen(
                    relatedKind: EntityKind.lead,
                    relatedId: lead.id,
                    relatedLabel: lead.name,
                    suggestedTitle: 'Call ${lead.name.split(' ').first}',
                  ),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
            children: [
              if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text('No follow-ups. Add one so this does not slip.'),
                )
              else
                for (final task in tasks)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TaskTile(task: task),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<bool> _confirmDelete(BuildContext context, String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this lead?'),
        content: Text('$name moves to Recently deleted, where it is kept '
            'for 30 days.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: lead.status.color.withValues(alpha: 0.15),
            child: Text(
              lead.name.isEmpty ? '?' : lead.name[0].toUpperCase(),
              style: TextStyle(
                color: lead.status.color,
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lead.name,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(lead.phone,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusChip(
                        label: lead.status.label,
                        color: lead.status.color,
                        dense: true),
                    StatusChip(
                        label: '${lead.priority.label} priority',
                        color: lead.priority.color,
                        dense: true),
                    if (lead.isIncomplete) const IncompleteBadge(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal stage picker — one tap moves the lead along the pipeline.
class _StagePicker extends StatelessWidget {
  const _StagePicker({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      child: SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final status in LeadStatus.values) ...[
              ChoiceChip(
                label: Text(status.label),
                selected: lead.status == status,
                selectedColor: status.color.withValues(alpha: 0.18),
                onSelected: (_) => state.setLeadStatus(lead, status),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.lead, required this.contact});

  final Lead lead;
  final Contact? contact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ActionChip(
            avatar: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('Match properties'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => MatchScreen(leadId: lead.id),
              ),
            ),
          ),
          ActionChip(
            avatar: const Icon(Icons.event_outlined, size: 18),
            label: const Text('Schedule visit'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => VisitFormScreen(lead: lead, contact: contact),
              ),
            ),
          ),
          ActionChip(
            avatar: const Icon(Icons.handshake_outlined, size: 18),
            label: const Text('Create deal'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => DealFormScreen(lead: lead, buyer: contact),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
