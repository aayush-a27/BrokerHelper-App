import 'dart:convert';

import 'package:broker_demo_app/services/export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = ExportService();

  const data = ExportDataset(
    name: 'leads',
    title: 'Leads',
    subtitle: '2 records',
    headers: ['Name', 'Notes', 'Budget'],
    rows: [
      ['Rohit Agarwal', 'Wants parking, gym', '₹90 L – ₹1.2 Cr'],
      ['Meera "MJ" Joshi', 'Line one\nline two', '₹70 L'],
    ],
  );

  group('CSV', () {
    test('writes a header row and one record per row', () {
      final csv = service.buildCsv(data);
      final lines = const LineSplitter().convert(csv);

      expect(lines.first, 'Name,Notes,Budget');
      // The second record holds a newline inside a quoted cell, so it spans
      // two physical lines — four in total, which is correct CSV.
      expect(lines, hasLength(4));
      expect(lines[1], startsWith('Rohit Agarwal,'));
    });

    test('quotes cells containing commas, quotes or newlines', () {
      final csv = service.buildCsv(data);

      expect(csv, contains('"Wants parking, gym"'));
      expect(csv, contains('"Meera ""MJ"" Joshi"'));
      expect(csv, contains('"Line one\nline two"'));
    });
  });

  group('PDF', () {
    test('produces a file with a PDF header and trailer', () {
      final bytes = service.buildPdf(data);
      final text = latin1.decode(bytes);

      expect(text.startsWith('%PDF-1.4'), isTrue);
      expect(text.trimRight().endsWith('%%EOF'), isTrue);
      expect(text, contains('/Type /Catalog'));
      expect(text, contains('startxref'));
    });

    test('the xref offsets point at the real object positions', () {
      final bytes = service.buildPdf(data);
      final text = latin1.decode(bytes);

      // Pull the offsets out of the cross-reference table and check each one
      // lands on the "N 0 obj" marker it claims to. (Not lastIndexOf('xref') —
      // that would find the one inside "startxref".)
      final xrefStart = text.indexOf('\nxref\n');
      final entries = RegExp(r'^(\d{10}) 00000 n $', multiLine: true)
          .allMatches(text.substring(xrefStart))
          .map((m) => int.parse(m.group(1)!))
          .toList();

      expect(entries, isNotEmpty);
      for (var i = 0; i < entries.length; i++) {
        expect(
          text.startsWith('${i + 1} 0 obj', entries[i]),
          isTrue,
          reason: 'object ${i + 1} is not where the xref table says it is',
        );
      }
    });

    test('folds the rupee sign and dashes down to Latin-1', () {
      final bytes = service.buildPdf(data);
      final text = latin1.decode(bytes);

      expect(text, contains('Rs.70 L'));
      expect(text, contains('Rs.90 L - Rs.1'));
      expect(text.contains('₹'), isFalse);
      expect(text.contains('–'), isFalse);
    });

    test('truncates an over-wide cell with a tilde rather than wrapping', () {
      final text = latin1.decode(service.buildPdf(data));

      // "Rs.90 L - Rs.1.2 Cr" does not fit the Budget column.
      expect(text, contains('Rs.90 L - Rs.1~'));
    });

    test('escapes parentheses so the content stream stays valid', () {
      const tricky = ExportDataset(
        name: 'x',
        title: 'Title (draft)',
        headers: ['A'],
        rows: [
          [r'value (with parens) and a \ backslash'],
        ],
      );
      final text = latin1.decode(service.buildPdf(tricky));

      expect(text, contains(r'Title \(draft\)'));
      expect(text, contains(r'\(with parens\)'));
    });

    test('splits a long table over several pages', () {
      final big = ExportDataset(
        name: 'big',
        title: 'Many rows',
        headers: const ['Name'],
        rows: [for (var i = 0; i < 200; i++) ['Row $i']],
      );
      final text = latin1.decode(service.buildPdf(big));

      expect(text, contains('/Count 4'));
      expect(text, contains('Page 1 of 4'));
    });

    test('an empty data set still produces a valid one-page PDF', () {
      const empty = ExportDataset(
        name: 'empty',
        title: 'Nothing',
        headers: ['A', 'B'],
        rows: [],
      );
      final text = latin1.decode(service.buildPdf(empty));

      expect(text.startsWith('%PDF-1.4'), isTrue);
      expect(text, contains('/Count 1'));
      expect(text, contains('no records'));
    });
  });
}
