import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/export_datasets.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import 'deal_detail_screen.dart';
import 'lead_detail_screen.dart';
import 'property_detail_screen.dart';
import 'task_form_screen.dart';

enum TaskFilter { open, today, overdue, done, all }

extension on TaskFilter {
  String get label => switch (this) {
        TaskFilter.open => 'Open',
        TaskFilter.today => 'Today',
        TaskFilter.overdue => 'Overdue',
        TaskFilter.done => 'Done',
        TaskFilter.all => 'All',
      };
}

/// Follow-ups and reminders. Also embedded as a tab inside Visits.
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MainScaffold(
      title: 'Follow-ups',
      subtitle: '${state.todaysTasks.length} due today · '
          '${state.overdueTasks.length} overdue',
      embedded: embedded,
      exportBuilder: () => ExportDatasets.tasks(state, state.tasks),
      body: const TasksBody(),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const TaskFormScreen()),
        ),
        icon: const Icon(Icons.add_task),
        label: const Text('Follow-up'),
      ),
    );
  }
}

/// The list itself, without any scaffold, so Visits can show it as a tab.
class TasksBody extends StatefulWidget {
  const TasksBody({super.key});

  @override
  State<TasksBody> createState() => _TasksBodyState();
}

class _TasksBodyState extends State<TasksBody> {
  TaskFilter _filter = TaskFilter.open;

  List<BrokerTask> _apply(AppState state) {
    final list = state.tasks.where((t) {
      return switch (_filter) {
        TaskFilter.open => !t.done,
        TaskFilter.today => !t.done && DateUtilsX.isToday(t.dueAt),
        TaskFilter.overdue => t.isOverdue,
        TaskFilter.done => t.done,
        TaskFilter.all => true,
      };
    }).toList()
      ..sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        return a.dueAt.compareTo(b.dueAt);
      });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tasks = _apply(state);

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            children: [
              for (final filter in TaskFilter.values) ...[
                FilterChip(
                  label: Text(filter.label),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Expanded(
          child: tasks.isEmpty
              ? const EmptyState(
                  icon: Icons.check_circle_outline,
                  title: 'Nothing here',
                  message: 'No follow-ups match this filter.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: tasks.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TaskTile(task: tasks[i], showLink: true),
                  ),
                ),
        ),
      ],
    );
  }
}

/// One follow-up row with a tick box, used on the dashboard, the lead
/// detail screen and the follow-up list.
class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, this.showLink = false});

  final BrokerTask task;
  final bool showLink;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final overdue = task.isOverdue;

    return Card(
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => TaskFormScreen(existing: task),
          ),
        ),
        leading: Checkbox(
          value: task.done,
          onChanged: (_) => state.toggleTaskDone(task),
        ),
        title: Text(
          task.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: task.done ? TextDecoration.lineThrough : null,
            color: task.done ? scheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            // A Wrap, not a Row: "Document collection" plus "2 days overdue ·
            // 10:00 AM" does not fit one line on a narrow handset.
            Wrap(
              spacing: 10,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(task.type.icon,
                        size: 13, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        task.type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      overdue ? Icons.warning_amber_rounded : Icons.schedule,
                      size: 13,
                      color: overdue ? scheme.error : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${formatRelativeDay(task.dueAt)} · ${formatTime(task.dueAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              overdue ? scheme.error : scheme.onSurfaceVariant,
                          fontWeight:
                              overdue ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (showLink && task.relatedKind != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: InkWell(
                  onTap: () => _openLinked(context, state, task),
                  child: Row(
                    children: [
                      Icon(task.relatedKind!.icon,
                          size: 13, color: scheme.primary),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _linkLabel(state, task),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _linkLabel(AppState state, BrokerTask task) {
    return switch (task.relatedKind) {
      EntityKind.lead => state.lead(task.relatedId)?.name ?? 'Lead',
      EntityKind.property =>
        state.property(task.relatedId)?.title ?? 'Property',
      EntityKind.deal => state.deal(task.relatedId)?.title ?? 'Deal',
      EntityKind.visit =>
        state.propertyTitle(state.visit(task.relatedId)?.propertyId),
      _ => task.relatedKind?.label ?? '',
    };
  }

  static void _openLinked(
      BuildContext context, AppState state, BrokerTask task) {
    final id = task.relatedId;
    if (id == null) return;
    final visitPropertyId = state.visit(id)?.propertyId;
    final Widget? screen = switch (task.relatedKind) {
      EntityKind.lead => LeadDetailScreen(leadId: id),
      EntityKind.property => PropertyDetailScreen(propertyId: id),
      EntityKind.deal => DealDetailScreen(dealId: id),
      EntityKind.visit => visitPropertyId == null
          ? null
          : PropertyDetailScreen(propertyId: visitPropertyId),
      _ => null,
    };
    if (screen == null) return;
    Navigator.push(
        context, MaterialPageRoute<void>(builder: (_) => screen));
  }
}
