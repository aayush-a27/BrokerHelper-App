import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/export_datasets.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';
import '../widgets/whatsapp_sheet.dart';
import 'property_detail_screen.dart';
import 'tasks_screen.dart';
import 'visit_form_screen.dart';

/// Visits & Tasks — calendar, reminders and outcomes (report p. 6).
class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return MainScaffold(
      title: 'Visits & tasks',
      subtitle: '${state.upcomingVisits.length} upcoming · '
          '${state.overdueTasks.length} overdue follow-ups',
      embedded: widget.embedded,
      exportBuilder: () => ExportDatasets.visits(state, state.visits),
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: 'Upcoming'),
          Tab(text: 'Calendar'),
          Tab(text: 'Follow-ups'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const VisitFormScreen()),
        ),
        icon: const Icon(Icons.event_available),
        label: const Text('Schedule'),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _UpcomingTab(),
          _CalendarTab(),
          TasksBody(),
        ],
      ),
    );
  }
}

class _UpcomingTab extends StatelessWidget {
  const _UpcomingTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final upcoming = state.upcomingVisits;
    final past = state.visits.where((v) => !v.isUpcoming).toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

    if (state.visits.isEmpty) {
      return const EmptyState(
        icon: Icons.event_busy_outlined,
        title: 'No site visits yet',
        message: 'Schedule one from a lead, a property, or the button below.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (upcoming.isNotEmpty) ...[
          const SectionHeader('Coming up',
              padding: EdgeInsets.fromLTRB(0, 8, 0, 8)),
          for (final visit in upcoming)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: VisitTile(visit: visit, expanded: true),
            ),
        ],
        if (past.isNotEmpty) ...[
          SectionHeader(
            'Past visits',
            subtitle: '${past.where((v) => v.outcome == VisitOutcome.pending).length} '
                'still need an outcome recorded',
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          ),
          for (final visit in past)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: VisitTile(visit: visit, expanded: true),
            ),
        ],
      ],
    );
  }
}

/// A two-week strip plus the selected day's appointments. Enough of a
/// calendar without pulling in a calendar package.
class _CalendarTab extends StatefulWidget {
  const _CalendarTab();

