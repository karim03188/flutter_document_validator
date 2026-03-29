enum DocumentType {
  governmentId,
  insurance,
  tradesCertificate,
  businessLicense,
  policeCheck,
  unknown,
}

enum DateCheckStatus {
  /// Date was found in the OCR text and is still valid.
  found,

  /// Date was found but is in the past — document is expired.
  expired,

  /// This document type requires a date but it could not be read clearly.
  notFound,

  /// This document type does not have this date field.
  notApplicable,
}

class ValidationResult {
  final DocumentType documentType;
  final bool isAccepted;
  final double confidence;
  final bool hasFace;
  final int textLength;
  final String extractedText;
  final String message;

  // Date fields
  final String? expiryDateRaw;
  final String? issueDateRaw;
  final DateCheckStatus expiryStatus;
  final DateCheckStatus issueDateStatus;

  /// True when any required date is expired or could not be read clearly.
  final bool hasDatesWarning;

  const ValidationResult({
    required this.documentType,
    required this.isAccepted,
    required this.confidence,
    required this.hasFace,
    required this.textLength,
    required this.extractedText,
    required this.message,
    this.expiryDateRaw,
    this.issueDateRaw,
    required this.expiryStatus,
    required this.issueDateStatus,
    required this.hasDatesWarning,
  });
}
