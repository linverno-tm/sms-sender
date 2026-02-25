import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:sms/models/parse_result.dart';

class FileParserService {
  static const Set<String> supportedExtensions = {'xlsx', 'xls', 'csv', 'txt'};

  Future<ParseResult> parse({
    required String extension,
    required Uint8List bytes,
  }) async {
    final normalizedExt = extension.toLowerCase();
    switch (normalizedExt) {
      case 'csv':
        return _parseCsv(bytes);
      case 'txt':
        return _parseTxt(bytes);
      case 'xlsx':
      case 'xls':
        return _parseExcel(bytes);
      default:
        throw UnsupportedError("Қўллаб-қувватланмайдиган формат: .$extension");
    }
  }

  ParseResult _parseTxt(Uint8List bytes) {
    final content = utf8.decode(bytes, allowMalformed: true);
    return _parseFromText(content);
  }

  ParseResult _parseCsv(Uint8List bytes) {
    final content = utf8.decode(bytes, allowMalformed: true);
    final rows = const CsvToListConverter(shouldParseNumbers: false).convert(content);
    final buffer = StringBuffer();
    for (final row in rows) {
      for (final value in row) {
        buffer.writeln('$value');
      }
    }
    return _parseFromText(buffer.toString());
  }

  ParseResult _parseExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final buffer = StringBuffer();

    for (final table in excel.tables.values) {
      for (final row in table.rows) {
        for (final cell in row) {
          final text = _cellToText(cell);
          if (text.isNotEmpty) {
            buffer.writeln(text);
          }
        }
      }
    }

    return _parseFromText(buffer.toString());
  }

  String _cellToText(dynamic cell) {
    if (cell == null) {
      return '';
    }
    final dynamic value = cell.value;
    if (value == null) {
      return '';
    }
    if (value is String) {
      return value;
    }
    if (value is num || value is DateTime || value is bool) {
      return value.toString();
    }

    try {
      final dynamic innerValue = value.value;
      if (innerValue != null) {
        return innerValue.toString();
      }
    } catch (_) {
      return value.toString();
    }

    return value.toString();
  }

  ParseResult _parseFromText(String text) {
    final candidates = _extractCandidates(text);
    final validNumbers = <String>{};
    var invalidCount = 0;

    for (final raw in candidates) {
      final normalized = normalizeUzbekNumber(raw);
      if (normalized == null) {
        invalidCount++;
      } else {
        validNumbers.add(normalized);
      }
    }

    return ParseResult(validNumbers: validNumbers, invalidCount: invalidCount);
  }

  Set<String> _extractCandidates(String text) {
    final matches = RegExp(r'(\+?\d[\d\s\-\(\)]{7,}\d)').allMatches(text);
    final values = <String>{};
    for (final match in matches) {
      final value = match.group(0);
      if (value != null && value.trim().isNotEmpty) {
        values.add(value.trim());
      }
    }
    return values;
  }

  String? normalizeUzbekNumber(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');

    if (digits.length == 12 && digits.startsWith('998')) {
      return digits;
    }

    if (digits.length == 10 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    if (digits.length == 9) {
      digits = '998$digits';
    }

    if (RegExp(r'^998\d{9}$').hasMatch(digits)) {
      return digits;
    }

    return null;
  }
}
