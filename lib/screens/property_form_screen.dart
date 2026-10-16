import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/attachment_service.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

class PropertyFormScreen extends StatefulWidget {
  const PropertyFormScreen({super.key, this.existing});

  final Property? existing;

  @override
  State<PropertyFormScreen> createState() => _PropertyFormScreenState();
}

class _PropertyFormScreenState extends State<PropertyFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _address;
  late final TextEditingController _locality;
  late final TextEditingController _city;
  late final TextEditingController _area;
  late final TextEditingController _price;
  late final TextEditingController _source;
  late final TextEditingController _features;
  late final TextEditingController _visitInstructions;
  late final TextEditingController _notes;

  PropertyType _type = PropertyType.apartment;
  ListingType _listing = ListingType.sale;
  PropertyStatus _status = PropertyStatus.available;
  int _bedrooms = 2;
  int _bathrooms = 2;
  String? _ownerContactId;
  String? _photo;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _title = TextEditingController(text: p?.title ?? '');
    _address = TextEditingController(text: p?.address ?? '');
    _locality = TextEditingController(text: p?.locality ?? '');
    _city = TextEditingController(text: p?.city ?? 'Pune');
    _area = TextEditingController(
        text: (p?.areaSqft ?? 0) <= 0 ? '' : '${p!.areaSqft}');
    _price = TextEditingController(
        text: (p?.price ?? 0) <= 0 ? '' : p!.price.toStringAsFixed(0));
    _source = TextEditingController(text: p?.source ?? '');
    _features = TextEditingController(text: p?.features.join(', ') ?? '');
    _visitInstructions =
        TextEditingController(text: p?.visitInstructions ?? '');
    _notes = TextEditingController(text: p?.notes ?? '');

    _type = p?.type ?? PropertyType.apartment;
    _listing = p?.listing ?? ListingType.sale;
    _status = p?.status ?? PropertyStatus.available;
    _bedrooms = p?.bedrooms ?? 2;
    _bathrooms = p?.bathrooms ?? 2;
    _ownerContactId = p?.ownerContactId;
    _photo = p?.photo;
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _address,
      _locality,
      _city,
      _area,
      _price,
      _source,
      _features,
      _visitInstructions,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    final features = _features.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (_isEditing) {
      final p = widget.existing!
        ..title = _title.text.trim()
        ..type = _type
        ..listing = _listing
        ..status = _status
        ..address = _address.text.trim()
        ..locality = _locality.text.trim()
        ..city = _city.text.trim()
        ..areaSqft = int.tryParse(_area.text.trim()) ?? 0
        ..bedrooms = _bedrooms
        ..bathrooms = _bathrooms
        ..price = double.tryParse(_price.text.trim()) ?? 0
        ..ownerContactId = _ownerContactId
        ..source = _source.text.trim()
        ..features = features
        ..visitInstructions = _visitInstructions.text.trim()
        ..notes = _notes.text.trim()
        ..photo = _photo;
      state.updateProperty(p);
      showToast(context, 'Property updated', icon: Icons.check_circle_outline);
      Navigator.pop(context, p);
      return;
    }

    final created = Property(
      id: state.nextId('pr'),
      title: _title.text.trim(),
      type: _type,
      listing: _listing,
      status: _status,
      address: _address.text.trim(),
      locality: _locality.text.trim(),
      city: _city.text.trim(),
      areaSqft: int.tryParse(_area.text.trim()) ?? 0,
      bedrooms: _bedrooms,
      bathrooms: _bathrooms,
      price: double.tryParse(_price.text.trim()) ?? 0,
      photo: _photo,
      ownerContactId: _ownerContactId,
      source: _source.text.trim(),
      features: features,
      visitInstructions: _visitInstructions.text.trim(),
      notes: _notes.text.trim(),
    );
    state.addProperty(created);

    // Keep the seller's linked-property list in step.
    final owner = state.contact(_ownerContactId);
    if (owner != null && !owner.seller.propertyIds.contains(created.id)) {
      owner.seller.propertyIds.add(created.id);
    }

    showToast(
      context,
      'Property saved',
      icon: Icons.check_circle_outline,
    );
    Navigator.pop(context, created);
  }

  Future<void> _pickPhoto({required bool camera}) async {
    try {
      final picked =
          await AttachmentService.instance.pickPhoto(camera: camera);
      if (picked != null && mounted) setState(() => _photo = picked.file);
    } catch (e) {
      if (mounted) showToast(context, 'Could not add the photo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit property' : 'New property'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            FormSection(
              title: 'The property',
              children: [
                AppTextField(
                  controller: _title,
                  label: 'Title',
                  hint: 'Skyline Residences, Tower B',
                  prefixIcon: Icons.home_work_outlined,
                  validator: (v) => requiredField(v, 'Title'),
                  autofocus: !_isEditing,
                ),
                AppDropdown<PropertyType>(
                  label: 'Type',
                  value: _type,
                  items: PropertyType.values,
                  labelBuilder: (e) => e.label,
                  onChanged: (e) => setState(() => _type = e ?? _type),
                ),
                ChipPicker<ListingType>(
                  label: 'Listing',
                  value: _listing,
                  items: ListingType.values,
                  labelBuilder: (e) => e.label,
                  onChanged: (e) => setState(() => _listing = e),
                ),
                AppDropdown<PropertyStatus>(
                  label: 'Availability',
                  value: _status,
                  items: PropertyStatus.values,
                  icon: Icons.verified_outlined,
                  labelBuilder: (e) => e.label,
                  onChanged: (e) => setState(() => _status = e ?? _status),
                ),
              ],
            ),
            FormSection(
              title: 'Where',
              children: [
                AppTextField(
                  controller: _address,
                  label: 'Address',
                  prefixIcon: Icons.location_on_outlined,
                  maxLines: 2,
                ),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                          controller: _locality, label: 'Locality'),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: AppTextField(controller: _city, label: 'City'),
                    ),
                  ],
                ),
              ],
            ),
            FormSection(
              title: 'Size and price',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _area,
                        label: 'Area (sq.ft)',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: MoneyField(
                        controller: _price,
                        label: _listing == ListingType.rent
                            ? 'Monthly rent'
                            : 'Price',
                      ),
                    ),
                  ],
                ),
                ChipPicker<int>(
                  label: 'Bedrooms',
                  value: _bedrooms,
                  items: const [0, 1, 2, 3, 4, 5],
                  labelBuilder: (e) => e == 0 ? 'N/A' : '$e BHK',
                  onChanged: (e) => setState(() => _bedrooms = e),
                ),
                ChipPicker<int>(
                  label: 'Bathrooms',
                  value: _bathrooms,
                  items: const [0, 1, 2, 3, 4, 5],
                  labelBuilder: (e) => '$e',
                  onChanged: (e) => setState(() => _bathrooms = e),
                ),
              ],
            ),
            FormSection(
              title: 'Links and photo',
              children: [
                PickerField(
                  label: 'Owner / seller',
                  icon: Icons.person_outline,
                  value: state.contact(_ownerContactId)?.name,
                  onClear: () => setState(() => _ownerContactId = null),
                  onTap: () async {
                    final picked = await showRecordPicker<Contact>(
                      context: context,
                      title: 'Link an owner',
                      items: state.contacts
                          .where((c) => c.role.isSeller)
                          .toList(),
                      titleBuilder: (c) => c.name,
                      subtitleBuilder: (c) => '${c.phone} · ${c.locality}',
                    );
                    if (picked != null) {
                      setState(() => _ownerContactId = picked.id);
                    }
                  },
                ),
                const SizedBox(height: 8),
                Text('Cover photo',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    PropertyThumb(photo: _photo, icon: _type.icon, size: 84),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _pickPhoto(camera: true),
                            icon: const Icon(Icons.photo_camera_outlined, size: 18),
                            label: const Text('Camera'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _pickPhoto(camera: false),
                            icon: const Icon(Icons.photo_library_outlined, size: 18),
                            label: const Text('Gallery'),
                          ),
                          if (_photo != null)
                            TextButton(
                              onPressed: () => setState(() => _photo = null),
                              child: const Text('Remove'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            FormSection(
              title: 'Details',
              children: [
                AppTextField(
                  controller: _source,
                  label: 'Source',
                  hint: 'Owner direct, referral, portal listing',
                ),
                AppTextField(
                  controller: _features,
                  label: 'Key features',
                  hint: 'Comma separated — covered parking, gym, east facing',
                  maxLines: 2,
                ),
                AppTextField(
                  controller: _visitInstructions,
                  label: 'Visit instructions',
                  hint: 'Who holds the keys, when visits are possible',
                  maxLines: 2,
                ),
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
            label: Text(_isEditing ? 'Save changes' : 'Save property'),
          ),
        ),
      ),
    );
  }
}
