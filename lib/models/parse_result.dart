class ParseResult {
  ParseResult({
    required this.validNumbers,
    required this.invalidCount,
  });

  final Set<String> validNumbers;
  final int invalidCount;
}
