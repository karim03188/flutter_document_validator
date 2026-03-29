import 'dart:io';
import 'dart:math';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/validation_result.dart';

/// Internal holder for a raw date string and whether it is in the past.
class _DateInfo {
  final String? raw;
  final bool isExpired;
  const _DateInfo({this.raw, required this.isExpired});
}

class DocumentValidatorService {
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: false,
      enableClassification: false,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  // ── Canadian document keywords ─────────────────────────────────────────
  // Each keyword found adds 1 point. 3 matches = 100% confidence (capped).
  static const Map<DocumentType, List<String>> _keywords = {
    DocumentType.governmentId: [
      'driver', 'licence', 'license', 'passport', 'ontario', 'alberta',
      'british columbia', 'quebec', 'manitoba', 'saskatchewan', 'nova scotia',
      'new brunswick', 'newfoundland', 'prince edward', 'canada',
      'health card', 'ohip', 'date of birth', 'expiry', 'expires',
      'sex', 'height', 'address', 'pr card', 'permanent resident',
      'citizenship', 'photo id', 'identification', 'class',
    ],
    DocumentType.insurance: [
      'insurance', 'wsib', 'liability', 'coverage', 'policy',
      'certificate of insurance', 'workplace safety', 'workers compensation',
      'insured', 'insurer', 'broker', 'underwriter', 'indemnity',
      'premium', 'deductible', 'commercial general liability', 'cgl',
      'certificate holder', 'additional insured',
    ],
    DocumentType.tradesCertificate: [
      'certificate', 'certification', 'licensed', 'journeyman',
      'journeyperson', 'red seal', 'electrical', 'plumbing', 'hvac',
      'refrigeration', 'gas fitter', 'tssa', 'esa',
      'ontario college of trades', 'trades qualification', 'apprentice',
      'master electrician', 'skilled trade', 'contractor', 'carpentry',
      'roofing', 'tile setter', 'steam fitter',
    ],
    DocumentType.businessLicense: [
      'business license', 'business licence', 'municipal', 'city of',
      'town of', 'corporation of', 'commercial registration',
      'business number', 'hst', 'gst', 'canada revenue', 'revenue canada',
      'bylaw', 'zoning', 'trade name', 'operating as', 'sole proprietor',
    ],
    DocumentType.policeCheck: [
      'police', 'criminal record', 'vulnerable sector', 'rcmp',
      'background check', 'clearance', 'judicial matters',
      'criminal background', 'offence', 'felony', 'record suspension',
    ],
  };

  // ── Date regex patterns ──────────────────────────────────────────────────

  /// Matches: dd/mm/yyyy · mm/dd/yyyy · yyyy-mm-dd · mm/yyyy · yyyy/mm
  ///          Month dd yyyy · dd Month yyyy  (case-insensitive)
  static final _datePattern = RegExp(
    r'(?:'
    r'\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{4}'
    r'|\d{4}[\/\-\.]\d{1,2}[\/\-\.]\d{1,2}'
    r'|\d{1,2}[\/\-\.]\d{4}'
    r'|\d{4}[\/\-\.]\d{1,2}'
    r'|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}'
    r'|\d{1,2}\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{4}'
    r')',
    caseSensitive: false,
  );

  /// Lines that signal an expiry / end date.
  static final _expiryLinePattern = RegExp(
    r'expir|exp[:\s.\-\/]|exp$|valid until|valid to |valid thru|not.?after|renew',
    caseSensitive: false,
  );

  /// Lines that signal an issue / start date.
  static final _issueLinePattern = RegExp(
    r'issued|issue date|date of issue|valid from|effective|iss[:\s.]|approved|certified|date of cert',
    caseSensitive: false,
  );

  /// Coverage period: "dd/mm/yyyy to dd/mm/yyyy"  Group 1 = start, Group 2 = end.
  static final _coveragePeriodPattern = RegExp(
    r'(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{4}|\d{4}[\/\-\.]\d{1,2}[\/\-\.]\d{1,2})'
    r'\s*(?:to|through|until|-)\s*'
    r'(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{4}|\d{4}[\/\-\.]\d{1,2}[\/\-\.]\d{1,2})',
    caseSensitive: false,
  );

