import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/matching_service.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/document_tools.dart';
import '../widgets/whatsapp_sheet.dart';
import 'contact_form_screen.dart';
import 'deal_detail_screen.dart';
import 'lead_detail_screen.dart';
import 'property_detail_screen.dart';

/// One person's full history: profile, requirements, linked records and
/// every logged interaction (report p. 3, 2.2).
class ContactDetailScreen extends StatelessWidget {
  const ContactDetailScreen({super.key, required this.contactId});

  final String contactId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final contact = state.contact(contactId);
    if (contact == null) {
      return const Scaffold(body: Center(child: Text('Contact not found')));
    }

    final leads = state.leadsForContact(contact.id);
    final owned = state.propertiesForOwner(contact.id);
    final deals = state.dealsForContact(contact.id);
    const matcher = MatchingService();
    final matches = contact.role.isBuyer
        ? matcher.matchForContact(contact, state.properties).take(3).toList()
        : const <PropertyMatch>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(contact.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ContactFormScreen(existing: contact),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'Delete this contact?',
                message: '${contact.name} moves to Recently deleted, where it '
                    'is kept for 30 days. Their leads and deals stay.',
                confirm: 'Delete',
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              final trashId = state.deleteContact(contact.id);
              if (trashId != null) {
                showDeletedToast(context, contact.name,
                    () => state.restoreFromTrash(trashId));
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(
                    contact.name[0].toUpperCase(),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(contact.phone),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          StatusChip(
                            label: contact.role.label,
                            color: Theme.of(context).colorScheme.primary,
                            dense: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          QuickContactActions(phone: contact.phone, contact: contact),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.note_add_outlined, size: 18),
                  label: const Text('Log a call'),
                  onPressed: () => _logInteraction(context, state, contact),
                ),
              ],
            ),
          ),
          DetailCard(
            title: 'Contact details',
            children: [
              InfoRow(
                label: 'Phone',
                value: contact.phone,
                icon: Icons.call_outlined,
              ),
              InfoRow(
                label: 'Email',
                value: contact.email,
                icon: Icons.alternate_email,
              ),
              InfoRow(
                label: 'Locality',
                value: contact.locality,
                icon: Icons.place_outlined,
              ),
              InfoRow(
                label: 'On file since',
                value: formatDate(contact.createdAt),
                icon: Icons.schedule_outlined,
              ),
            ],
          ),
          if (contact.role.isBuyer)
            DetailCard(
              title: 'Buyer requirements',
              children: [
                InfoRow(
                  label: 'Budget',
                  value: formatBudgetRange(
                      contact.buyer.budgetMin, contact.buyer.budgetMax),
                  icon: Icons.account_balance_wallet_outlined,
                ),
                InfoRow(
                  label: 'Locations',
                  value: contact.buyer.preferredLocations.join(', '),
                  icon: Icons.place_outlined,
                ),
                InfoRow(
                  label: 'Property type',
                  value: contact.buyer.propertyTypes
                      .map((e) => e.label)
                      .join(', '),
                  icon: Icons.home_work_outlined,
                ),
                InfoRow(
                  label: 'Bedrooms',
                  value: formatBedrooms(contact.buyer.bedrooms),
                  icon: Icons.bed_outlined,
                ),
                InfoRow(
                  label: 'Must-haves',
                  value: contact.buyer.mustHaves.join(', '),
                  icon: Icons.checklist_outlined,
                ),
              ],
            ),
          if (contact.role.isSeller)
            DetailCard(
              title: 'Seller details',
              children: [
                InfoRow(
                  label: 'Asking price',
                  value: formatMoney(contact.seller.askingPrice),
                  icon: Icons.sell_outlined,
                ),
                InfoRow(
                  label: 'Expected min',
                  value: formatMoney(contact.seller.expectedMinPrice),
                  icon: Icons.lock_outline,
                ),
                InfoRow(
                  label: 'Best time',
                  value: contact.seller.preferredContactTime,
                  icon: Icons.schedule_outlined,
                ),
              ],
            ),
          if (matches.isNotEmpty)
            DetailCard(
              title: 'Suggested properties',
              children: [
                for (final match in matches)
                  ListTile(
                    leading: PropertyThumb(
                      photo: match.property.photo,
                      icon: match.property.type.icon,
                      size: 44,
                    ),
                    title: Text(match.property.title),
                    subtitle: Text(
                      '${formatMoney(match.property.price)} · '
                      '${match.criteria.where((c) => c.ok).length} of '
                      '${match.criteria.length} criteria fit',
                    ),
                    trailing: StatusChip(
                      label: '${match.percent}%',
                      color: match.isStrong
                          ? const Color(0xFF059669)
                          : Theme.of(context).colorScheme.outline,
                      dense: true,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PropertyDetailScreen(
                            propertyId: match.property.id),
                      ),
                    ),
                  ),
              ],
            ),
          if (owned.isNotEmpty)
            DetailCard(
              title: 'Properties owned (${owned.length})',
              children: [
                for (final property in owned)
                  ListTile(
                    leading: PropertyThumb(
                      photo: property.photo,
                      icon: property.type.icon,
                      size: 44,
                    ),
                    title: Text(property.title),
                    subtitle: Text(
                        '${property.status.label} · ${formatMoney(property.price)}'),
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
          if (leads.isNotEmpty)
            DetailCard(
              title: 'Linked leads (${leads.length})',
              children: [
                for (final lead in leads)
                  ListTile(
                    leading: Icon(lead.source.icon),
                    title: Text(lead.name),
                    subtitle: Text(
                        '${lead.status.label} · ${formatBudgetRange(lead.budgetMin, lead.budgetMax)}'),
                    trailing: StatusChip(
                      label: lead.status.label,
                      color: lead.status.color,
                      dense: true,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => LeadDetailScreen(leadId: lead.id),
                      ),
                    ),
                  ),
              ],
            ),
          if (deals.isNotEmpty)
            DetailCard(
              title: 'Deals (${deals.length})',
              children: [
                for (final deal in deals)
                  ListTile(
                    leading: const Icon(Icons.handshake_outlined),
                    title: Text(deal.title),
                    subtitle: Text(formatMoney(deal.agreedValue)),
                    trailing: StatusChip(
                      label: deal.stage.label,
                      color: deal.stage.color,
                      dense: true,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => DealDetailScreen(dealId: deal.id),
                      ),
                    ),
                  ),
              ],
            ),
          DocumentsSection(kind: EntityKind.contact, id: contact.id),
          DetailCard(
            title: 'Interaction history (${contact.interactions.length})',
            children: [
              if (contact.interactions.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text('Nothing logged yet. Tap "Log a call" above.'),
                )
              else
                for (final interaction in contact.interactions)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, size: 20),
                    title: Text(interaction.note),
                    subtitle: Text(
                        '${interaction.channel} · ${formatDateTime(interaction.at)}'),
                  ),
            ],
          ),
          if (contact.notes.isNotEmpty)
            DetailCard(
              title: 'Notes',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(contact.notes,
                      style: const TextStyle(height: 1.45)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static Future<void> _logInteraction(
      BuildContext context, AppState state, Contact contact) async {
    final note = TextEditingController();
    var channel = 'Call';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Log an interaction',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final option in const [
                    'Call',
                    'WhatsApp',
                    'Site visit',
                    'Meeting',
                    'Email',
                  ])
                    ChoiceChip(
                      label: Text(option),
                      selected: channel == option,
                      onSelected: (_) => setSheetState(() => channel = option),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'What was discussed?',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.check),
                label: const Text('Save note'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (saved == true && note.text.trim().isNotEmpty) {
      state.logInteraction(contact, channel, note.text.trim());
      if (context.mounted) {
        showToast(context, 'Interaction logged',
            icon: Icons.check_circle_outline);
      }
    }
    note.dispose();
  }
}
