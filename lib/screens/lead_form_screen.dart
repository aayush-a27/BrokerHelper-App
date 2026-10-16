import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/voice_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';
import '../widgets/voice_capture_sheet.dart';

/// Add or edit a lead.
class LeadFormScreen extends StatefulWidget {
  const LeadFormScreen({super.key, this.existing, this.prefill});

  /// When set the form edits this lead in place; otherwise it creates one.
  final Lead? existing;

  /// Values handed over from the voice-to-record review screen.
  final VoiceCapture? prefill;

  @override
  State<LeadFormScreen> createState() => _LeadFormScreenState();
}

class _LeadFormScreenState extends State<LeadFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _budgetMin;
  late final TextEditingController _budgetMax;
  late final TextEditingController _location;
  late final TextEditingController _requirements;
  late final TextEditingController _notes;

  LeadSource _source = LeadSource.phoneCall;
  LeadStatus _status = LeadStatus.newLead;
  Priority _priority = Priority.medium;
  PropertyType _type = PropertyType.apartment;
  int _bedrooms = 2;
  DateTime? _followUp;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final lead = widget.existing;
    final voice = widget.prefill;

    _name = TextEditingController(text: lead?.name ?? voice?.name ?? '');
    _phone = TextEditingController(text: lead?.phone ?? voice?.phone ?? '');
    _email = TextEditingController(text: lead?.email ?? '');
    _budgetMin = TextEditingController(
        text: _amountText(lead?.budgetMin ?? voice?.budgetMin ?? 0));
    _budgetMax = TextEditingController(
        text: _amountText(lead?.budgetMax ?? voice?.budgetMax ?? 0));
    _location = TextEditingController(
        text: lead?.preferredLocation ?? voice?.location ?? '');
    _requirements = TextEditingController(text: lead?.requirements ?? '');
    _notes = TextEditingController(text: lead?.notes ?? voice?.notes ?? '');

    _source = lead?.source ?? (voice != null ? LeadSource.other : LeadSource.phoneCall);
    _status = lead?.status ?? LeadStatus.newLead;
    _priority = lead?.priority ?? Priority.medium;
    _type = lead?.propertyType ?? voice?.propertyType ?? PropertyType.apartment;
    _bedrooms = lead?.bedrooms ?? voice?.bedrooms ?? 2;
    _followUp = lead?.nextFollowUpAt ?? voice?.followUpAt;
  }

  static String _amountText(double value) =>
      value <= 0 ? '' : value.toStringAsFixed(0);

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _email,
      _budgetMin,
      _budgetMax,
      _location,
      _requirements,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _dictate() async {
    final capture = await showVoiceCaptureSheet(context);
    if (capture == null || !mounted) return;
    setState(() {
      if ((capture.name ?? '').isNotEmpty) _name.text = capture.name!;
      if ((capture.phone ?? '').isNotEmpty) _phone.text = capture.phone!;
      if (capture.budgetMin > 0) _budgetMin.text = _amountText(capture.budgetMin);
      if (capture.budgetMax > 0) _budgetMax.text = _amountText(capture.budgetMax);
      if ((capture.location ?? '').isNotEmpty) _location.text = capture.location!;
      if (capture.propertyType != null) _type = capture.propertyType!;
      if (capture.bedrooms > 0) _bedrooms = capture.bedrooms;
      if (capture.followUpAt != null) _followUp = capture.followUpAt;
      _notes.text = _notes.text.isEmpty
          ? capture.transcript
          : '${_notes.text}\n${capture.transcript}';
    });
    if (mounted) {
      showToast(context, 'Voice note added to the form', icon: Icons.mic);
    }
  }

  double _amount(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    if (_isEditing) {
      final lead = widget.existing!;
      final previousFollowUp = lead.nextFollowUpAt;
      lead
        ..name = _name.text.trim()
        ..phone = _phone.text.trim()
        ..email = _email.text.trim()
        ..source = _source
        ..status = _status
        ..priority = _priority
        ..budgetMin = _amount(_budgetMin)
        ..budgetMax = _amount(_budgetMax)
        ..preferredLocation = _location.text.trim()
        ..propertyType = _type
        ..bedrooms = _bedrooms
        ..requirements = _requirements.text.trim()
        ..notes = _notes.text.trim()
        ..nextFollowUpAt = _followUp;
      state.updateLead(lead, previousFollowUp: previousFollowUp);
      showToast(context, 'Lead updated', icon: Icons.check_circle_outline);
      Navigator.pop(context, lead);
      return;
    }

    final lead = Lead(
      id: state.nextId('ld'),
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      source: _source,
      status: _status,
      priority: _priority,
      budgetMin: _amount(_budgetMin),
      budgetMax: _amount(_budgetMax),
      preferredLocation: _location.text.trim(),
      propertyType: _type,
      bedrooms: _bedrooms,
      requirements: _requirements.text.trim(),
      notes: _notes.text.trim(),
      nextFollowUpAt: _followUp,
      createdAt: DateTime.now(),
    );
    state.addLead(lead);

    if (_followUp != null) {
      state.addTask(BrokerTask(
        id: state.nextId('tk'),
        title: 'Follow up with ${lead.name}',
        type: TaskType.call,
        dueAt: _followUp!,
        relatedKind: EntityKind.lead,
        relatedId: lead.id,
      ));
    }

    showToast(context, 'Lead saved', icon: Icons.check_circle_outline);
    Navigator.pop(context, lead);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final duplicates = _duplicates(state);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit lead' : 'New lead'),
        actions: [
          if (!_isEditing)
            IconButton(
              key: const Key('lead-form-dictate'),
              tooltip: 'Dictate',
              icon: const Icon(Icons.mic_none),
              onPressed: _dictate,
            ),
          TextButton(
            key: const Key('lead-form-save-appbar'),
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            if (duplicates.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _Banner(
                  icon: Icons.copy_all_outlined,
                  color: Theme.of(context).colorScheme.error,
                  text: 'Possible duplicate: '
                      '${duplicates.map((e) => e.name).take(2).join(', ')} '
                      'already ${duplicates.length == 1 ? 'has' : 'have'} this '
                      'number. Check before saving.',
                ),
              ),
            FormSection(
              title: 'Who',
              children: [
                AppTextField(
                  key: const Key('lead-form-name'),
                  controller: _name,
                  label: 'Name',
                  prefixIcon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => requiredField(v, 'Name'),
                  autofocus: !_isEditing,
                ),
                AppTextField(
                  key: const Key('lead-form-phone'),
                  controller: _phone,
                  label: 'Phone number',
                  prefixIcon: Icons.call_outlined,
                  keyboardType: TextInputType.phone,
                  validator: phoneField,
                  // Re-runs the duplicate check as the number is typed.
                  onChanged: (_) => setState(() {}),
                ),
                AppTextField(
                  key: const Key('lead-form-email'),
                  controller: _email,
                  label: 'Email (optional)',
                  prefixIcon: Icons.alternate_email,
                  keyboardType: TextInputType.emailAddress,
                  textCapitalization: TextCapitalization.none,
                ),
              ],
            ),
            FormSection(
              title: 'Where it came from',
              children: [
                ChipPicker<LeadSource>(
                  label: 'Source',
                  value: _source,
                  items: LeadSource.values,
                  labelBuilder: (e) => e.label,
                  onChanged: (e) => setState(() => _source = e),
                ),
                ChipPicker<Priority>(
                  label: 'Priority',
                  value: _priority,
                  items: Priority.values,
                  labelBuilder: (e) => e.label,
                  colorBuilder: (e) => e.color,
                  onChanged: (e) => setState(() => _priority = e),
                ),
                AppDropdown<LeadStatus>(
                  label: 'Status',
                  value: _status,
                  items: LeadStatus.values,
                  icon: Icons.flag_outlined,
                  labelBuilder: (e) => e.label,
                  onChanged: (e) => setState(() => _status = e ?? _status),
                ),
              ],
            ),
            FormSection(
              title: 'What they want',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MoneyField(
                        key: const Key('lead-form-budget-min'),
                        controller: _budgetMin,
                        label: 'Budget from',
                      ),
                    ),
                    Gap.m,
                    Expanded(
                      child: MoneyField(
                        key: const Key('lead-form-budget-max'),
                        controller: _budgetMax,
                        label: 'Budget to',
                      ),
                    ),
                  ],
                ),
                AppTextField(
                  key: const Key('lead-form-location'),
                  controller: _location,
                  label: 'Preferred location',
                  prefixIcon: Icons.place_outlined,
                  hint: 'Baner, Aundh',
                ),
                AppDropdown<PropertyType>(
                  label: 'Property type',
                  value: _type,
                  items: PropertyType.values,
                  icon: Icons.home_work_outlined,
                  labelBuilder: (e) => e.label,
                  onChanged: (e) => setState(() => _type = e ?? _type),
                ),
                ChipPicker<int>(
                  label: 'Bedrooms',
                  value: _bedrooms,
                  items: const [0, 1, 2, 3, 4, 5],
                  labelBuilder: (e) => e == 0 ? 'Any' : '$e BHK',
                  onChanged: (e) => setState(() => _bedrooms = e),
                ),
                AppTextField(
                  key: const Key('lead-form-requirements'),
                  controller: _requirements,
                  label: 'Must-have requirements',
                  hint: 'Covered parking, east facing, ready to move',
                  maxLines: 2,
                ),
              ],
            ),
            FormSection(
              title: 'Next step',
              children: [
                DateTimeField(
                  label: 'Next follow-up',
                  value: _followUp,
                  clearable: true,
                  onChanged: (v) => setState(() => _followUp = v),
                ),
                AppTextField(
                  key: const Key('lead-form-notes'),
                  controller: _notes,
                  label: 'Notes',
                  maxLines: 4,
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
            key: const Key('lead-form-save'),
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(_isEditing ? 'Save changes' : 'Save lead'),
          ),
        ),
      ),
    );
  }

  List<Lead> _duplicates(AppState state) {
    final phone = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (phone.length < 10) return const [];
    final probe = Lead(
      id: widget.existing?.id ?? '__new__',
      name: _name.text,
      phone: _phone.text,
    );
    return state.duplicateLeadsFor(probe);
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