  @override
  State<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<_CalendarTab> {
  DateTime _selected = DateUtilsX.startOfDay(DateTime.now());
  int _weekOffset = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final start = DateUtilsX.startOfDay(DateTime.now())
        .subtract(const Duration(days: 3))
        .add(Duration(days: _weekOffset * 7));
    final days = List.generate(14, (i) => start.add(Duration(days: i)));
    final dayVisits = state.visitsOn(_selected);
    final dayTasks = state.tasks
        .where((t) => DateUtilsX.isSameDay(t.dueAt, _selected))
        .toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _weekOffset--),
              ),
              Expanded(
                child: Text(
                  formatLongDate(_selected),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() => _weekOffset++),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: days.length,
            itemBuilder: (context, i) {
              final day = days[i];
              final count = state.visitsOn(day).length;
              final selected = DateUtilsX.isSameDay(day, _selected);
              final today = DateUtilsX.isToday(day);
              final scheme = Theme.of(context).colorScheme;
              return GestureDetector(
                onTap: () => setState(() => _selected = day),
                child: Container(
                  width: 54,
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : scheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: today && !selected
                          ? scheme.primary
                          : scheme.outlineVariant,
                      width: today && !selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _weekday(day),
                        style: TextStyle(
                          fontSize: 11,
                          color: selected
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color:
                              selected ? scheme.onPrimary : scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 16,
                        height: 4,
                        decoration: BoxDecoration(
                          color: count == 0
                              ? Colors.transparent
                              : (selected ? scheme.onPrimary : scheme.primary),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: dayVisits.isEmpty && dayTasks.isEmpty
              ? const EmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'Nothing on this day',
                  message: 'Pick another date or schedule a visit.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    if (dayVisits.isNotEmpty) ...[
                      const SectionHeader('Site visits',
                          padding: EdgeInsets.fromLTRB(0, 8, 0, 8)),
                      for (final visit in dayVisits)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: VisitTile(visit: visit, expanded: true),
                        ),
                    ],
                    if (dayTasks.isNotEmpty) ...[
                      const SectionHeader('Follow-ups',
                          padding: EdgeInsets.fromLTRB(0, 8, 0, 8)),
                      for (final task in dayTasks)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TaskTile(task: task, showLink: true),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  static String _weekday(DateTime d) => const [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][d.weekday - 1];
}

/// One site visit. [expanded] adds the action row used on the list screens.
class VisitTile extends StatelessWidget {
  const VisitTile({super.key, required this.visit, this.expanded = false});

  final SiteVisit visit;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final property = state.property(visit.propertyId);
    final contact = state.contact(visit.contactId);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onTap: property == null
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PropertyDetailScreen(propertyId: property.id),
                      ),
                    ),
            leading: PropertyThumb(
              photo: property?.photo,
              icon: property?.type.icon ?? Icons.home_work_outlined,
              size: 48,
            ),
            title: Text(
              property?.title ?? 'Property removed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 3),
                Text(
                  '${formatRelativeDay(visit.scheduledAt)} · '
                  '${formatTime(visit.scheduledAt)}'
                  '${contact == null ? '' : ' · ${contact.name}'}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    StatusChip(
                        label: visit.status.label,
                        color: visit.status.color,
                        dense: true),
                    if (visit.outcome != VisitOutcome.pending)
                      StatusChip(
                        label: visit.outcome.label,
                        color: scheme.primary,
                        dense: true,
                      ),
                  ],
                ),
                if (visit.feedback.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '“${visit.feedback}”',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Wrap(
                children: [
                  if (visit.status != VisitStatus.confirmed &&
                      visit.status != VisitStatus.completed)
                    TextButton.icon(
                      onPressed: () {
                        visit.status = VisitStatus.confirmed;
                        state.updateVisit(visit);
                      },
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Confirm'),
                    ),
                  if (visit.status != VisitStatus.completed)
                    TextButton.icon(
                      onPressed: () => _recordOutcome(context, state, visit),
                      icon: const Icon(Icons.rate_review_outlined, size: 18),
                      label: const Text('Outcome'),
                    ),
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => VisitFormScreen(existing: visit),
                      ),
                    ),
                    icon: const Icon(Icons.schedule, size: 18),
                    label: const Text('Reschedule'),
                  ),
                  if (contact != null)
                    TextButton.icon(
                      onPressed: () => showWhatsAppSheet(
                        context,
                        phone: contact.phone,
                        contact: contact,
                        property: property,
                        visitAt: visit.scheduledAt,
                        initialTemplateId: 'visit',
                      ),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: const Text('Remind'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Future<void> _recordOutcome(
      BuildContext context, AppState state, SiteVisit visit) async {
    final feedback = TextEditingController(text: visit.feedback);
    var outcome =
        visit.outcome == VisitOutcome.pending ? VisitOutcome.interested : visit.outcome;

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
              Text('Record the outcome',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                state.propertyTitle(visit.propertyId),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ChipPicker<VisitOutcome>(
                label: 'Outcome',
                value: outcome,
                items: VisitOutcome.values
                    .where((o) => o != VisitOutcome.pending)
                    .toList(),
                labelBuilder: (o) => o.label,
                onChanged: (o) => setSheetState(() => outcome = o),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: feedback,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Buyer feedback',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.check),
                label: const Text('Save outcome'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (saved == true) {
      state.recordVisitOutcome(visit, outcome, feedback.text.trim());
      if (context.mounted) {
        showToast(context, 'Outcome recorded and the lead stage updated',
            icon: Icons.check_circle_outline);
      }
    }
    feedback.dispose();
  }
}
