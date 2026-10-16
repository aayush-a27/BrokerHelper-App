import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/export_datasets.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import 'deal_detail_screen.dart';
import 'deal_form_screen.dart';

/// Deals — stages, commission and payment status (report p. 6).
class DealsScreen extends StatefulWidget {
  const DealsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<DealsScreen> createState() => _DealsScreenState();
}

class _DealsScreenState extends State<DealsScreen> {
  bool _pipeline = true;
  DealStage? _stage;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final deals = _stage == null
        ? state.deals
        : state.deals.where((d) => d.stage == _stage).toList();

    return MainScaffold(
      title: 'Deals',
      subtitle: '${state.openDeals.length} open · '
          '${formatMoney(state.totalPendingCommission)} commission pending',
      embedded: widget.embedded,
      exportBuilder: () => ExportDatasets.deals(state, deals),
      actions: [
        IconButton(
          tooltip: _pipeline ? 'List view' : 'Pipeline view',
          icon: Icon(_pipeline ? Icons.view_list_outlined : Icons.view_kanban_outlined),
          onPressed: () => setState(() => _pipeline = !_pipeline),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const DealFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Deal'),
      ),
      body: Column(
        children: [
          _CommissionStrip(state: state),
          if (_pipeline)
            Expanded(child: _PipelineBoard(state: state))
          else ...[
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final stage in DealStage.values) ...[
                    FilterChip(
                      label: Text(stage.label),
                      selected: _stage == stage,
                      selectedColor: stage.color.withValues(alpha: 0.18),
                      onSelected: (v) =>
                          setState(() => _stage = v ? stage : null),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Expanded(
              child: deals.isEmpty
                  ? const EmptyState(
                      icon: Icons.handshake_outlined,
                      title: 'No deals here',
                      message:
                          'Create a deal from a lead or a property to start '
                          'tracking commission.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: deals.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DealCard(deal: deals[i]),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommissionStrip extends StatelessWidget {
  const _CommissionStrip({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _Figure(
                label: 'Expected',
                value: formatMoney(state.totalExpectedCommission),
              ),
              _Figure(
                label: 'Received',
                value: formatMoney(state.totalReceivedCommission),
                color: const Color(0xFF059669),
              ),
              _Figure(
                label: 'Pending',
                value: formatMoney(state.totalPendingCommission),
                color: const Color(0xFFDC2626),
              ),
              _Figure(
                label: 'Won / lost',
                value: '${state.dealsWon} / ${state.dealsLost}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14, color: color),
          ),
        ],
      ),
    );
  }
}

/// Horizontal board, one column per stage.
class _PipelineBoard extends StatelessWidget {
  const _PipelineBoard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        for (final stage in DealStage.values)
          _StageColumn(
            stage: stage,
            deals: state.deals.where((d) => d.stage == stage).toList(),
            state: state,
          ),
      ],
    );
  }
}

class _StageColumn extends StatelessWidget {
  const _StageColumn({
    required this.stage,
    required this.deals,
    required this.state,
  });

  final DealStage stage;
  final List<Deal> deals;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final total =
        deals.fold<double>(0, (sum, d) => sum + d.expectedCommission);
    return Container(
      width: 272,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: stage.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    stage.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: stage.color,
                    ),
                  ),
                ),
                Text(
                  '${deals.length}',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: stage.color),
                ),
              ],
            ),
          ),
          if (total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text(
                '${formatMoney(total)} expected',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: deals.isEmpty
                ? Center(
                    child: Text(
                      'Nothing here',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : ListView.builder(
                    itemCount: deals.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DealCard(deal: deals[i], compact: true),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class DealCard extends StatelessWidget {
  const DealCard({super.key, required this.deal, this.compact = false});

  final Deal deal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final received = state.commissionReceivedFor(deal.id);
    final pending = state.commissionPendingFor(deal);
    final property = state.property(deal.propertyId);

    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => DealDetailScreen(dealId: deal.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      deal.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    StatusChip(
                      label: deal.stage.label,
                      color: deal.stage.color,
                      dense: true,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              if (property != null)
                Row(
                  children: [
                    Icon(Icons.place_outlined,
                        size: 13, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        property.shortAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _Mini(
                      label: 'Value',
                      value: formatMoney(deal.agreedValue),
                    ),
                  ),
                  Expanded(
                    child: _Mini(
                      label: 'Commission',
                      value: formatMoney(deal.expectedCommission),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: deal.expectedCommission == 0
                          ? 0
                          : (received / deal.expectedCommission)
                              .clamp(0.0, 1.0),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(999),
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    pending == 0
                        ? 'Fully paid'
                        : '${formatMoney(pending)} due',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: pending == 0
                          ? const Color(0xFF059669)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ],
    );
  }
}
