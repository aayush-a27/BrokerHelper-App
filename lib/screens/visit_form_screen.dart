import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

/// Schedule or reschedule a site visit. Saving also drops a "confirm the
/// visit" reminder two hours before (report p. 3, 2.4).
class VisitFormScreen extends StatefulWidget {
  const VisitFormScreen({
    super.key,
    this.existing,
    this.property,
    this.lead,
    this.contact,
  });

  final SiteVisit? existing;
  final Property? property;
  final Lead? lead;
  final Contact? contact;

  @override
  State<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends State<VisitFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _notes;
  late final TextEditingController _feedback;

  String? _propertyId;
  String? _contactId;
  String? _leadId;
  late DateTime _scheduledAt;
  VisitStatus _status = VisitStatus.scheduled;
  VisitOutcome _outcome = VisitOutcome.pending;
  bool _createReminder = true;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final v = widget.existing;
    _notes = TextEditingController(text: v?.notes ?? '');
    _feedback = TextEditingController(text: v?.feedback ?? '');
    _propertyId = v?.propertyId ?? widget.property?.id;
    _contactId = v?.contactId ?? widget.contact?.id ?? widget.lead?.contactId;
    _leadId = v?.leadId ?? widget.lead?.id;
    _scheduledAt = v?.scheduledAt ?? _defaultSlot();
    _status = v?.status ?? VisitStatus.scheduled;
    _outcome = v?.outcome ?? VisitOutcome.pending;
  }

  /// Tomorrow at 11:00 — a realistic default slot.
  static DateTime _defaultSlot() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 11);
  }

  @override
  void dispose() {
    _notes.dispose();
    _feedback.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_propertyId == null) {
      showToast(context, 'Pick a property for this visit',
          icon: Icons.error_outline);
      return;
    }
    final state = context.read<AppState>();

    if (_isEditing) {
      final v = widget.existing!;
      final rescheduled = v.scheduledAt != _scheduledAt;
      v
        ..propertyId = _propertyId!
        ..contactId = _contactId
        ..leadId = _leadId
        ..status = _status
        ..outcome = _outcome
        ..feedback = _feedback.text.trim()
        ..notes = _notes.text.trim();
      if (rescheduled) {
        state.rescheduleVisit(v, _scheduledAt);
      } else {
        state.updateVisit(v);
      }
      showToast(context, rescheduled ? 'Visit rescheduled' : 'Visit updated',
          icon: Icons.check_circle_outline);
      Navigator.pop(context, v);
      return;
    }

    final created = SiteVisit(
      id: state.nextId('vs'),
      propertyId: _propertyId!,
      contactId: _contactId,
      leadId: _leadId,
      scheduledAt: _scheduledAt,
      status: _status,
      notes: _notes.text.trim(),
    );
    state.addVisit(created, createReminder: _createReminder);

    // A visit means the lead has moved past "contacted".
    final lead = state.lead(_leadId);
    if (lead != null && lead.status.isOpen) {
      state.setLeadStatus(lead, LeadStatus.siteVisit);
    }

    showToast(
      context,
      _createReminder
              ? 'Visit scheduled and reminder set'
              : 'Visit scheduled',
      icon: Icons.event_available,
    );
    Navigator.pop(context, created);
  }

  Future<void> _delete() async {
    final visit = widget.existing!;
    final ok = await confirmDialog(
      context,
      title: 'Delete this site visit?',
      message: 'The visit and its reminder will be removed. To keep a record '
          'that it did not happen, mark it Cancelled instead.',
      confirm: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final state = context.read<AppState>();
    final trashId = state.deleteVisit(visit.id);
    if (trashId != null) {
      showDeletedToast(
          context, 'Site visit', () => state.restoreFromTrash(trashId));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final property = state.property(_propertyId);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit site visit' : 'Schedule site visit'),
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
            FormSection(
              title: 'Property',
              children: [
                PickerField(
                  label: 'Property',
                  icon: Icons.home_work_outlined,
                  value: property?.title,
                  onTap: () async {
                    final picked = await showRecordPicker<Property>(
                      context: context,
                      title: 'Which property?',
                      items: state.properties,
                      titleBuilder: (p) => p.title,
                      subtitleBuilder: (p) =>
                          '${p.shortAddress} · ${formatMoney(p.price)} · ${p.status.label}',
                      leadingBuilder: (p) =>
                          PropertyThumb(photo: p.photo, icon: p.type.icon, size: 44),
                    );
                    if (picked != null) {
                      setState(() => _propertyId = picked.id);
                    }
                  },
                ),
                if (property != null && property.visitInstructions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.key_outlined),
                        title: const Text('Visit instructions'),
                        subtitle: Text(property.visitInstructions),
                      ),
                    ),
                  ),
              ],
            ),
            FormSection(
              title: 'Who is coming',
              children: [
                PickerField(
                  label: 'Buyer / contact',
                  icon: Icons.person_outline,
                  value: state.contact(_contactId)?.name,
                  onClear: () => setState(() => _contactId = null),
                  onTap: () async {
                    final picked = await showRecordPicker<Contact>(
                      context: context,
                      title: 'Who is visiting?',
                      items: state.contacts,
                      titleBuilder: (c) => c.name,
                      subtitleBuilder: (c) => '${c.phone} · ${c.role.label}',
                    );
                    if (picked != null) setState(() => _contactId = picked.id);
                  },
                ),
                PickerField(
                  label: 'Linked lead (optional)',
                  icon: Icons.filter_alt_outlined,
                  value: state.lead(_leadId)?.name,
                  onClear: () => setState(() => _leadId = null),
                  onTap: () async {
                    final picked = await showRecordPicker<Lead>(
                      context: context,
                      title: 'Link a lead',
                      items: state.leads,
                      titleBuilder: (l) => l.name,
                      subtitleBuilder: (l) =>
                          '${l.status.label} · ${l.preferredLocation}',
                    );
                    if (picked != null) {
                      setState(() {
                        _leadId = picked.id;
                        _contactId ??= picked.contactId;
                      });
                    }
                  },
                ),
              ],
            ),
            FormSection(
              title: 'When',
              children: [
                DateTimeField(
                  label: 'Date and time',
                  value: _scheduledAt,
                  onChanged: (v) =>
                      setState(() => _scheduledAt = v ?? _scheduledAt),
                ),
                ChipPicker<VisitStatus>(
                  label: 'Confirmation',
                  value: _status,
                  items: VisitStatus.values,
                  labelBuilder: (e) => e.label,
                  colorBuilder: (e) => e.color,
                  onChanged: (e) => setState(() => _status = e),
                ),
                if (!_isEditing)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _createReminder,
                    title: const Text('Create a reminder'),
                    subtitle: const Text('Two hours before the visit'),
                    onChanged: (v) => setState(() => _createReminder = v),
                  ),
              ],
            ),
            if (_isEditing)
              FormSection(
                title: 'Outcome',
                children: [
                  AppDropdown<VisitOutcome>(
                    label: 'Outcome',
                    value: _outcome,
                    items: VisitOutcome.values,
                    labelBuilder: (e) => e.label,
                    onChanged: (e) => setState(() => _outcome = e ?? _outcome),
                  ),
                  AppTextField(
                    controller: _feedback,
                    label: 'Buyer feedback',
                    maxLines: 3,
                  ),
                ],
              ),
            FormSection(
              title: 'Notes',
              children: [
                AppTextField(controller: _notes, label: 'Notes', maxLines: 3),
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
            icon: const Icon(Icons.event_available),
            label: Text(_isEditing ? 'Save changes' : 'Schedule visit'),
          ),
        ),
      ),
    );
  }
}
