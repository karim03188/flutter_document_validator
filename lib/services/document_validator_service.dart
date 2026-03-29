import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/validation_result.dart';

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

  Future<ValidationResult> validateImage(File file) async {
    final inputImage = InputImage.fromFile(file);

    final recognizedText = await _textRecognizer.processImage(inputImage);
    final faces = await _faceDetector.processImage(inputImage);

    final text = recognizedText.text.trim();
    final hasFace = faces.isNotEmpty;
    final textLength = text.replaceAll('\n', ' ').trim().length;

    final lower = text.toLowerCase();

    final hasDocKeywords = [
      'license',
      'licence',
      'driver',
      'policy',
      'insurance',
      'permit',
      'expiry',
      'expires',
      'id',
      'identification',
      'government',
      'name',
      'address',
    ].any(lower.contains);

    final looksLikeDocument = textLength > 20 || hasDocKeywords;

    String message;
    if (hasFace && textLength < 20) {
      message = 'This looks more like a human photo than a document image.';
    } else if (!looksLikeDocument) {
      message = 'This does not appear to be a clear document image.';
    } else {
      message = 'This image appears to be a document.';
    }

    return ValidationResult(
      looksLikeDocument: looksLikeDocument,
      hasFace: hasFace,
      textLength: textLength,
      extractedText: text,
      message: message,
    );
  }

  Future<void> dispose() async {
    await _textRecognizer.close();
    await _faceDetector.close();
  }
}
