import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/export_datasets.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import 'contact_detail_screen.dart';
import 'contact_form_screen.dart';

/// Contacts — buyers, sellers and interaction history (report p. 6).
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _search = TextEditingController();
  ContactRole? _role;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Contact> _filtered(AppState state) {
    final q = _search.text.trim().toLowerCase();
    return state.contacts.where((c) {
      if (_role != null) {
        final matches = switch (_role!) {
          ContactRole.buyer => c.role.isBuyer,
          ContactRole.seller => c.role.isSeller,
          ContactRole.both => c.role == ContactRole.both,
        };
        if (!matches) return false;
      }
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.phone.contains(q) ||
          c.email.toLowerCase().contains(q) ||
          c.locality.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final contacts = _filtered(state);

    return MainScaffold(
      title: 'Contacts',
      subtitle: '${pluralise(contacts.length, 'contact')} · '
          '${state.contacts.where((c) => c.role.isBuyer).length} buyers · '
          '${state.contacts.where((c) => c.role.isSeller).length} sellers',
      embedded: widget.embedded,
      exportBuilder: () => ExportDatasets.contacts(state, contacts),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const ContactFormScreen()),
        ),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Contact'),
      ),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // A Wrap rather than a Row: "Buyer & seller" pushes the three
            // chips past the edge of a narrow handset.
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final role in ContactRole.values)
                  FilterChip(
                    label: Text(role.label),
                    selected: _role == role,
                    onSelected: (v) => setState(() => _role = v ? role : null),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: contacts.isEmpty
                ? const EmptyState(
                    icon: Icons.contacts_outlined,
                    title: 'No contacts match',
                    message: 'Try a different search, or add a buyer/seller.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: contacts.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (context, i) =>
                        ContactTile(contact: contacts[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class ContactTile extends StatelessWidget {
  const ContactTile({super.key, required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final leads = state.leadsForContact(contact.id).length;
    final owned = state.propertiesForOwner(contact.id).length;

    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        child: Text(
          contact.name.isEmpty ? '?' : contact.name[0].toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(contact.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            '${contact.phone}${contact.locality.isEmpty ? '' : ' · ${contact.locality}'}',
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              StatusChip(
                label: contact.role.label,
                color: Theme.of(context).colorScheme.primary,
                dense: true,
              ),
              if (contact.role.isBuyer && contact.buyer.budgetMax > 0)
                StatusChip(
                  label: formatBudgetRange(
                      contact.buyer.budgetMin, contact.buyer.budgetMax),
                  color: Theme.of(context).colorScheme.tertiary,
                  dense: true,
                ),
              if (leads > 0)
                StatusChip(
                  label: pluralise(leads, 'lead'),
                  color: Theme.of(context).colorScheme.secondary,
                  dense: true,
                ),
              if (owned > 0)
                StatusChip(
                  label: pluralise(owned, 'listing'),
                  color: Theme.of(context).colorScheme.secondary,
                  dense: true,
                ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ContactDetailScreen(contactId: contact.id),
        ),
      ),
    );
  }
}
