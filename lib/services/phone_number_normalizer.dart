class PhoneNumberNormalizer {
  static final RegExp _validUzbekPhone = RegExp(r'^998\d{9}$');
  static final RegExp _specialSpaces = RegExp(r'[\u00A0\u2007\u202F]');
  static final RegExp _excelTrailingDecimal = RegExp(r'^\d+\.0+$');
  static final RegExp _scientificNotation = RegExp(r'^\+?\d+(\.\d+)?[eE][+\-]?\d+$');

  String? normalize(dynamic input) {
    if (input == null) {
      return null;
    }

    var raw = input.toString().trim();
    if (raw.isEmpty) {
      return null;
    }

    raw = raw.replaceAll(_specialSpaces, '');
    raw = _normalizeExcelNumericText(raw);

    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return null;
    }

    if (digits.length == 10 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    if (digits.length == 9) {
      digits = '998$digits';
    }

    if (_validUzbekPhone.hasMatch(digits)) {
      return digits;
    }

    return null;
  }

  String _normalizeExcelNumericText(String value) {
    if (_excelTrailingDecimal.hasMatch(value)) {
      return value.split('.').first;
    }

    if (_scientificNotation.hasMatch(value)) {
      final expanded = _expandScientificToInteger(value);
      if (expanded != null) {
        return expanded;
      }

      final parsed = num.tryParse(value);
      if (parsed != null) {
        return parsed.toStringAsFixed(0);
      }
    }

    return value;
  }

  String? _expandScientificToInteger(String input) {
    final lower = input.toLowerCase();
    final parts = lower.split('e');
    if (parts.length != 2) {
      return null;
    }

    final mantissa = parts[0].replaceFirst('+', '');
    final exponent = int.tryParse(parts[1]);
    if (exponent == null) {
      return null;
    }

    final dotIndex = mantissa.indexOf('.');
    final decimals = dotIndex == -1 ? 0 : mantissa.length - dotIndex - 1;
    final digits = mantissa.replaceAll('.', '');
    final shift = exponent - decimals;

    if (shift < 0) {
      return null;
    }

    return '$digits${'0' * shift}';
  }
}
