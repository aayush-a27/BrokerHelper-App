import '../models/models.dart';
import '../utils/formatters.dart';

/// One criterion in a match, with the reason spelled out. The report is
/// explicit that the broker must see *why* something matched and which
/// criteria do not fit (p. 4, 3.5).
class MatchCriterion {
  const MatchCriterion({
    required this.label,
    required this.ok,
    required this.detail,
    this.weight = 1,
  });

  final String label;
  final bool ok;
  final String detail;
  final double weight;
}

class PropertyMatch {
  PropertyMatch({required this.property, required this.criteria});

  final Property property;
  final List<MatchCriterion> criteria;

  double get score {
    final total = criteria.fold<double>(0, (s, c) => s + c.weight);
    if (total == 0) return 0;
    final hit =
        criteria.where((c) => c.ok).fold<double>(0, (s, c) => s + c.weight);
    return hit / total;
  }

  int get percent => (score * 100).round();

  List<MatchCriterion> get misses =>
      criteria.where((c) => !c.ok).toList(growable: false);

  bool get isStrong => score >= 0.75;
}

/// Rule-based buyer → property matching. Deliberately simple and explainable:
/// the broker stays in control and nothing here promises a perfect match.
class MatchingService {
  const MatchingService();

  /// Budget tolerance — a property slightly over budget is still worth
  /// showing, flagged as a stretch rather than hidden.
  static const double _overBudgetTolerance = 0.10;

  List<PropertyMatch> matchForLead(Lead lead, List<Property> properties) {
    final matches = properties
        .where((p) => p.status.isOfferable)
        .map((p) => PropertyMatch(
              property: p,
              criteria: _criteria(
                price: p.price,
                locality: '${p.locality} ${p.city} ${p.address}',
                type: p.type,
                bedrooms: p.bedrooms,
                features: p.features,
                budgetMin: lead.budgetMin,
                budgetMax: lead.budgetMax,
                wantedLocations: lead.preferredLocation.isEmpty
                    ? const <String>[]
                    : lead.preferredLocation.split(RegExp(r'[,/]')),
                wantedTypes: [lead.propertyType],
                wantedBedrooms: lead.bedrooms,
                mustHaves: _splitRequirements(lead.requirements),
              ),
            ))
        .where((m) => m.score > 0)
        .toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : a.property.price.compareTo(b.property.price);
      });
    return matches;
  }

  List<PropertyMatch> matchForContact(Contact contact, List<Property> properties) {
    final buyer = contact.buyer;
    return properties
        .where((p) => p.status.isOfferable)
        .map((p) => PropertyMatch(
              property: p,
              criteria: _criteria(
                price: p.price,
                locality: '${p.locality} ${p.city} ${p.address}',
                type: p.type,
                bedrooms: p.bedrooms,
                features: p.features,
                budgetMin: buyer.budgetMin,
                budgetMax: buyer.budgetMax,
                wantedLocations: buyer.preferredLocations,
                wantedTypes: buyer.propertyTypes,
                wantedBedrooms: buyer.bedrooms,
                mustHaves: buyer.mustHaves,
              ),
            ))
        .where((m) => m.score > 0)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  List<MatchCriterion> _criteria({
    required double price,
    required String locality,
    required PropertyType type,
    required int bedrooms,
    required List<String> features,
    required double budgetMin,
    required double budgetMax,
    required List<String> wantedLocations,
    required List<PropertyType> wantedTypes,
    required int wantedBedrooms,
    required List<String> mustHaves,
  }) {
    final criteria = <MatchCriterion>[];

    // Budget — weighted highest; a buyer rarely stretches far.
    if (budgetMax > 0 || budgetMin > 0) {
      final ceiling =
          budgetMax > 0 ? budgetMax * (1 + _overBudgetTolerance) : double.infinity;
      final floor = budgetMin > 0 ? budgetMin * 0.8 : 0.0;
      final withinBudget = price <= ceiling && price >= floor;
      final stretch = budgetMax > 0 && price > budgetMax && price <= ceiling;
      criteria.add(MatchCriterion(
        label: 'Budget',
        ok: withinBudget,
        weight: 3,
        detail: withinBudget
            ? (stretch
                ? '${formatMoney(price)} — just over the stated ceiling of ${formatMoney(budgetMax)}'
                : '${formatMoney(price)} fits ${formatBudgetRange(budgetMin, budgetMax)}')
            : '${formatMoney(price)} is outside ${formatBudgetRange(budgetMin, budgetMax)}',
      ));
    }

    // Location.
    // Compared case-insensitively, but shown back in the broker's own
    // capitalisation.
    final cleanWanted = wantedLocations
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (cleanWanted.isNotEmpty) {
      final haystack = locality.toLowerCase();
      final hit =
          cleanWanted.where((w) => haystack.contains(w.toLowerCase())).toList();
      criteria.add(MatchCriterion(
        label: 'Location',
        ok: hit.isNotEmpty,
        weight: 2,
        detail: hit.isNotEmpty
            ? 'In ${hit.first}'
            : 'Not in ${cleanWanted.join(', ')}',
      ));
    }

    // Property type.
    if (wantedTypes.isNotEmpty) {
      final ok = wantedTypes.contains(type);
      criteria.add(MatchCriterion(
        label: 'Property type',
        ok: ok,
        weight: 2,
        detail: ok
            ? type.label
            : '${type.label} — buyer asked for ${wantedTypes.map((e) => e.label).join(' or ')}',
      ));
    }

    // Bedrooms.
    if (wantedBedrooms > 0) {
      final ok = bedrooms >= wantedBedrooms;
      criteria.add(MatchCriterion(
        label: 'Bedrooms',
        ok: ok,
        weight: 1.5,
        detail: ok
            ? '${formatBedrooms(bedrooms)} (asked for ${formatBedrooms(wantedBedrooms)})'
            : 'Only ${formatBedrooms(bedrooms)}, buyer wants ${formatBedrooms(wantedBedrooms)}',
      ));
    }

    // Free-text must-haves checked against the property's feature list.
    final haystack = features.join(' ').toLowerCase();
    for (final want in mustHaves.take(4)) {
      final needle = want.trim().toLowerCase();
      if (needle.isEmpty) continue;
      final ok = haystack.contains(needle);
      criteria.add(MatchCriterion(
        label: want.trim(),
        ok: ok,
        weight: 0.5,
        detail: ok ? 'Listed in the property features' : 'Not listed — confirm with the owner',
      ));
    }

    return criteria;
  }

  /// Splits a free-text requirements note into candidate must-haves.
  static List<String> _splitRequirements(String text) => text
      .split(RegExp(r'[,.;\n]'))
      .map((e) => e.trim())
      .where((e) => e.length > 2 && e.length < 28)
      .toList();
}
