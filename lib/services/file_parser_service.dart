import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:sms/models/parse_result.dart';
import 'package:sms/services/phone_number_normalizer.dart';

class FileParserService {
  static const Set<String> supportedExtensions = {'xlsx', 'xls', 'csv', 'txt'};

  final PhoneNumberNormalizer _phoneNumberNormalizer = PhoneNumberNormalizer();

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
        throw UnsupportedError('Unsupported file format: .$extension');
    }
  }

  ParseResult _parseTxt(Uint8List bytes) {
    final content = utf8.decode(bytes, allowMalformed: true);
    final values = <String>[];
    for (final line in const LineSplitter().convert(content)) {
      values.addAll(line.split(RegExp(r'[,\t;]')));
    }
    return _parseValues(values);
  }

  ParseResult _parseCsv(Uint8List bytes) {
    final content = utf8.decode(bytes, allowMalformed: true);
    final rows = const CsvToListConverter(shouldParseNumbers: false).convert(content);
    final values = <dynamic>[];
    for (final row in rows) {
      for (final value in row) {
        values.add(value);
      }
    }
    return _parseValues(values);
  }

  ParseResult _parseExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final values = <dynamic>[];

    for (final table in excel.tables.values) {
      for (final row in table.rows) {
        for (final cell in row) {
          final value = _cellToValue(cell);
          if (value != null) {
            values.add(value);
          }
        }
      }
    }

    return _parseValues(values);
  }

  dynamic _cellToValue(dynamic cell) {
    if (cell == null) {
      return null;
    }

    final dynamic value = cell.value;
    if (value == null) {
      return null;
    }

    if (value is String || value is num || value is DateTime || value is bool) {
      return value;
    }

    try {
      final dynamic innerValue = value.value;
      if (innerValue != null) {
        return innerValue;
      }
    } catch (_) {
      return value;
    }

    return value;
  }

  ParseResult _parseValues(Iterable<dynamic> values) {
    final validNumbers = <String>{};
    var invalidCount = 0;

    for (final value in values) {
      final text = value?.toString() ?? '';
      if (text.trim().isEmpty) {
        continue;
      }

      final candidates = _extractCandidates(text);
      if (candidates.isEmpty) {
        final normalized = normalizeUzbekNumber(text);
        if (normalized == null) {
          invalidCount++;
        } else {
          validNumbers.add(normalized);
        }
        continue;
      }

      var hasValidInValue = false;
      for (final candidate in candidates) {
        final normalized = normalizeUzbekNumber(candidate);
        if (normalized != null) {
          validNumbers.add(normalized);
          hasValidInValue = true;
        }
      }

      if (!hasValidInValue) {
        invalidCount++;
      }
    }

    return ParseResult(validNumbers: validNumbers, invalidCount: invalidCount);
  }

  List<String> _extractCandidates(String text) {
    final matches = RegExp(r'(\+?\d[\d\s\u00A0\u2007\u202F\-\(\)]{7,}\d)').allMatches(text);
    final values = <String>{};
    for (final match in matches) {
      final value = match.group(0);
      if (value != null && value.trim().isNotEmpty) {
        values.add(value.trim());
      }
    }
    return values.toList();
  }

  String? normalizeUzbekNumber(String input) {
    return _phoneNumberNormalizer.normalize(input);
  }
}
