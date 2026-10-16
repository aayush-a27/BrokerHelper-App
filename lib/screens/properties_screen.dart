import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/export_datasets.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import 'property_detail_screen.dart';
import 'property_form_screen.dart';

/// Properties — inventory, availability, photos and owner details
/// (report p. 6).
class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  final _search = TextEditingController();
  PropertyStatus? _status;
  PropertyType? _type;
  ListingType? _listing;
  bool _grid = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Property> _filtered(AppState state) {
    final q = _search.text.trim().toLowerCase();
    return state.properties.where((p) {
      if (_status != null && p.status != _status) return false;
      if (_type != null && p.type != _type) return false;
      if (_listing != null && p.listing != _listing) return false;
      if (q.isEmpty) return true;
      return p.title.toLowerCase().contains(q) ||
          p.address.toLowerCase().contains(q) ||
          p.locality.toLowerCase().contains(q) ||
          p.city.toLowerCase().contains(q) ||
          p.features.any((f) => f.toLowerCase().contains(q));
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final properties = _filtered(state);
    final byStatus = state.propertiesByStatus;

    return MainScaffold(
      title: 'Properties',
      subtitle: '${pluralise(properties.length, 'property', 'properties')} shown · '
          '${byStatus[PropertyStatus.available] ?? 0} available',
      embedded: widget.embedded,
      exportBuilder: () => ExportDatasets.properties(state, properties),
      actions: [
        IconButton(
          tooltip: _grid ? 'List view' : 'Grid view',
          icon: Icon(_grid ? Icons.view_list_outlined : Icons.grid_view),
          onPressed: () => setState(() => _grid = !_grid),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const PropertyFormScreen()),
        ),
        icon: const Icon(Icons.add_home_outlined),
        label: const Text('Property'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search title, address or feature',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final listing in ListingType.values) ...[
                  FilterChip(
                    label: Text(listing.label),
                    selected: _listing == listing,
                    onSelected: (v) =>
                        setState(() => _listing = v ? listing : null),
                  ),
                  const SizedBox(width: 8),
                ],
                for (final status in PropertyStatus.values) ...[
                  FilterChip(
                    label: Text('${status.label} ${byStatus[status] ?? 0}'),
                    selected: _status == status,
                    selectedColor: status.color.withValues(alpha: 0.18),
                    onSelected: (v) =>
                        setState(() => _status = v ? status : null),
                  ),
                  const SizedBox(width: 8),
                ],
                for (final type in PropertyType.values) ...[
                  FilterChip(
                    label: Text(type.label),
                    avatar: Icon(type.icon, size: 16),
                    selected: _type == type,
                    onSelected: (v) => setState(() => _type = v ? type : null),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: properties.isEmpty
                ? EmptyState(
                    icon: Icons.home_outlined,
                    title: 'No properties match',
                    message:
                        'Clear the filters, or add a unit with the button below.',
                    action: OutlinedButton(
                      onPressed: () => setState(() {
                        _search.clear();
                        _status = null;
                        _type = null;
                        _listing = null;
                      }),
                      child: const Text('Clear filters'),
                    ),
                  )
                : _grid
                    ? GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 320,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.82,
                        ),
                        itemCount: properties.length,
                        itemBuilder: (context, i) =>
                            _PropertyGridCard(property: properties[i]),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: properties.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: PropertyCard(property: properties[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class PropertyCard extends StatelessWidget {
  const PropertyCard({super.key, required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final owner = state.contact(property.ownerContactId);

    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PropertyDetailScreen(propertyId: property.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PropertyThumb(
                photo: property.photo,
                icon: property.type.icon,
                size: 76,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            property.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        StatusChip(
                          label: property.status.label,
                          color: property.status.color,
                          dense: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      property.shortAddress,
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatMoney(property.price)}'
                      '${property.listing == ListingType.rent ? ' / month' : ''}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (property.bedrooms > 0)
                          formatBedrooms(property.bedrooms),
                        if (property.areaSqft > 0)
                          formatArea(property.areaSqft),
                        property.type.label,
                      ].join(' · '),
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 13, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            owner?.name ?? 'No owner linked',
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ),
                        if (property.interestedContactIds.isNotEmpty) ...[
                          Icon(Icons.favorite_border,
                              size: 13, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text(
                            '${property.interestedContactIds.length}',
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PropertyGridCard extends StatelessWidget {
  const _PropertyGridCard({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PropertyDetailScreen(propertyId: property.id),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PropertyThumb(
                    photo: property.photo,
                    icon: property.type.icon,
                    size: double.infinity,
                    radius: 0,
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: StatusChip(
                      label: property.status.label,
                      color: property.status.color,
                      dense: true,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    property.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    property.shortAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatMoney(property.price),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
