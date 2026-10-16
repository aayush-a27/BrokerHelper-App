import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

class DealFormScreen extends StatefulWidget {
  const DealFormScreen({
    super.key,
    this.existing,
    this.property,
    this.lead,
    this.buyer,
  });

  final Deal? existing;
  final Property? property;
  final Lead? lead;
  final Contact? buyer;

  @override
  State<DealFormScreen> createState() => _DealFormScreenState();
}

class _DealFormScreenState extends State<DealFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _agreedValue;
  late final TextEditingController _tokenAmount;
  late final TextEditingController _commissionValue;
  late final TextEditingController _notes;

  String? _propertyId;
  String? _buyerId;
  String? _sellerId;
  String? _leadId;
  DealStage _stage = DealStage.prospect;
  CommissionType _commissionType = CommissionType.percentage;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    final property = widget.property;
    final lead = widget.lead;

    _propertyId = d?.propertyId ?? property?.id;
    _buyerId = d?.buyerContactId ?? widget.buyer?.id ?? lead?.contactId;
    _sellerId = d?.sellerContactId ?? property?.ownerContactId;
    _leadId = d?.leadId ?? lead?.id;
    _stage = d?.stage ?? DealStage.prospect;
    _commissionType = d?.commissionType ?? CommissionType.percentage;

    final suggestedTitle = d?.title ??
        [
          property?.title,
          lead?.name ?? widget.buyer?.name,
        ].whereType<String>().join(' — ');

    _title = TextEditingController(text: suggestedTitle);
    _agreedValue = TextEditingController(
      text: _num(d?.agreedValue ?? property?.price),
    );
    _tokenAmount = TextEditingController(text: _num(d?.tokenAmount));
    _commissionValue =
        TextEditingController(text: _num(d?.commissionValue ?? 2));
    _notes = TextEditingController(text: d?.notes ?? '');
  }

  static String _num(double? v) {
    if (v == null || v <= 0) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _agreedValue,
      _tokenAmount,
      _commissionValue,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _amount(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  double get _expectedCommission {
    final value = _amount(_agreedValue);
    final commission = _amount(_commissionValue);
    return _commissionType == CommissionType.fixed
        ? commission
        : value * commission / 100;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();

    if (_isEditing) {
      final d = widget.existing!;
      final stageChanged = d.stage != _stage;
      d
        ..title = _title.text.trim()
        ..propertyId = _propertyId
        ..buyerContactId = _buyerId
        ..sellerContactId = _sellerId
        ..leadId = _leadId
        ..agreedValue = _amount(_agreedValue)
        ..tokenAmount = _amount(_tokenAmount)
        ..commissionType = _commissionType
        ..commissionValue = _amount(_commissionValue)
        ..notes = _notes.text.trim();
      if (stageChanged) {
        final target = _stage;
        d.stage = widget.existing!.stage;
        state.setDealStage(d, target);
      } else {
        state.updateDeal(d);
      }
      showToast(context, 'Deal updated', icon: Icons.check_circle_outline);
      Navigator.pop(context, d);
      return;
    }

    final created = Deal(
      id: state.nextId('dl'),
      title: _title.text.trim(),
      propertyId: _propertyId,
      buyerContactId: _buyerId,
      sellerContactId: _sellerId,
      leadId: _leadId,
      stage: _stage,
      agreedValue: _amount(_agreedValue),
      tokenAmount: _amount(_tokenAmount),
      commissionType: _commissionType,
      commissionValue: _amount(_commissionValue),
      notes: _notes.text.trim(),
    );
    state.addDeal(created);

    final property = state.property(_propertyId);
    if (property != null && property.status == PropertyStatus.available) {
      state.setPropertyStatus(property, PropertyStatus.underNegotiation);
    }

    showToast(
      context,
      'Deal created',
      icon: Icons.check_circle_outline,
    );
    Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit deal' : 'New deal'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            FormSection(
              title: 'The deal',
              children: [
                AppTextField(
                  controller: _title,
                  label: 'Deal name',
                  prefixIcon: Icons.handshake_outlined,
                  validator: (v) => requiredField(v, 'Deal name'),
                ),
                AppDropdown<DealStage>(
                  label: 'Stage',
                  value: _stage,
                  items: DealStage.values,
                  icon: Icons.timeline_outlined,
                  labelBuilder: (e) => e.label,
                  onChanged: (e) => setState(() => _stage = e ?? _stage),
                ),
              ],
            ),
            FormSection(
              title: 'Parties',
              children: [
                PickerField(
                  label: 'Property',
                  icon: Icons.home_work_outlined,
                  value: state.property(_propertyId)?.title,
                  onClear: () => setState(() => _propertyId = null),
                  onTap: () async {
                    final picked = await showRecordPicker<Property>(
                      context: context,
                      title: 'Which property?',
                      items: state.properties,
                      titleBuilder: (p) => p.title,
                      subtitleBuilder: (p) =>
                          '${p.shortAddress} · ${formatMoney(p.price)}',
                      leadingBuilder: (p) => PropertyThumb(
                          photo: p.photo, icon: p.type.icon, size: 44),
                    );
                    if (picked != null) {
                      setState(() {
                        _propertyId = picked.id;
                        _sellerId ??= picked.ownerContactId;
                        if (_agreedValue.text.isEmpty) {
                          _agreedValue.text = _num(picked.price);
                        }
                      });
                    }
                  },
                ),
                PickerField(
                  label: 'Buyer',
                  icon: Icons.person_outline,
                  value: state.contact(_buyerId)?.name,
                  onClear: () => setState(() => _buyerId = null),
                  onTap: () async {
                    final picked = await showRecordPicker<Contact>(
                      context: context,
                      title: 'Buyer',
                      items:
                          state.contacts.where((c) => c.role.isBuyer).toList(),
                      titleBuilder: (c) => c.name,
                      subtitleBuilder: (c) => c.phone,
                    );
                    if (picked != null) setState(() => _buyerId = picked.id);
                  },
                ),
                PickerField(
                  label: 'Seller',
                  icon: Icons.sell_outlined,
                  value: state.contact(_sellerId)?.name,
                  onClear: () => setState(() => _sellerId = null),
                  onTap: () async {
                    final picked = await showRecordPicker<Contact>(
                      context: context,
                      title: 'Seller',
                      items:
                          state.contacts.where((c) => c.role.isSeller).toList(),
                      titleBuilder: (c) => c.name,
                      subtitleBuilder: (c) => c.phone,
                    );
                    if (picked != null) setState(() => _sellerId = picked.id);
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
                      subtitleBuilder: (l) => l.status.label,
                    );
                    if (picked != null) setState(() => _leadId = picked.id);
                  },
                ),
              ],
            ),
            FormSection(
              title: 'Money',
              children: [
                MoneyField(
                  controller: _agreedValue,
                  label: 'Agreed property value',
                ),
                MoneyField(
                  controller: _tokenAmount,
                  label: 'Token amount',
                ),
                ChipPicker<CommissionType>(
                  label: 'Commission',
                  value: _commissionType,
                  items: CommissionType.values,
                  labelBuilder: (e) => e.label,
                  onChanged: (e) => setState(() => _commissionType = e),
                ),
                AppTextField(
                  controller: _commissionValue,
                  label: _commissionType == CommissionType.fixed
                      ? 'Fixed fee (₹)'
                      : 'Percentage of value (%)',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  prefixIcon: _commissionType == CommissionType.fixed
                      ? Icons.currency_rupee
                      : Icons.percent,
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: const Text('Expected commission'),
                    subtitle: const Text('As agreed by the parties'),
                    trailing: Text(
                      formatMoney(_expectedCommission),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
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
            icon: const Icon(Icons.check),
            label: Text(_isEditing ? 'Save changes' : 'Create deal'),
          ),
        ),
      ),
    );
  }
}
