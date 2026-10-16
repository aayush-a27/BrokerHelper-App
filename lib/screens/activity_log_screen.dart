import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

/// The diary's history: every change in [AppState] writes a line here.
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  EntityKind? _kind;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entries = _kind == null
        ? state.activities
        : state.activities.where((a) => a.entityKind == _kind).toList();

    final grouped = <String, List<ActivityEntry>>{};
    for (final entry in entries) {
      final key = DateUtilsX.isToday(entry.at)
          ? 'Today'
          : DateUtilsX.isSameDay(
                  entry.at, DateTime.now().subtract(const Duration(days: 1)))
              ? 'Yesterday'
              : formatDate(entry.at);
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    return MainScaffold(
      title: 'Activity log',
      subtitle: pluralise(entries.length, 'entry', 'entries'),
      embedded: widget.embedded,
      showQuickAdd: false,
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _kind == null,
                  onSelected: (_) => setState(() => _kind = null),
                ),
                const SizedBox(width: 8),
                for (final kind in EntityKind.values) ...[
                  FilterChip(
                    label: Text(kind.label),
                    avatar: Icon(kind.icon, size: 16),
                    selected: _kind == kind,
                    onSelected: (v) => setState(() => _kind = v ? kind : null),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const EmptyState(
                    icon: Icons.history,
                    title: 'Nothing logged',
                    message: 'Make a change and it will show up here.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      for (final group in grouped.entries) ...[
                        SectionHeader(
                          group.key,
                          padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
                        ),
                        Card(
                          child: Column(
                            children: [
                              for (final entry in group.value)
                                _ActivityTile(entry: entry, state: state),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.entry, required this.state});

  final ActivityEntry entry;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: scheme.surfaceContainerHighest,
        child: Icon(entry.entityKind.icon, size: 16),
      ),
      title: Text(
        entry.action,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        entry.summary.isEmpty
            ? formatTime(entry.at)
            : '${entry.summary}\n${formatTime(entry.at)}',
        style: const TextStyle(fontSize: 12, height: 1.4),
      ),
      isThreeLine: entry.summary.isNotEmpty,
    );
  }
}
