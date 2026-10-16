import 'package:broker_demo_app/models/models.dart';
import 'package:broker_demo_app/services/voice_service.dart';
import 'package:broker_demo_app/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone does the listening; this is the part that turns what it heard
/// into form fields.
void main() {
  final service = const VoiceParser();

  test('pulls name, phone, budget range, area and bedrooms out of a note', () {
    final capture = service.parse(
      'Add lead Rajesh Kumar phone 98210 34567 budget 80 lakh to 1 crore '
      'looking for 3 BHK apartment in Baner call him tomorrow evening',
    );

    expect(capture.name, 'Rajesh Kumar');
    expect(capture.phone, '98210 34567');
    expect(capture.budgetMin, 8000000);
    expect(capture.budgetMax, 10000000);
    expect(capture.location, 'Baner');
    expect(capture.bedrooms, 3);
    expect(capture.propertyType, PropertyType.apartment);
    expect(capture.isUsable, isTrue);
  });

  test('"tomorrow evening" becomes tomorrow at 6 pm', () {
    final capture = service.parse('Lead Asha Rao 98765 43210 call tomorrow evening');
    final tomorrow = DateUtilsX.startOfDay(DateTime.now())
        .add(const Duration(days: 1));

    expect(capture.followUpAt, isNotNull);
    expect(DateUtilsX.isSameDay(capture.followUpAt!, tomorrow), isTrue);
    expect(capture.followUpAt!.hour, 18);
  });

  test('"in 3 days" is resolved relative to today', () {
    final capture = service.parse('Walk in client Anita Rao 97020 55413 call back in 3 days');
    final expected =
        DateUtilsX.startOfDay(DateTime.now()).add(const Duration(days: 3));

    expect(DateUtilsX.isSameDay(capture.followUpAt!, expected), isTrue);
  });

  test('"up to 45 lakh" is read as a ceiling, not a range', () {
    final capture = service.parse('Client Anita Rao 97020 55413 budget up to 45 lakh');

    expect(capture.budgetMin, 0);
    expect(capture.budgetMax, 4500000);
  });

  test('recognises a villa and a crore figure', () {
    final capture = service.parse(
      'Seller enquiry Mohan Desai 98765 43210 selling 4 BHK villa in '
      'Koregaon Park asking 3.2 crore',
    );

    expect(capture.propertyType, PropertyType.villa);
    expect(capture.bedrooms, 4);
    expect(capture.location, 'Koregaon Park');
    expect(capture.budgetMax, closeTo(35200000, 1));
  });

  test('a note with nothing recognisable is marked unusable', () {
    final capture = service.parse('erm, something about a place somewhere');

    expect(capture.extracted, isEmpty);
    expect(capture.isUsable, isFalse);
    // The raw text is still kept so the broker can type the rest in.
    expect(capture.notes, isNotEmpty);
  });

  test('typical dictated notes parse into something usable', () {
    const notes = [
      'Add lead Rajesh Kumar phone 98210 34567 budget 80 lakh to 1 crore '
          'looking for 3 BHK apartment in Baner call him tomorrow evening',
      'New enquiry Priya Sharma 99304 11228 wants 2 BHK flat in Kharadi '
          'around 65 lakh needs covered parking follow up on Friday',
      'Seller enquiry Mohan Desai 98765 43210 selling 4 BHK villa in '
          'Koregaon Park asking 3.2 crore available next week',
      'Walk in client Anita Rao 97020 55413 budget up to 45 lakh 1 BHK '
          'apartment in Wakad call back in 3 days',
    ];
    for (final note in notes) {
      final capture = service.parse(note);
      expect(capture.isUsable, isTrue, reason: note);
      expect(capture.extracted.length, greaterThanOrEqualTo(3), reason: note);
    }
  });
}
