import 'package:broker_demo_app/models/models.dart';
import 'package:broker_demo_app/services/matching_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const matcher = MatchingService();

  Property property({
    String id = 'pr-1',
    double price = 10000000,
    String locality = 'Baner',
    PropertyType type = PropertyType.apartment,
    int bedrooms = 3,
    PropertyStatus status = PropertyStatus.available,
    List<String> features = const ['covered parking', 'gym'],
  }) {
    return Property(
      id: id,
      title: 'Test property $id',
      price: price,
      locality: locality,
      city: 'Pune',
      type: type,
      bedrooms: bedrooms,
      status: status,
      features: features,
    );
  }

  Lead lead({
    double budgetMin = 9000000,
    double budgetMax = 12000000,
    String location = 'Baner',
    PropertyType type = PropertyType.apartment,
    int bedrooms = 3,
    String requirements = '',
  }) {
    return Lead(
      id: 'ld-1',
      name: 'Test Buyer',
      phone: '98210 34567',
      budgetMin: budgetMin,
      budgetMax: budgetMax,
      preferredLocation: location,
      propertyType: type,
      bedrooms: bedrooms,
      requirements: requirements,
    );
  }

  test('a property meeting every criterion scores 100%', () {
    final matches = matcher.matchForLead(lead(), [property()]);

    expect(matches, hasLength(1));
    expect(matches.single.percent, 100);
    expect(matches.single.isStrong, isTrue);
    expect(matches.single.misses, isEmpty);
  });

  test('explains which criteria do not fit', () {
    final matches = matcher.matchForLead(
      lead(),
      [property(locality: 'Kharadi', bedrooms: 2)],
    );

    final missLabels = matches.single.misses.map((c) => c.label).toList();
    expect(missLabels, contains('Location'));
    expect(missLabels, contains('Bedrooms'));
    expect(matches.single.isStrong, isFalse);
    expect(
      matches.single.misses.firstWhere((c) => c.label == 'Bedrooms').detail,
      contains('buyer wants'),
    );
  });

  test('allows a 10% stretch over the stated budget and says so', () {
    // 1.26 Cr against a 1.2 Cr ceiling: inside the tolerance.
    final matches = matcher.matchForLead(lead(), [property(price: 12600000)]);
    final budget =
        matches.single.criteria.firstWhere((c) => c.label == 'Budget');

    expect(budget.ok, isTrue);
    expect(budget.detail, contains('just over the stated ceiling'));
  });

  test('a property well over budget fails the budget criterion', () {
    final matches = matcher.matchForLead(lead(), [property(price: 20000000)]);
    final budget =
        matches.single.criteria.firstWhere((c) => c.label == 'Budget');

    expect(budget.ok, isFalse);
    expect(matches.single.isStrong, isFalse);
  });

  test('sold and rented inventory is never offered', () {
    final matches = matcher.matchForLead(lead(), [
      property(id: 'pr-sold', status: PropertyStatus.sold),
      property(id: 'pr-rented', status: PropertyStatus.rented),
      property(id: 'pr-hold', status: PropertyStatus.onHold),
    ]);

    expect(matches.map((m) => m.property.id), ['pr-hold']);
  });

  test('stronger matches are ranked first', () {
    final matches = matcher.matchForLead(lead(), [
      property(id: 'pr-weak', locality: 'Hadapsar', bedrooms: 1),
      property(id: 'pr-strong'),
      property(id: 'pr-middling', locality: 'Hadapsar'),
    ]);

    expect(matches.first.property.id, 'pr-strong');
    expect(matches.last.property.id, 'pr-weak');
  });

  test('free-text requirements are checked against the feature list', () {
    final matches = matcher.matchForLead(
      lead(requirements: 'covered parking, swimming pool'),
      [property()],
    );
    final labels = {for (final c in matches.single.criteria) c.label: c.ok};

    expect(labels['covered parking'], isTrue);
    expect(labels['swimming pool'], isFalse);
  });

  test('matches a contact profile as well as a lead', () {
    final contact = Contact(
      id: 'ct-1',
      name: 'Test Buyer',
      phone: '98210 34567',
      role: ContactRole.buyer,
      buyer: BuyerProfile(
        budgetMin: 9000000,
        budgetMax: 12000000,
        preferredLocations: ['Baner', 'Aundh'],
        propertyTypes: [PropertyType.apartment],
        bedrooms: 3,
      ),
    );

    final matches = matcher.matchForContact(contact, [property()]);
    expect(matches.single.isStrong, isTrue);
  });
}