  // ── Public API ───────────────────────────────────────────────────────────

  Future<ValidationResult> validateImage(File file) async {
    final inputImage = InputImage.fromFile(file);

    final recognizedText = await _textRecognizer.processImage(inputImage);
    final faces = await _faceDetector.processImage(inputImage);

    final rawText = recognizedText.text.trim();
    final lower = rawText.toLowerCase();
    final hasFace = faces.isNotEmpty;
    final textLength = rawText.replaceAll(RegExp(r'\s+'), ' ').trim().length;

    // ── Keyword scoring ──────────────────────────────────────────────────
    final scores = <DocumentType, int>{};
    for (final entry in _keywords.entries) {
      scores[entry.key] = entry.value.where(lower.contains).length;
    }

    DocumentType bestType = DocumentType.unknown;
    int bestScore = 0;
    scores.forEach((type, score) {
      if (score > bestScore) {
        bestScore = score;
        bestType = type;
      }
    });

    final confidence = bestScore == 0 ? 0.0 : min(1.0, bestScore / 3.0);
    final isContentAccepted =
        bestType != DocumentType.unknown && confidence >= 0.4 && textLength > 15;

    // ── Date extraction ──────────────────────────────────────────────────
    final expiryInfo = _extractExpiryDate(rawText);
    final issueInfo = _extractIssueDate(rawText);

    final requiresExpiry = _requiresExpiry(bestType);
    final requiresIssue = _requiresIssueDate(bestType);

    final expiryStatus = _toDateStatus(expiryInfo, requiresExpiry, isExpiryField: true);
    final issueDateStatus = _toDateStatus(issueInfo, requiresIssue, isExpiryField: false);

    // Date warning when: expired OR required date not found
    final hasDatesWarning =
        expiryStatus == DateCheckStatus.expired ||
        (requiresExpiry && expiryStatus == DateCheckStatus.notFound) ||
        (requiresIssue && issueDateStatus == DateCheckStatus.notFound);

    final isAccepted = isContentAccepted && !hasDatesWarning;

    final message = _buildMessage(
      bestType, isContentAccepted, confidence, hasFace, textLength,
      expiryStatus, issueDateStatus, hasDatesWarning,
    );

    return ValidationResult(
      documentType: bestType,
      isAccepted: isAccepted,
      confidence: confidence,
      hasFace: hasFace,
      textLength: textLength,
      extractedText: rawText,
      message: message,
      expiryDateRaw: expiryInfo.raw,
      issueDateRaw: issueInfo.raw,
      expiryStatus: expiryStatus,
      issueDateStatus: issueDateStatus,
      hasDatesWarning: hasDatesWarning,
    );
  }

  // ── Date helpers ─────────────────────────────────────────────────────────

