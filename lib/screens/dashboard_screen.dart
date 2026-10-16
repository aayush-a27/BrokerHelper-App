import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../models/models.dart';
import '../services/export_datasets.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import 'deal_detail_screen.dart';
import 'lead_detail_screen.dart';
import 'tasks_screen.dart';
import 'visits_screen.dart';

/// Home / Today — key numbers, what is due and what is coming up
/// (report p. 4, 3.4).
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.profile;

    return MainScaffold(
      title: 'Today',
      subtitle: formatLongDate(DateTime.now()),
      embedded: embedded,
      exportBuilder: () => ExportDatasets.businessSummary(state),
      actions: [
        IconButton(
          tooltip: 'Profile',
          icon: const Icon(Icons.account_circle_outlined),
          onPressed: () => Navigator.pushNamed(context, Routes.profile),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (profile != null) _Greeting(profile: profile),
          const BackupNudgeBanner(),
          if (state.isEmpty)
            const _GettingStarted()
          else ...[
            _StatGrid(state: state),
            _TodaysTasks(state: state),
            _LeadFollowUps(state: state),
            _UpcomingVisits(state: state),
            _Pipeline(state: state),
            _CommissionCard(state: state),
          ],
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.profile});

  final BrokerProfile profile;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          CircleAvatar(radius: 24, child: Text(profile.initials)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$part, ${profile.name.split(' ').first}',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (profile.agency.isNotEmpty)
                Text(
                  profile.agency,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final overdue = state.overdueTasks.length;
    final cards = <Widget>[
      StatCard(
        label: 'New leads this week',
        value: '${state.newLeadsThisWeek.length}',
        icon: Icons.person_add_alt_1_outlined,
        caption: '${state.openLeads.length} open in total',
        onTap: () => Navigator.pushNamed(context, Routes.leads),
      ),
      StatCard(
        label: 'Follow-ups due today',
        value: '${state.todaysTasks.length}',
        icon: Icons.task_alt,
        tone: overdue > 0 ? Theme.of(context).colorScheme.error : null,
        caption: overdue > 0 ? '$overdue overdue' : 'Nothing overdue',
        onTap: () => Navigator.pushNamed(context, Routes.tasks),
      ),
      StatCard(
        label: 'Upcoming site visits',
        value: '${state.upcomingVisits.length}',
        icon: Icons.event_outlined,
        caption: '${state.visitsOn(DateTime.now()).length} today',
        onTap: () => Navigator.pushNamed(context, Routes.visits),
      ),
      StatCard(
        label: 'Active deals',
        value: '${state.openDeals.length}',
        icon: Icons.handshake_outlined,
        caption: '${state.dealsWon} won · ${state.dealsLost} lost',
        onTap: () => Navigator.pushNamed(context, Routes.deals),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      // A max-extent delegate rather than a fixed column count: the cards
      // keep a sensible size on a phone, a tablet and a wide browser window.
      child: GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisExtent: 148,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        children: cards,
      ),
    );
  }
}

class _TodaysTasks extends StatelessWidget {
  const _TodaysTasks({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final overdue = state.overdueTasks;
    final today = state.todaysTasks.where((t) => !t.isOverdue).toList();
    final items = [...overdue, ...today].take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Due now',
          subtitle: overdue.isEmpty
              ? 'Nothing overdue — good'
              : '${pluralise(overdue.length, 'follow-up')} overdue',
          action: TextButton(
            onPressed: () => Navigator.pushNamed(context, Routes.tasks),
            child: const Text('All tasks'),
          ),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Card(
              child: ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('Nothing due today'),
                subtitle: Text('Add a follow-up so the next step is not lost.'),
              ),
            ),
          )
        else
          for (final task in items)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TaskTile(task: task),
            ),
      ],
    );
  }
}

class _UpcomingVisits extends StatelessWidget {
  const _UpcomingVisits({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final visits = state.upcomingVisits.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Upcoming visits',
          subtitle: visits.isEmpty
              ? 'No visits booked'
              : 'Next: ${formatRelativeDay(visits.first.scheduledAt)}',
          action: TextButton(
            onPressed: () => Navigator.pushNamed(context, Routes.visits),
            child: const Text('Calendar'),
          ),
        ),
        if (visits.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Card(
              child: ListTile(
                leading: Icon(Icons.event_busy_outlined),
                title: Text('Nothing scheduled'),
              ),
            ),
          )
        else
          for (final visit in visits)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: VisitTile(visit: visit),
            ),
      ],
    );
  }
}

