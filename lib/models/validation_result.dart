class ValidationResult {
  final bool looksLikeDocument;
  final bool hasFace;
  final int textLength;
  final String extractedText;
  final String message;

  const ValidationResult({
    required this.looksLikeDocument,
    required this.hasFace,
    required this.textLength,
    required this.extractedText,
    required this.message,
  });
}
