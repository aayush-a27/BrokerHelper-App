import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/export_datasets.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import '../widgets/document_tools.dart';

enum _GroupBy { property, contact, deal, kind }

extension on _GroupBy {
  String get label => switch (this) {
        _GroupBy.property => 'Property',
        _GroupBy.contact => 'Contact',
        _GroupBy.deal => 'Deal',
        _GroupBy.kind => 'Type',
      };
}

/// Documents — files grouped by property, contact or deal (report p. 6).
///
/// Files are copied into the diary's own folder on the phone. The app keeps
/// them; it does not verify them.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  _GroupBy _groupBy = _GroupBy.property;
  bool _missingOnly = false;

  Map<String, List<DocumentRecord>> _grouped(AppState state) {
    final docs = state.documents
        .where((d) => !_missingOnly || d.missing)
        .toList()
      ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));

    final map = <String, List<DocumentRecord>>{};
    for (final doc in docs) {
      final key = switch (_groupBy) {
        _GroupBy.property => doc.propertyId == null
            ? 'Not linked to a property'
            : state.propertyTitle(doc.propertyId),
        _GroupBy.contact => doc.contactId == null
            ? 'Not linked to a contact'
            : state.contactName(doc.contactId),
        _GroupBy.deal => doc.dealId == null
            ? 'Not linked to a deal'
            : state.deal(doc.dealId)?.title ?? 'Unknown deal',
        _GroupBy.kind => doc.kind.label,
      };
      map.putIfAbsent(key, () => []).add(doc);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final grouped = _grouped(state);
    final missing = state.missingDocuments.length;
    final expiring = state.documents.where((d) => d.isExpiringSoon).length;

    return MainScaffold(
      title: 'Documents',
      subtitle: '${pluralise(state.documents.length, 'file')} · '
          '$missing missing · $expiring expiring soon',
      embedded: widget.embedded,
      exportBuilder: () => ExportDatasets.documents(state, state.documents),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Files are kept inside the diary on this phone and '
                        'included in backups. Tap a file to open it.',
                        style: TextStyle(fontSize: 12, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              children: [
                FilterChip(
                  label: Text('Missing ($missing)'),
                  selected: _missingOnly,
                  onSelected: (v) => setState(() => _missingOnly = v),
                ),
                const SizedBox(width: 12),
                const VerticalDivider(width: 1),
                const SizedBox(width: 12),
                for (final group in _GroupBy.values) ...[
                  ChoiceChip(
                    label: Text('By ${group.label.toLowerCase()}'),
                    selected: _groupBy == group,
                    onSelected: (_) => setState(() => _groupBy = group),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: grouped.isEmpty
                ? const EmptyState(
                    icon: Icons.folder_open_outlined,
                    title: 'No documents',
                    message:
                        'Attach a file from a property, contact or deal screen.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      for (final entry in grouped.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 14, 16, 2),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry.key,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      Text(
                                        pluralise(entry.value.length, 'file'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                for (final doc in entry.value)
                                  DocumentTile(document: doc, showLinks: true),
                                const SizedBox(height: 6),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
