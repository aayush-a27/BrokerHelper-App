import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// A table ready to be written out.
class ExportDataset {
  const ExportDataset({
    required this.name,
    required this.title,
    required this.headers,
    required this.rows,
    this.subtitle = '',
  });

  /// File-name stem, e.g. `leads`.
  final String name;
  final String title;
  final String subtitle;
  final List<String> headers;
  final List<List<String>> rows;

  bool get isEmpty => rows.isEmpty;
}

enum ExportStatus { shared, dismissed, failed }

class ExportOutcome {
  const ExportOutcome(this.status, this.message);

  final ExportStatus status;
  final String message;
}

/// Builds CSV and PDF files in memory and hands them to the platform share
/// sheet. The PDF is written by hand rather than pulled from a package — it
/// keeps the app dependency-light and the output is a real, openable file.
class ExportService {
  const ExportService();

  // --- CSV -----------------------------------------------------------------

  String buildCsv(ExportDataset data) {
    final buffer = StringBuffer();
    buffer.writeln(data.headers.map(_csvCell).join(','));
    for (final row in data.rows) {
      buffer.writeln(row.map(_csvCell).join(','));
    }
    return buffer.toString();
  }

  static String _csvCell(String value) {
    final needsQuotes = value.contains(RegExp('[",\n\r]'));
    final escaped = value.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }

  Future<ExportOutcome> shareCsv(ExportDataset data) {
    // A UTF-8 BOM so Excel opens the rupee sign correctly.
    final bytes = Uint8List.fromList(
      <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(buildCsv(data))],
    );
    return _share(
      bytes: bytes,
      fileName: '${data.name}_${_stamp()}.csv',
      mimeType: 'text/csv',
      subject: data.title,
    );
  }

  // --- PDF -----------------------------------------------------------------

  Future<ExportOutcome> sharePdf(ExportDataset data) => _share(
        bytes: buildPdf(data),
        fileName: '${data.name}_${_stamp()}.pdf',
        mimeType: 'application/pdf',
        subject: data.title,
      );

  /// A minimal single-font PDF. Rows are laid out with Courier so the columns
  /// line up without a layout engine.
  Uint8List buildPdf(ExportDataset data) {
    const pageWidth = 595;
    const pageHeight = 842;
    const margin = 40;
    const bodySize = 8.0;
    const leading = 11.0;
    const charWidth = bodySize * 0.6; // Courier is monospaced at 0.6 em.
    final maxChars = ((pageWidth - margin * 2) / charWidth).floor();
    const linesPerPage = 64;

    final widths = _columnWidths(data, maxChars);
    final headerLine = _padRow(data.headers, widths);
    final ruleLine = widths.map((w) => '-' * w).join('  ');

    final bodyLines = <String>[
      for (final row in data.rows) _padRow(row, widths),
    ];

    // Split into pages, repeating the header on each.
    final pages = <List<String>>[];
    if (bodyLines.isEmpty) {
      pages.add(<String>['(no records)']);
    } else {
      for (var i = 0; i < bodyLines.length; i += linesPerPage) {
        pages.add(bodyLines.sublist(
            i, (i + linesPerPage).clamp(0, bodyLines.length)));
      }
    }

    final objects = <String>[];

    // 1 catalog, 2 pages, 3 Helvetica-Bold, 4 Courier — then page/content
    // pairs from object 5 onward.
    final pageObjIds = <int>[];
    final contentStreams = <String>[];
    for (var p = 0; p < pages.length; p++) {
      pageObjIds.add(5 + p * 2);
      contentStreams.add(_contentStream(
        title: data.title,
        subtitle: data.subtitle,
        pageLabel: 'Page ${p + 1} of ${pages.length}',
        headerLine: headerLine,
        ruleLine: ruleLine,
        lines: pages[p],
        margin: margin.toDouble(),
        pageHeight: pageHeight.toDouble(),
        bodySize: bodySize,
        leading: leading,
      ));
    }

    objects.add('<< /Type /Catalog /Pages 2 0 R >>');
    objects.add('<< /Type /Pages /Kids [${pageObjIds.map((id) => '$id 0 R').join(' ')}] '
        '/Count ${pageObjIds.length} >>');
    objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>');
    objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>');

    for (var p = 0; p < pages.length; p++) {
      final contentId = 5 + p * 2 + 1;
      objects.add('<< /Type /Page /Parent 2 0 R '
          '/MediaBox [0 0 $pageWidth $pageHeight] '
          '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> '
          '/Contents $contentId 0 R >>');
      final stream = contentStreams[p];
      objects.add('<< /Length ${latin1.encode(stream).length} >>\nstream\n'
          '$stream\nendstream');
    }

    // Assemble with a cross-reference table of byte offsets.
    final out = BytesBuilder();
    void write(String s) => out.add(latin1.encode(s));

    write('%PDF-1.4\n');
    final offsets = <int>[];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(out.length);
      write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }
    final xrefOffset = out.length;
    write('xref\n0 ${objects.length + 1}\n');
    write('0000000000 65535 f \n');
    for (final offset in offsets) {
      write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
        'startxref\n$xrefOffset\n%%EOF\n');

    return out.toBytes();
  }

  String _contentStream({
    required String title,
    required String subtitle,
    required String pageLabel,
    required String headerLine,
    required String ruleLine,
    required List<String> lines,
    required double margin,
    required double pageHeight,
    required double bodySize,
    required double leading,
  }) {
    final b = StringBuffer();
    var y = pageHeight - margin - 10;

    b.writeln('BT /F1 15 Tf $margin $y Td (${_pdfEscape(title)}) Tj ET');
    y -= 16;
    if (subtitle.isNotEmpty) {
      b.writeln('BT /F2 8 Tf $margin $y Td (${_pdfEscape(subtitle)}) Tj ET');
      y -= 12;
    }
    b.writeln('BT /F2 8 Tf $margin $y Td '
        '(${_pdfEscape('Broker Diary - generated ${_stamp()}. $pageLabel')}) Tj ET');
    y -= 18;

    b.writeln('BT /F1 $bodySize Tf $margin $y Td (${_pdfEscape(headerLine)}) Tj ET');
    y -= leading;
    b.writeln('BT /F2 $bodySize Tf $margin $y Td (${_pdfEscape(ruleLine)}) Tj ET');
    y -= leading;

    for (final line in lines) {
      b.writeln('BT /F2 $bodySize Tf $margin $y Td (${_pdfEscape(line)}) Tj ET');
      y -= leading;
      if (y < margin) break;
    }
    return b.toString();
  }

  /// Distributes the available character budget across columns, giving each
  /// one at least its header width where possible.
  List<int> _columnWidths(ExportDataset data, int maxChars) {
    final count = data.headers.length;
    if (count == 0) return const <int>[];
    final natural = List<int>.generate(count, (i) {
      var w = data.headers[i].length;
      for (final row in data.rows) {
        if (i < row.length && row[i].length > w) w = row[i].length;
      }
      return w.clamp(4, 40);
    });
    final gaps = (count - 1) * 2;
    var total = natural.fold<int>(0, (s, w) => s + w) + gaps;
    // Shrink the widest column until everything fits on one line.
    while (total > maxChars) {
      var widest = 0;
      for (var i = 1; i < count; i++) {
        if (natural[i] > natural[widest]) widest = i;
      }
      if (natural[widest] <= 5) break;
      natural[widest]--;
      total--;
    }
    return natural;
  }

  String _padRow(List<String> cells, List<int> widths) {
    final parts = <String>[];
    for (var i = 0; i < widths.length; i++) {
      final raw = i < cells.length ? _pdfSafe(cells[i]) : '';
      final w = widths[i];
      final text = raw.length > w
          ? (w > 1 ? '${raw.substring(0, w - 1)}~' : raw.substring(0, w))
          : raw.padRight(w);
      parts.add(text);
    }
    return parts.join('  ');
  }

  /// Helvetica/Courier with WinAnsiEncoding has no rupee sign or en dash, so
  /// we fold the few non-Latin-1 characters the app uses down to ASCII.
  static String _pdfSafe(String input) => input
      .replaceAll('₹', 'Rs.')
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('·', '|')
      .replaceAll('’', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('\n', ' ')
      .replaceAll(RegExp(r'[^\x20-\x7E]'), '?');

  static String _pdfEscape(String input) => _pdfSafe(input)
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)');

  // --- sharing -------------------------------------------------------------

  Future<ExportOutcome> _share({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String subject,
  }) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
          fileNameOverrides: [fileName],
          subject: subject,
          text: '$subject — exported from Broker Diary.',
        ),
      );
      return switch (result.status) {
        ShareResultStatus.success =>
          ExportOutcome(ExportStatus.shared, 'Shared $fileName'),
        ShareResultStatus.dismissed =>
          ExportOutcome(ExportStatus.dismissed, 'Export cancelled'),
        ShareResultStatus.unavailable => ExportOutcome(ExportStatus.shared,
            'Generated $fileName (the share sheet is not available here)'),
      };
    } catch (e) {
      return ExportOutcome(
          ExportStatus.failed, 'Could not export $fileName: $e');
    }
  }

  static String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}';
  }
}
