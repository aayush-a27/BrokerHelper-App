import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

/// Deleted records wait here for 30 days before they are gone for good.
class RecentlyDeletedScreen extends StatelessWidget {
  const RecentlyDeletedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final trash = state.trash;

    return MainScaffold(
      title: 'Recently deleted',
      subtitle: 'Kept for ${TrashEntry.retention.inDays} days, then removed',
      showQuickAdd: false,
      showSearch: false,
      actions: [
        if (trash.isNotEmpty)
          IconButton(
            tooltip: 'Empty',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'Empty recently deleted?',
                message: '${pluralise(trash.length, 'item')} will be '
                    'deleted for good, including any photos and files. '
                    'This can\'t be undone.',
                confirm: 'Delete for good',
                destructive: true,
              );
              if (ok) await state.emptyTrash();
            },
          ),
      ],
      body: trash.isEmpty
          ? const EmptyState(
              icon: Icons.delete_outline,
              title: 'Nothing here',
              message: 'Anything you delete waits here for 30 days, so a '
                  'mistake can be undone.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              itemCount: trash.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final entry = trash[i];
                final daysLeft =
                    entry.purgeAt.difference(DateTime.now()).inDays.clamp(0, 30);
                final extra = entry.records.entries
                    .where((e) => e.value.length > 1 ||
                        e.key != _primaryCollection(entry.kind))
                    .map((e) => '${e.value.length} ${e.key}')
                    .join(', ');
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(entry.kind.icon, size: 20)),
                    title: Text(entry.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${entry.kind.label} · deleted '
                      '${formatRelativeDay(entry.deletedAt).toLowerCase()} · '
                      '$daysLeft days left'
                      '${extra.isEmpty ? '' : '\nAlso: $extra'}',
                    ),
                    isThreeLine: extra.isNotEmpty,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'restore') {
                          state.restoreFromTrash(entry.id);
                          showToast(context, '${entry.title} restored',
                              icon: Icons.restore);
                        } else {
                          final ok = await confirmDialog(
                            context,
                            title: 'Delete for good?',
                            message: '${entry.title} can\'t be brought back.',
                            confirm: 'Delete',
                            destructive: true,
                          );
                          if (ok) await state.deleteForever(entry.id);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'restore', child: Text('Restore')),
                        PopupMenuItem(
                            value: 'forever', child: Text('Delete for good')),
                      ],
                    ),
                    onTap: () {
                      state.restoreFromTrash(entry.id);
                      showToast(context, '${entry.title} restored',
                          icon: Icons.restore);
                    },
                  ),
                );
              },
            ),
    );
  }

  static String _primaryCollection(EntityKind kind) => switch (kind) {
        EntityKind.lead => Collections.leads,
        EntityKind.contact => Collections.contacts,
        EntityKind.property => Collections.properties,
        EntityKind.visit => Collections.visits,
        EntityKind.task => Collections.tasks,
        EntityKind.deal => Collections.deals,
        EntityKind.payment => Collections.payments,
        EntityKind.document => Collections.documents,
      };
}