class _Pipeline extends StatelessWidget {
  const _Pipeline({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final byStage = state.leadsByStage;
    final bySource = state.leadsBySource;
    final total = state.leads.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Lead pipeline',
          subtitle: '${pluralise(total, 'lead')} · '
              '${(state.leadsWithNextActionRatio * 100).round()}% have a next action',
          action: TextButton(
            onPressed: () => Navigator.pushNamed(context, Routes.reports),
            child: const Text('Reports'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  for (final status in LeadStatus.values)
                    BreakdownBar(
                      label: status.label,
                      count: byStage[status] ?? 0,
                      total: total,
                      color: status.color,
                    ),
                  const Divider(height: 20, indent: 16, endIndent: 16),
                  for (final source in LeadSource.values)
                    BreakdownBar(
                      label: source.label,
                      count: bySource[source] ?? 0,
                      total: total,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CommissionCard extends StatelessWidget {
  const _CommissionCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final expected = state.totalExpectedCommission;
    final received = state.totalReceivedCommission;
    final pending = state.totalPendingCommission;
    final ratio = expected == 0 ? 0.0 : (received / expected).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Commission',
          subtitle: 'Expected versus received',
          action: TextButton(
            onPressed: () => Navigator.pushNamed(context, Routes.deals),
            child: const Text('Deals'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Money(
                            label: 'Expected', value: expected, strong: true),
                      ),
                      Expanded(
                        child: _Money(
                          label: 'Received',
                          value: received,
                          color: const Color(0xFF059669),
                        ),
                      ),
                      Expanded(
                        child: _Money(
                          label: 'Pending',
                          value: pending,
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 10,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(ratio * 100).round()}% of expected commission collected',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Money extends StatelessWidget {
  const _Money({
    required this.label,
    required this.value,
    this.color,
    this.strong = false,
  });

  final String label;
  final double value;
  final Color? color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          formatMoney(value),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                color: color,
              ),
        ),
      ],
    );
  }
}

/// Lead follow-ups due today or overdue that have no follow-up task of
/// their own (those already show under "Due now").
class _LeadFollowUps extends StatelessWidget {
  const _LeadFollowUps({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final leads = state.leadFollowUpsWithoutTask;
    if (leads.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Calls to make',
          subtitle: pluralise(leads.length, 'lead follow-up'),
        ),
        for (final lead in leads.take(6))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LeadMiniTile(lead: lead),
          ),
      ],
    );
  }
}

/// Shown on an empty diary: what to do first.
class _GettingStarted extends StatelessWidget {
  const _GettingStarted();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget step(int n, String title, String subtitle, IconData icon,
            VoidCallback onTap) =>
        ListTile(
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: scheme.primaryContainer,
            child: Text('$n',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer)),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
          trailing: Icon(icon),
          onTap: onTap,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          'Your diary is empty',
          subtitle: 'Three things to do first',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Card(
            child: Column(
              children: [
                step(1, 'Add your first lead', 'Tap + below — or dictate it',
                    Icons.person_add_alt_1_outlined,
                    () => Navigator.pushNamed(context, Routes.leads)),
                const Divider(height: 1, indent: 56),
                step(2, 'Add a property', 'With a photo from the camera',
                    Icons.home_work_outlined,
                    () => Navigator.pushNamed(context, Routes.properties)),
                const Divider(height: 1, indent: 56),
                step(3, 'Check reminders work', 'Send yourself a test reminder',
                    Icons.notifications_active_outlined,
                    () => Navigator.pushNamed(context, Routes.reminderHelp)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared by the dashboard and the leads list for a compact "next action"
/// row. Kept here so both stay identical.
class LeadMiniTile extends StatelessWidget {
  const LeadMiniTile({super.key, required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: lead.status.color.withValues(alpha: 0.15),
          child: Text(
            lead.name.isEmpty ? '?' : lead.name[0].toUpperCase(),
            style: TextStyle(
                color: lead.status.color, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(lead.name),
        subtitle: Text(
          '${lead.preferredLocation} · ${formatBudgetRange(lead.budgetMin, lead.budgetMax)}',
        ),
        trailing: StatusChip(
            label: lead.status.label, color: lead.status.color, dense: true),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => LeadDetailScreen(leadId: lead.id),
          ),
        ),
      ),
    );
  }
}

/// Compact deal row reused by the dashboard and the reports screen.
class DealMiniTile extends StatelessWidget {
  const DealMiniTile({super.key, required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(deal.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(formatMoney(deal.agreedValue)),
        trailing: StatusChip(
            label: deal.stage.label, color: deal.stage.color, dense: true),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => DealDetailScreen(dealId: deal.id),
          ),
        ),
      ),
    );
  }
}