  _DateInfo _extractExpiryDate(String text) {
    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (_expiryLinePattern.hasMatch(lines[i])) {
        final searchText = i + 1 < lines.length
            ? '${lines[i]} ${lines[i + 1]}'
            : lines[i];
        final match = _datePattern.firstMatch(searchText);
        if (match != null) {
          final raw = match.group(0)!;
          return _DateInfo(raw: raw, isExpired: _isDateExpired(raw));
        }
      }
    }
    // Fallback: insurance-style coverage period — take the end date
    final cp = _coveragePeriodPattern.firstMatch(text);
    if (cp != null) {
      final raw = cp.group(2)!;
      return _DateInfo(raw: raw, isExpired: _isDateExpired(raw));
    }
    return const _DateInfo(raw: null, isExpired: false);
  }

  _DateInfo _extractIssueDate(String text) {
    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (_issueLinePattern.hasMatch(lines[i])) {
        final searchText = i + 1 < lines.length
            ? '${lines[i]} ${lines[i + 1]}'
            : lines[i];
        final match = _datePattern.firstMatch(searchText);
        if (match != null) {
          return _DateInfo(raw: match.group(0)!, isExpired: false);
        }
      }
    }
    // Fallback: insurance-style coverage period — take the start date
    final cp = _coveragePeriodPattern.firstMatch(text);
    if (cp != null) {
      return _DateInfo(raw: cp.group(1)!, isExpired: false);
    }
    return const _DateInfo(raw: null, isExpired: false);
  }

  /// Returns true if [dateStr] contains a 20xx year that is in the past.
  /// Uses month names for same-year comparison to avoid day/month ambiguity.
  bool _isDateExpired(String dateStr) {
    final now = DateTime.now();
    final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(dateStr);
    if (yearMatch == null) return false;

    final year = int.parse(yearMatch.group(1)!);
    if (year < now.year) return true;
    if (year > now.year) return false;

    // Same year — use month names for confident determination only
    const monthMap = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final lower = dateStr.toLowerCase();
    for (final entry in monthMap.entries) {
      if (lower.contains(entry.key)) {
        return entry.value < now.month;
      }
    }

    // Try mm/yyyy pattern specifically (unambiguous month position)
    final mmYYYY = RegExp(r'^(0?[1-9]|1[0-2])[\/\-\.]20\d{2}$')
        .firstMatch(dateStr.trim());
    if (mmYYYY != null) {
      return int.parse(mmYYYY.group(1)!) < now.month;
    }

    return false; // Same year, month not determinable — assume still valid
  }

  DateCheckStatus _toDateStatus(
    _DateInfo info,
    bool required, {
    required bool isExpiryField,
  }) {
    if (!required) return DateCheckStatus.notApplicable;
    if (info.raw == null) return DateCheckStatus.notFound;
    if (isExpiryField && info.isExpired) return DateCheckStatus.expired;
    return DateCheckStatus.found;
  }

  static bool _requiresExpiry(DocumentType type) =>
      type == DocumentType.governmentId ||
      type == DocumentType.insurance ||
      type == DocumentType.businessLicense;

  static bool _requiresIssueDate(DocumentType type) =>
      type == DocumentType.insurance ||
      type == DocumentType.policeCheck;

  // ── Message building ─────────────────────────────────────────────────────

  String _buildMessage(
    DocumentType type,
    bool isContentAccepted,
    double confidence,
    bool hasFace,
    int textLength,
    DateCheckStatus expiryStatus,
    DateCheckStatus issueDateStatus,
    bool hasDatesWarning,
  ) {
    // Expired document — highest priority
    if (expiryStatus == DateCheckStatus.expired) {
      return 'Document is EXPIRED. Please upload a currently valid document.';
    }

    // Selfie / no text
    if (type == DocumentType.unknown && hasFace && textLength < 20) {
      return 'Selfie or personal photo detected. Please upload a valid Canadian document.';
    }
    if (type == DocumentType.unknown && textLength < 15) {
      return 'No recognizable text found. Hold the camera steady and ensure good lighting.';
    }
    if (type == DocumentType.unknown) {
      return 'Document type not recognized. Upload a government ID, insurance certificate, trades certificate, business license, or police check.';
    }

    final pct = (confidence * 100).toInt();

    if (!isContentAccepted) {
      return 'Possible ${typeLabel(type)}, but confidence is too low ($pct%). Try a clearer, straighter photo.';
    }

    // Document identified but one or more required dates not readable
    if (hasDatesWarning) {
      final missing = <String>[];
      if (expiryStatus == DateCheckStatus.notFound) missing.add('expiry date');
      if (issueDateStatus == DateCheckStatus.notFound) missing.add('issue date');
      return '${typeLabel(type)} detected ($pct% confidence), but the '
          '${missing.join(' and ')} could not be clearly read. '
          'Retake with better lighting and ensure the full document is flat and in frame.';
    }

    return 'Accepted — ${typeLabel(type)} detected ($pct% confidence).';
  }

  static String typeLabel(DocumentType type) {
    switch (type) {
      case DocumentType.governmentId:
        return 'Government ID';
      case DocumentType.insurance:
        return 'Insurance Certificate';
      case DocumentType.tradesCertificate:
        return 'Trades Certificate';
      case DocumentType.businessLicense:
        return 'Business License';
      case DocumentType.policeCheck:
        return 'Police / Background Check';
      case DocumentType.unknown:
        return 'Unknown';
    }
  }

  Future<void> dispose() async {
    await _textRecognizer.close();
    await _faceDetector.close();
  }
}
