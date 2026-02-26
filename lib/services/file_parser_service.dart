import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';
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
        return _parseExcel(bytes);
      case 'xls':
        throw const FormatException(
          '`.xls` formati qo\'llab-quvvatlanmaydi. Faylni `.xlsx` qilib qayta saqlang.',
        );
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
    if (!_looksLikeXlsx(bytes)) {
      throw const FormatException(
        'Excel fayli buzilgan yoki `.xlsx` formatda emas.',
      );
    }

    try {
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
    } catch (_) {
      try {
        final fallbackValues = _extractXlsxValuesViaZip(bytes);
        return _parseValues(fallbackValues);
      } catch (_) {
        throw const FormatException(
          'Excel faylini ochib bo\'lmadi. Fayl parol bilan himoyalangan yoki nosoz bo\'lishi mumkin.',
        );
      }
    }
  }

  bool _looksLikeXlsx(Uint8List bytes) {
    if (bytes.length < 4) {
      return false;
    }
    return bytes[0] == 0x50 && bytes[1] == 0x4B;
  }

  List<String> _extractXlsxValuesViaZip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final byName = <String, ArchiveFile>{};
    for (final file in archive.files) {
      byName[file.name] = file;
    }

    if (!byName.containsKey('xl/workbook.xml')) {
      throw const FormatException('Workbook topilmadi.');
    }

    final sharedStrings = _readSharedStrings(byName['xl/sharedStrings.xml']);
    final worksheetPaths = _resolveWorksheetPaths(byName);
    if (worksheetPaths.isEmpty) {
      throw const FormatException('Excel sheet topilmadi.');
    }

    final values = <String>[];
    for (final sheetPath in worksheetPaths) {
      final file = byName[sheetPath];
      if (file == null) {
        continue;
      }
      values.addAll(_readWorksheetValues(file, sharedStrings));
    }
    return values;
  }

  List<String> _readSharedStrings(ArchiveFile? sharedStringsFile) {
    if (sharedStringsFile == null) {
      return const <String>[];
    }
    final xml = XmlDocument.parse(_archiveFileAsString(sharedStringsFile));
    final result = <String>[];
    for (final si in _findElementsByLocalName(xml.rootElement, 'si')) {
      final text = _findElementsByLocalName(si, 't').map((node) => node.innerText).join();
      result.add(text);
    }
    return result;
  }

  List<String> _resolveWorksheetPaths(Map<String, ArchiveFile> byName) {
    final workbook = XmlDocument.parse(_archiveFileAsString(byName['xl/workbook.xml']!));

    final relationshipsFile = byName['xl/_rels/workbook.xml.rels'];
    final relationshipById = <String, String>{};
    if (relationshipsFile != null) {
      final relsDoc = XmlDocument.parse(_archiveFileAsString(relationshipsFile));
      for (final rel in _findElementsByLocalName(relsDoc.rootElement, 'Relationship')) {
        final id = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (id != null && target != null && target.isNotEmpty) {
          relationshipById[id] = target;
        }
      }
    }

    final paths = <String>[];
    for (final sheet in _findElementsByLocalName(workbook.rootElement, 'sheet')) {
      final relId =
          sheet.getAttribute('id', namespace: 'http://schemas.openxmlformats.org/officeDocument/2006/relationships') ??
          sheet.getAttribute('r:id');
      if (relId == null) {
        continue;
      }
      final target = relationshipById[relId];
      if (target == null || target.isEmpty) {
        continue;
      }
      final normalized = target.startsWith('/') ? target.substring(1) : target;
      if (normalized.startsWith('xl/')) {
        paths.add(normalized);
      } else {
        paths.add('xl/$normalized');
      }
    }

    if (paths.isNotEmpty) {
      return paths;
    }

    final fallback = byName.keys
        .where((path) => path.startsWith('xl/worksheets/sheet') && path.endsWith('.xml'))
        .toList()
      ..sort();
    return fallback;
  }

  List<String> _readWorksheetValues(ArchiveFile sheetFile, List<String> sharedStrings) {
    final sheet = XmlDocument.parse(_archiveFileAsString(sheetFile));
    final values = <String>[];

    for (final cell in _findElementsByLocalName(sheet.rootElement, 'c')) {
      final type = cell.getAttribute('t');
      String? value;

      if (type == 'inlineStr') {
        final isNode = _directChildByLocalName(cell, 'is');
        if (isNode != null) {
          value = _findElementsByLocalName(isNode, 't').map((node) => node.innerText).join();
        }
      } else {
        final raw = _directChildByLocalName(cell, 'v')?.innerText;
        if (raw != null && raw.trim().isNotEmpty) {
          if (type == 's') {
            final index = int.tryParse(raw.trim());
            if (index != null && index >= 0 && index < sharedStrings.length) {
              value = sharedStrings[index];
            } else {
              value = raw;
            }
          } else {
            value = raw;
          }
        }
      }

      if (value != null && value.trim().isNotEmpty) {
        values.add(value.trim());
      }
    }
    return values;
  }

  String _archiveFileAsString(ArchiveFile file) {
    final content = file.content;
    if (content is Uint8List) {
      return utf8.decode(content, allowMalformed: true);
    }
    if (content is List<int>) {
      return utf8.decode(content, allowMalformed: true);
    }
    if (content is String) {
      return content;
    }
    return content.toString();
  }

  Iterable<XmlElement> _findElementsByLocalName(XmlElement root, String localName) {
    return root.descendants.whereType<XmlElement>().where((e) => e.name.local == localName);
  }

  XmlElement? _directChildByLocalName(XmlElement root, String localName) {
    for (final child in root.children.whereType<XmlElement>()) {
      if (child.name.local == localName) {
        return child;
      }
    }
    return null;
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
