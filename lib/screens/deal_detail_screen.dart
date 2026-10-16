import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/document_tools.dart';
import '../widgets/form_fields.dart';
import 'contact_detail_screen.dart';
import 'deal_form_screen.dart';
import 'property_detail_screen.dart';
import 'task_form_screen.dart';
import 'tasks_screen.dart';

/// One transaction: stage, money, milestones, commission instalments and the
/// documents that go with it (report p. 4, 3.1).
class DealDetailScreen extends StatelessWidget {
  const DealDetailScreen({super.key, required this.dealId});

  final String dealId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final deal = state.deal(dealId);
    if (deal == null) {
      return const Scaffold(body: Center(child: Text('Deal not found')));
    }

    final property = state.property(deal.propertyId);
    final buyer = state.contact(deal.buyerContactId);
    final seller = state.contact(deal.sellerContactId);
    final payments = state.paymentsForDeal(deal.id);
    final tasks = state.tasksFor(EntityKind.deal, deal.id);
    final received = state.commissionReceivedFor(deal.id);
    final pending = state.commissionPendingFor(deal);

    return Scaffold(
      appBar: AppBar(
        title: Text(deal.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => DealFormScreen(existing: deal),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete this deal?'),
                    content: const Text(
                        'The deal and its commission records move to '
                        'Recently deleted for 30 days.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  final trashId = state.deleteDeal(deal.id);
                  if (trashId != null) {
                    showDeletedToast(context, deal.title,
                        () => state.restoreFromTrash(trashId));
                  }
                  Navigator.pop(context);
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete deal')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatMoney(deal.agreedValue),
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        StatusChip(
                            label: deal.stage.label, color: deal.stage.color),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Agreed property value'
                      '${deal.tokenAmount > 0 ? ' · token ${formatMoney(deal.tokenAmount)}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _Figure(
                            label: 'Commission expected',
                            value: formatMoney(deal.expectedCommission),
                            caption: deal.commissionType ==
                                    CommissionType.percentage
                                ? '${deal.commissionValue}% of value'
                                : 'Fixed fee',
                          ),
                        ),
                        Expanded(
                          child: _Figure(
                            label: 'Received',
                            value: formatMoney(received),
                            color: const Color(0xFF059669),
                          ),
                        ),
                        Expanded(
                          child: _Figure(
                            label: 'Pending',
                            value: formatMoney(pending),
                            color: const Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
                  for (final stage in DealStage.values) ...[
                    ChoiceChip(
                      label: Text(stage.label),
                      selected: deal.stage == stage,
                      selectedColor: stage.color.withValues(alpha: 0.18),
                      onSelected: (_) => state.setDealStage(deal, stage),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          DetailCard(
            title: 'Parties',
            children: [
              if (property != null)
                ListTile(
                  leading: PropertyThumb(
                    photo: property.photo,
                    icon: property.type.icon,
                    size: 44,
                  ),
                  title: Text(property.title),
                  subtitle: Text(property.shortAddress),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PropertyDetailScreen(propertyId: property.id),
                    ),
                  ),
                ),
              if (buyer != null)
                _PartyTile(contact: buyer, role: 'Buyer'),
              if (seller != null)
                _PartyTile(contact: seller, role: 'Seller'),
              InfoRow(
                label: 'Created',
                value: formatDate(deal.createdAt),
                icon: Icons.schedule_outlined,
              ),
              if (deal.closedAt != null)
                InfoRow(
                  label: 'Closed',
                  value: formatDate(deal.closedAt),
                  icon: Icons.flag_outlined,
                ),
            ],
          ),
          DetailCard(
            title: 'Milestones',
            children: [
              if (deal.milestones.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text('No milestones recorded for this deal.'),
                )
              else
                for (final milestone in deal.milestones)
                  CheckboxListTile(
                    value: milestone.done,
                    dense: true,
                    title: Text(milestone.label),
                    subtitle: Text(formatDate(milestone.at)),
                    onChanged: (v) {
                      milestone.done = v ?? false;
                      state.recordActivity(
                        milestone.done
                            ? 'Milestone completed'
                            : 'Milestone reopened',
                        '${milestone.label} — ${deal.title}',
                        EntityKind.deal,
                        deal.id,
                      );
                    },
                  ),
            ],
          ),
          DetailCard(
            title: 'Commission records (${payments.length})',
            trailing: TextButton.icon(
              onPressed: () => _addPayment(context, state, deal),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
            children: [
              if (payments.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'No instalments recorded. Add one to track what is due '
                    'and when.',
                  ),
                )
              else
                for (final payment in payments)
                  ListTile(
                    leading: IconButton(
                      tooltip: payment.isPaid
                          ? 'Mark as pending'
                          : 'Mark as received',
                      icon: Icon(
                        payment.isPaid
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: payment.isPaid
                            ? const Color(0xFF059669)
                            : Theme.of(context).colorScheme.outline,
                      ),
                      onPressed: () => state.togglePaymentPaid(payment),
                    ),
                    title: Text(
                      formatMoney(payment.amount),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      payment.isPaid
                          ? 'Received ${formatDate(payment.paidDate)}'
                              '${payment.note.isEmpty ? '' : ' · ${payment.note}'}'
                          : 'Due ${formatDate(payment.dueDate)}'
                              '${payment.note.isEmpty ? '' : ' · ${payment.note}'}',
                    ),
                    trailing: StatusChip(
                      label: payment.status.label,
                      color: payment.status.color,
                      dense: true,
                    ),
                    onLongPress: () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Delete this commission record?',
                        message: '${formatMoney(payment.amount)} due '
                            '${formatDate(payment.dueDate)}',
                        confirm: 'Delete',
                        destructive: true,
                      );
                      if (!ok || !context.mounted) return;
                      final trashId = state.deletePayment(payment.id);
                      if (trashId != null) {
                        showDeletedToast(context, 'Commission record',
                            () => state.restoreFromTrash(trashId));
                      }
                    },
                  ),
            ],
          ),
          DocumentsSection(kind: EntityKind.deal, id: deal.id),
          DetailCard(
            title: 'Follow-ups',
            trailing: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => TaskFormScreen(
                    relatedKind: EntityKind.deal,
                    relatedId: deal.id,
                    relatedLabel: deal.title,
                  ),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
            children: [
              if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text('Nothing scheduled for this deal.'),
                )
              else
                for (final task in tasks)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TaskTile(task: task),
                  ),
            ],
          ),
          if (deal.notes.isNotEmpty)
            DetailCard(
              title: 'Notes',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child:
                      Text(deal.notes, style: const TextStyle(height: 1.45)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static Future<void> _addPayment(
      BuildContext context, AppState state, Deal deal) async {
    final amount = TextEditingController(
      text: state.commissionPendingFor(deal).toStringAsFixed(0),
    );
    final note = TextEditingController();
    var dueDate = DateTime.now().add(const Duration(days: 15));
    var paid = false;

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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Commission record',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                MoneyField(controller: amount, label: 'Amount'),
                DateTimeField(
                  label: 'Due date',
                  value: dueDate,
                  includeTime: false,
                  onChanged: (v) =>
                      setSheetState(() => dueDate = v ?? dueDate),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: paid,
                  title: const Text('Already received'),
                  onChanged: (v) => setSheetState(() => paid = v),
                ),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.check),
                  label: const Text('Save record'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      final value = double.tryParse(amount.text.trim()) ?? 0;
      if (value > 0) {
        state.addPayment(PaymentRecord(
          id: state.nextId('pm'),
          dealId: deal.id,
          amount: value,
          dueDate: dueDate,
          paidDate: paid ? DateTime.now() : null,
          status: paid ? PaymentStatus.paid : PaymentStatus.pending,
          note: note.text.trim(),
        ));
      }
    }
    amount.dispose();
    note.dispose();
  }
}

class _PartyTile extends StatelessWidget {
  const _PartyTile({required this.contact, required this.role});

  final Contact contact;
  final String role;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(child: Text(contact.name[0])),
      title: Text(contact.name),
      subtitle: Text('$role · ${contact.phone}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ContactDetailScreen(contactId: contact.id),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.caption,
    this.color,
  });

  final String label;
  final String value;
  final String? caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 15, color: color),
        ),
        if (caption != null)
          Text(caption!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
