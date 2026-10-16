import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

/// Add or edit a follow-up/reminder. Can be opened standalone from the
/// quick-add sheet or pre-linked from a lead, property, visit or deal.
class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({
    super.key,
    this.existing,
    this.relatedKind,
    this.relatedId,
    this.relatedLabel,
    this.suggestedTitle,
  });

  final BrokerTask? existing;
  final EntityKind? relatedKind;
  final String? relatedId;
  final String? relatedLabel;
  final String? suggestedTitle;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _notes;

  TaskType _type = TaskType.call;
  late DateTime _dueAt;
  bool _done = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _title = TextEditingController(
        text: t?.title ?? widget.suggestedTitle ?? '');
    _notes = TextEditingController(text: t?.notes ?? '');
    _type = t?.type ?? TaskType.call;
    _dueAt = t?.dueAt ?? _defaultDue();
    _done = t?.done ?? false;
  }

  /// Tomorrow at 10:00 — the most common answer, so the broker rarely has to
  /// open the picker at all.
  static DateTime _defaultDue() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 10);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();

    if (_isEditing) {
      final t = widget.existing!
        ..title = _title.text.trim()
        ..type = _type
        ..dueAt = _dueAt
        ..notes = _notes.text.trim()
        ..done = _done;
      state.updateTask(t);
      showToast(context, 'Follow-up updated', icon: Icons.check_circle_outline);
      Navigator.pop(context, t);
      return;
    }

    final created = BrokerTask(
      id: state.nextId('tk'),
      title: _title.text.trim(),
      type: _type,
      dueAt: _dueAt,
      notes: _notes.text.trim(),
      relatedKind: widget.relatedKind,
      relatedId: widget.relatedId,
    );
    state.addTask(created);
    showToast(
      context,
      'Follow-up saved',
      icon: Icons.check_circle_outline,
    );
    Navigator.pop(context, created);
  }

  Future<void> _delete() async {
    final task = widget.existing!;
    final ok = await confirmDialog(
      context,
      title: 'Delete this follow-up?',
      message: '"${task.title}" and its reminder will be removed.',
      confirm: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final state = context.read<AppState>();
    final trashId = state.deleteTask(task.id);
    if (trashId != null) {
      showDeletedToast(
          context, 'Follow-up', () => state.restoreFromTrash(trashId));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit follow-up' : 'New follow-up'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            if (widget.relatedLabel != null)
              Card(
                child: ListTile(
                  leading: Icon(widget.relatedKind?.icon ?? Icons.link),
                  title: Text(widget.relatedLabel!),
                  subtitle:
                      Text('Linked ${widget.relatedKind?.label.toLowerCase()}'),
                ),
              ),
            FormSection(
              title: 'What needs doing',
              children: [
                AppTextField(
                  controller: _title,
                  label: 'Title',
                  hint: 'Call Rohit about loan pre-approval',
                  prefixIcon: Icons.task_alt,
                  validator: (v) => requiredField(v, 'Title'),
                  autofocus: !_isEditing,
                ),
                ChipPicker<TaskType>(
                  label: 'Type',
                  value: _type,
                  items: TaskType.values,
                  labelBuilder: (e) => e.label,
                  onChanged: (e) => setState(() => _type = e),
                ),
              ],
            ),
            FormSection(
              title: 'When',
              children: [
                DateTimeField(
                  label: 'Due',
                  value: _dueAt,
                  onChanged: (v) => setState(() => _dueAt = v ?? _dueAt),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final preset in const [
                      ('Today 6 pm', 0, 18),
                      ('Tomorrow 10 am', 1, 10),
                      ('In 3 days', 3, 10),
                      ('Next week', 7, 10),
                    ])
                      ActionChip(
                        label: Text(preset.$1),
                        onPressed: () {
                          final now = DateTime.now();
                          setState(() => _dueAt = DateTime(now.year, now.month,
                              now.day + preset.$2, preset.$3));
                        },
                      ),
                  ],
                ),
              ],
            ),
            FormSection(
              title: 'Who and why',
              children: [
                AppTextField(controller: _notes, label: 'Notes', maxLines: 3),
                if (_isEditing)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _done,
                    title: const Text('Completed'),
                    onChanged: (v) => setState(() => _done = v),
                  ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(_isEditing ? 'Save changes' : 'Save follow-up'),
          ),
        ),
      ),
    );
  }
}
