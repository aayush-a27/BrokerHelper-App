import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/document_tools.dart';
import '../widgets/whatsapp_sheet.dart';
import 'contact_detail_screen.dart';
import 'deal_form_screen.dart';
import 'property_form_screen.dart';
import 'task_form_screen.dart';
import 'tasks_screen.dart';
import 'visit_form_screen.dart';
import 'visits_screen.dart';

class PropertyDetailScreen extends StatelessWidget {
  const PropertyDetailScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final property = state.property(propertyId);
    if (property == null) {
      return const Scaffold(body: Center(child: Text('Property not found')));
    }

    final owner = state.contact(property.ownerContactId);
    final interested = state.interestedIn(property);
    final visits = state.visitsForProperty(property.id);
    final tasks = state.tasksFor(EntityKind.property, property.id);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PropertyThumb(
                    photo: property.photo,
                    icon: property.type.icon,
                    size: double.infinity,
                    radius: 0,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatMoney(property.price) +
                              (property.listing == ListingType.rent
                                  ? ' / month'
                                  : ''),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            StatusChip(
                              label: property.status.label,
                              color: Colors.white,
                              dense: true,
                            ),
                            const SizedBox(width: 6),
                            StatusChip(
                              label: property.listing.label,
                              color: Colors.white,
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
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PropertyFormScreen(existing: property),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'delete') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Remove this property?'),
                        content: Text(
                            '${property.title} moves to Recently deleted, '
                            'where it is kept for 30 days.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) {
                      final trashId = state.deleteProperty(property.id);
                      if (trashId != null) {
                        showDeletedToast(context, property.title,
                            () => state.restoreFromTrash(trashId));
                      }
                      Navigator.pop(context);
                    }
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'delete', child: Text('Remove property')),
                ],
              ),
            ],
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.title,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(property.address),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                child: SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final status in PropertyStatus.values) ...[
                        ChoiceChip(
                          label: Text(status.label),
                          selected: property.status == status,
                          selectedColor: status.color.withValues(alpha: 0.18),
                          onSelected: (_) =>
                              state.setPropertyStatus(property, status),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.event_outlined, size: 18),
                      label: const Text('Schedule visit'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => VisitFormScreen(property: property),
                        ),
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.handshake_outlined, size: 18),
                      label: const Text('Create deal'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => DealFormScreen(property: property),
                        ),
                      ),
                    ),
                    if (owner != null)
                      ActionChip(
                        avatar: const Icon(Icons.chat_outlined, size: 18),
                        label: const Text('Message owner'),
                        onPressed: () => showWhatsAppSheet(
                          context,
                          phone: owner.phone,
                          contact: owner,
                          property: property,
                        ),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add_task, size: 18),
                      label: const Text('Add follow-up'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => TaskFormScreen(
                            relatedKind: EntityKind.property,
                            relatedId: property.id,
                            relatedLabel: property.title,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              DetailCard(
                title: 'Details',
                children: [
                  InfoRow(
                    label: 'Type',
                    value: property.type.label,
                    icon: property.type.icon,
                  ),
                  InfoRow(
                    label: 'Configuration',
                    value: [
                      if (property.bedrooms > 0)
                        formatBedrooms(property.bedrooms),
                      if (property.bathrooms > 0)
                        '${property.bathrooms} bath',
                      if (property.areaSqft > 0) formatArea(property.areaSqft),
                    ].join(' · '),
                    icon: Icons.straighten,
                  ),
                  InfoRow(
                    label: 'Locality',
                    value: property.shortAddress,
                    icon: Icons.place_outlined,
                  ),
                  InfoRow(
                    label: 'Source',
                    value: property.source,
                    icon: Icons.input,
                  ),
                  InfoRow(
                    label: 'Added',
                    value: formatDate(property.createdAt),
                    icon: Icons.schedule_outlined,
                  ),
                ],
              ),
              if (property.features.isNotEmpty)
                DetailCard(
                  title: 'Key features',
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final feature in property.features)
                            Chip(
                              label: Text(feature),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              if (property.visitInstructions.isNotEmpty ||
                  property.notes.isNotEmpty)
                DetailCard(
                  title: 'Notes for the broker',
                  children: [
                    if (property.visitInstructions.isNotEmpty)
                      InfoRow(
                        label: 'Visit',
                        value: property.visitInstructions,
                        icon: Icons.key_outlined,
                      ),
                    if (property.notes.isNotEmpty)
                      InfoRow(
                        label: 'Notes',
                        value: property.notes,
                        icon: Icons.sticky_note_2_outlined,
                      ),
                  ],
                ),
              DetailCard(
                title: 'Owner',
                children: [
                  if (owner == null)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text('No owner linked to this property.'),
                    )
                  else
                    ListTile(
                      leading: CircleAvatar(child: Text(owner.name[0])),
                      title: Text(owner.name),
                      subtitle: Text(
                        '${owner.phone}'
                        '${owner.seller.expectedMinPrice > 0 ? ' · expects at least ${formatMoney(owner.seller.expectedMinPrice)}' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ContactDetailScreen(contactId: owner.id),
                        ),
                      ),
                    ),
                ],
              ),
              DetailCard(
                title: 'Interested buyers (${interested.length})',
                children: [
                  if (interested.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text(
                        'No buyer linked yet. Use Match on a lead to link '
                        'one — the property record is never duplicated.',
                      ),
                    )
                  else
                    for (final buyer in interested)
                      ListTile(
                        leading: CircleAvatar(child: Text(buyer.name[0])),
                        title: Text(buyer.name),
                        subtitle: Text(
                          formatBudgetRange(
                              buyer.buyer.budgetMin, buyer.buyer.budgetMax),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.chat_outlined),
                          onPressed: () => showWhatsAppSheet(
                            context,
                            phone: buyer.phone,
                            contact: buyer,
                            property: property,
                            initialTemplateId: 'match',
                          ),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ContactDetailScreen(contactId: buyer.id),
                          ),
                        ),
                      ),
                ],
              ),
              DetailCard(
                title: 'Site visits (${visits.length})',
                children: [
                  if (visits.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text('No visits recorded for this property.'),
                    )
                  else
                    for (final visit in visits)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: VisitTile(visit: visit),
                      ),
                ],
              ),
              DocumentsSection(
                kind: EntityKind.property,
                id: property.id,
              ),
              if (tasks.isNotEmpty)
                DetailCard(
                  title: 'Follow-ups',
                  children: [
                    for (final task in tasks)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TaskTile(task: task),
                      ),
                  ],
                ),
              const SizedBox(height: 32),
            ]),
          ),
        ],
      ),
    );
  }
}
