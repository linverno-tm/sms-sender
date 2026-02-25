class ImportedFile {
  ImportedFile({
    required this.path,
    required this.name,
    required this.extension,
    required this.validNumbers,
    required this.invalidCount,
    this.errorMessage,
  });

  final String path;
  final String name;
  final String extension;
  final Set<String> validNumbers;
  final int invalidCount;
  final String? errorMessage;

  int get validCount => validNumbers.length;
}
