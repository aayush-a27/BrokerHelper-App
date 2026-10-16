import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

/// Add or edit a buyer/seller. One person gets one record even when they are
/// both buying and selling — the role chips carry that (report p. 3, 2.2).
class ContactFormScreen extends StatefulWidget {
  const ContactFormScreen({super.key, this.existing, this.initialRole});

  final Contact? existing;
  final ContactRole? initialRole;

  @override
  State<ContactFormScreen> createState() => _ContactFormScreenState();
}

class _ContactFormScreenState extends State<ContactFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _locality;
  late final TextEditingController _notes;
  late final TextEditingController _budgetMin;
  late final TextEditingController _budgetMax;
  late final TextEditingController _preferredLocations;
  late final TextEditingController _mustHaves;
  late final TextEditingController _askingPrice;
  late final TextEditingController _expectedMin;
  late final TextEditingController _contactTime;

  ContactRole _role = ContactRole.buyer;
  int _bedrooms = 2;
  final Set<PropertyType> _types = {PropertyType.apartment};

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _locality = TextEditingController(text: c?.locality ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _budgetMin = TextEditingController(text: _money(c?.buyer.budgetMin));
    _budgetMax = TextEditingController(text: _money(c?.buyer.budgetMax));
    _preferredLocations = TextEditingController(
        text: c?.buyer.preferredLocations.join(', ') ?? '');
    _mustHaves =
        TextEditingController(text: c?.buyer.mustHaves.join(', ') ?? '');
    _askingPrice = TextEditingController(text: _money(c?.seller.askingPrice));
    _expectedMin =
        TextEditingController(text: _money(c?.seller.expectedMinPrice));
    _contactTime =
        TextEditingController(text: c?.seller.preferredContactTime ?? '');

    _role = c?.role ?? widget.initialRole ?? ContactRole.buyer;
    _bedrooms = c?.buyer.bedrooms ?? 2;
    if (c != null && c.buyer.propertyTypes.isNotEmpty) {
      _types
        ..clear()
        ..addAll(c.buyer.propertyTypes);
    }
  }

  static String _money(double? v) =>
      (v == null || v <= 0) ? '' : v.toStringAsFixed(0);

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _email,
      _locality,
      _notes,
      _budgetMin,
      _budgetMax,
      _preferredLocations,
      _mustHaves,
      _askingPrice,
      _expectedMin,
      _contactTime,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _amount(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  List<String> _csv(TextEditingController c) => c.text
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();

    final buyer = BuyerProfile(
      budgetMin: _amount(_budgetMin),
      budgetMax: _amount(_budgetMax),
      preferredLocations: _csv(_preferredLocations),
      propertyTypes: _types.toList(),
      bedrooms: _bedrooms,
      mustHaves: _csv(_mustHaves),
    );
    final seller = SellerProfile(
      askingPrice: _amount(_askingPrice),
      expectedMinPrice: _amount(_expectedMin),
      preferredContactTime: _contactTime.text.trim(),
      propertyIds: widget.existing?.seller.propertyIds ?? [],
    );

    if (_isEditing) {
      final c = widget.existing!
        ..name = _name.text.trim()
        ..phone = _phone.text.trim()
        ..email = _email.text.trim()
        ..role = _role
        ..locality = _locality.text.trim()
        ..notes = _notes.text.trim()
        ..buyer = buyer
        ..seller = seller;
      state.updateContact(c);
      showToast(context, 'Contact updated', icon: Icons.check_circle_outline);
      Navigator.pop(context, c);
      return;
    }

    final created = Contact(
      id: state.nextId('ct'),
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      role: _role,
      locality: _locality.text.trim(),
      notes: _notes.text.trim(),
      buyer: buyer,
      seller: seller,
    );
    state.addContact(created);
    showToast(
      context,
      'Contact saved',
      icon: Icons.check_circle_outline,
    );
    Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final duplicates = _duplicates(state);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit contact' : 'New contact'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            if (duplicates.isNotEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.copy_all_outlined),
                  title: const Text('Possible duplicate'),
                  subtitle: Text(
                    '${duplicates.map((e) => e.name).take(2).join(', ')} '
                    'already has this number or name.',
                  ),
                ),
              ),
            FormSection(
              title: 'Person',
              children: [
                AppTextField(
                  controller: _name,
                  label: 'Full name',
                  prefixIcon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => requiredField(v, 'Name'),
                  autofocus: !_isEditing,
                ),
                AppTextField(
                  controller: _phone,
                  label: 'Phone number',
                  prefixIcon: Icons.call_outlined,
                  keyboardType: TextInputType.phone,
                  validator: phoneField,
                ),
                AppTextField(
                  controller: _email,
                  label: 'Email (optional)',
                  prefixIcon: Icons.alternate_email,
                  keyboardType: TextInputType.emailAddress,
                  textCapitalization: TextCapitalization.none,
                ),
                AppTextField(
                  controller: _locality,
                  label: 'Locality',
                  prefixIcon: Icons.place_outlined,
                ),
                ChipPicker<ContactRole>(
                  label: 'Role',
                  value: _role,
                  items: ContactRole.values,
                  labelBuilder: (e) => e.label,
                  onChanged: (e) => setState(() => _role = e),
                ),
              ],
            ),
            if (_role.isBuyer)
              FormSection(
                title: 'Buyer requirements',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: MoneyField(
                            controller: _budgetMin, label: 'Budget from'),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: MoneyField(
                            controller: _budgetMax, label: 'Budget to'),
                      ),
                    ],
                  ),
                  AppTextField(
                    controller: _preferredLocations,
                    label: 'Preferred locations',
                    hint: 'Comma separated — Baner, Aundh',
                    prefixIcon: Icons.place_outlined,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Property types',
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final t in PropertyType.values)
                              FilterChip(
                                label: Text(t.label),
                                selected: _types.contains(t),
                                onSelected: (on) => setState(() {
                                  if (on) {
                                    _types.add(t);
                                  } else if (_types.length > 1) {
                                    _types.remove(t);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ChipPicker<int>(
                    label: 'Bedrooms',
                    value: _bedrooms,
                    items: const [0, 1, 2, 3, 4, 5],
                    labelBuilder: (e) => e == 0 ? 'Any' : '$e BHK',
                    onChanged: (e) => setState(() => _bedrooms = e),
                  ),
                  AppTextField(
                    controller: _mustHaves,
                    label: 'Must-haves',
                    hint: 'Comma separated — covered parking, east facing',
                    maxLines: 2,
                  ),
                ],
              ),
            if (_role.isSeller)
              FormSection(
                title: 'Seller details',
                children: [
                  MoneyField(controller: _askingPrice, label: 'Asking price'),
                  MoneyField(
                    controller: _expectedMin,
                    label: 'Expected minimum price',
                    helper: 'Kept private — never shown to a buyer',
                  ),
                  AppTextField(
                    controller: _contactTime,
                    label: 'Preferred contact time',
                    hint: 'After 7 pm, weekends only',
                    prefixIcon: Icons.schedule_outlined,
                  ),
                ],
              ),
            FormSection(
              title: 'Notes',
              children: [
                AppTextField(controller: _notes, label: 'Notes', maxLines: 4),
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
            label: Text(_isEditing ? 'Save changes' : 'Save contact'),
          ),
        ),
      ),
    );
  }

  List<Contact> _duplicates(AppState state) {
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 10) return const [];
    return state.duplicateContactsFor(Contact(
      id: widget.existing?.id ?? '__new__',
      name: _name.text,
      phone: _phone.text,
    ));
  }
}
