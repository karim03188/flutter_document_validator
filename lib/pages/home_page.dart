import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/validation_result.dart';
import '../services/document_validator_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker _picker = ImagePicker();
  final DocumentValidatorService _validator = DocumentValidatorService();

  File? _selectedImage;
  ValidationResult? _result;
  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source) async {
    try {
      setState(() {
        _isLoading = true;
        _result = null;
      });

      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 90,
      );

      if (pickedFile == null) {
        setState(() => _isLoading = false);
        return;
      }

      final file = File(pickedFile.path);
      final result = await _validator.validateImage(file);

      setState(() {
        _selectedImage = file;
        _result = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _validator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Validator'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInstructions(),
            const SizedBox(height: 16),
            _buildPickButtons(),
            const SizedBox(height: 20),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
            if (_selectedImage != null) ...[
              _buildImagePreview(),
              const SizedBox(height: 16),
            ],
            if (_result != null) _buildResultCard(_result!),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return Card(
      color: Colors.blue.shade50,
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Accepted documents',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 6),
            Text('• Government ID (driver\'s licence, passport, PR card)'),
            Text('• Insurance certificate (WSIB, general liability)'),
            Text('• Trades certificate (ESA, TSSA, Red Seal)'),
            Text('• Business license'),
            Text('• Police / background check'),
          ],
        ),
      ),
    );
  }

  Widget _buildPickButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed:
                _isLoading ? null : () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Camera'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed:
                _isLoading ? null : () => _pickImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library),
            label: const Text('Gallery'),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        _selectedImage!,
        height: 220,
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildResultCard(ValidationResult result) {
    final accepted = result.isAccepted;
    final bannerColor = accepted ? Colors.green.shade600 : Colors.red.shade600;
    final bannerIcon = accepted ? Icons.check_circle : Icons.cancel;
    final bannerLabel = accepted ? 'ACCEPTED' : 'REJECTED';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Accept / Reject banner ─────────────────────────────────
          Container(
            color: bannerColor,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                Icon(bannerIcon, color: Colors.white, size: 28),
                const SizedBox(width: 10),
                Text(
                  bannerLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Document type ────────────────────────────────────
                Row(
                  children: [
                    Icon(
                      _typeIcon(result.documentType),
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DocumentValidatorService.typeLabel(result.documentType),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Confidence bar ───────────────────────────────────
                Row(
                  children: [
                    const Text('Confidence: '),
                    Text(
                      '${(result.confidence * 100).toInt()}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _confidenceColor(result.confidence),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: result.confidence,
                  backgroundColor: Colors.grey.shade200,
                  color: _confidenceColor(result.confidence),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),

                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),

                // ── Details ─────────────────────────────────────────
                _detailRow(
                  Icons.face,
                  'Face detected',
                  result.hasFace ? 'Yes' : 'No',
                ),
                _detailRow(
                  Icons.text_fields,
                  'Text length',
                  '${result.textLength} chars',
                ),

                // ── Date checks ──────────────────────────────────────
                if (result.expiryStatus != DateCheckStatus.notApplicable ||
                    result.issueDateStatus != DateCheckStatus.notApplicable) ...[  
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  const Text(
                    'Document Dates',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (result.expiryStatus != DateCheckStatus.notApplicable)
                    _dateRow('Expiry Date', result.expiryStatus, result.expiryDateRaw),
                  if (result.issueDateStatus != DateCheckStatus.notApplicable)
                    _dateRow('Issue Date', result.issueDateStatus, result.issueDateRaw),
                  if (result.hasDatesWarning) ...[  
                    const SizedBox(height: 10),
                    _dateWarningBox(result),
                  ],
                ],

                const SizedBox(height: 12),

                // ── Message ─────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accepted
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accepted
                          ? Colors.green.shade200
                          : Colors.orange.shade200,
                    ),
                  ),
                  child: Text(result.message),
                ),

                const SizedBox(height: 16),

                // ── Extracted text ───────────────────────────────────
                const Text(
                  'Extracted Text',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      result.extractedText.isEmpty
                          ? 'No text found'
                          : result.extractedText,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  IconData _typeIcon(DocumentType type) {
    switch (type) {
      case DocumentType.governmentId:
        return Icons.badge;
      case DocumentType.insurance:
        return Icons.security;
      case DocumentType.tradesCertificate:
        return Icons.workspace_premium;
      case DocumentType.businessLicense:
        return Icons.store;
      case DocumentType.policeCheck:
        return Icons.local_police;
      case DocumentType.unknown:
        return Icons.help_outline;
    }
  }

  Color _confidenceColor(double confidence) {
    if (confidence >= 0.7) return Colors.green.shade600;
    if (confidence >= 0.4) return Colors.orange.shade600;
    return Colors.red.shade600;
  }

  Widget _dateRow(String label, DateCheckStatus status, String? raw) {
    final IconData icon;
    final Color color;
    final String valueText;

    if (status == DateCheckStatus.found) {
      icon = Icons.check_circle;
      color = Colors.green.shade600;
      valueText = raw ?? '';
    } else if (status == DateCheckStatus.expired) {
      icon = Icons.error;
      color = Colors.red.shade700;
      valueText = 'EXPIRED — ${raw ?? 'unknown date'}';
    } else if (status == DateCheckStatus.notFound) {
      icon = Icons.warning_amber_rounded;
      color = Colors.red.shade700;
      valueText = 'Not readable';
    } else {
      icon = Icons.remove;
      color = Colors.grey;
      valueText = 'N/A';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(
              valueText,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateWarningBox(ValidationResult result) {
    final isExpired = result.expiryStatus == DateCheckStatus.expired;
    final warningText = isExpired
        ? 'This document is EXPIRED and cannot be accepted. '
            'Please upload a currently valid document.'
        : 'One or more required dates could not be clearly read. '
            'Please retake the photo with better lighting and ensure '
            'the full document is flat, in frame, and in focus.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              warningText,
              style: TextStyle(
                color: Colors.red.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
