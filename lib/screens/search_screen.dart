import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import 'contacts_screen.dart';
import 'leads_screen.dart';
import 'properties_screen.dart';

/// One search box across leads, contacts and properties (report p. 5).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final results = state.search(_controller.text);
    final query = _controller.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search leads, contacts and properties',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(_controller.clear),
                  ),
          ),
        ),
      ),
      body: query.isEmpty
          ? const EmptyState(
              icon: Icons.search,
              title: 'Search everything',
              message:
                  'Type a name, a phone number, a locality or a feature. '
                  'Leads, contacts and properties are searched together.',
            )
          : results.isEmpty
              ? EmptyState(
                  icon: Icons.search_off,
                  title: 'Nothing found',
                  message: 'No lead, contact or property matches “$query”.',
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        '${pluralise(results.total, 'result')} for “$query”',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (results.leads.isNotEmpty) ...[
                      SectionHeader('Leads (${results.leads.length})'),
                      for (final lead in results.leads)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: LeadCard(lead: lead),
                        ),
                    ],
                    if (results.contacts.isNotEmpty) ...[
                      SectionHeader('Contacts (${results.contacts.length})'),
                      for (final contact in results.contacts)
                        ContactTile(contact: contact),
                    ],
                    if (results.properties.isNotEmpty) ...[
                      SectionHeader(
                          'Properties (${results.properties.length})'),
                      for (final property in results.properties)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: PropertyCard(property: property),
                        ),
                    ],
                  ],
                ),
    );
  }
}
