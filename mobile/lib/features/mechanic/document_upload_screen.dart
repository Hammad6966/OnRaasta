import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';

class DocumentUploadScreen extends StatefulWidget {
  const DocumentUploadScreen({super.key});

  @override
  State<DocumentUploadScreen> createState() => _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends State<DocumentUploadScreen> {
  final List<_DocItem> _docs = [
    _DocItem(title: 'CNIC Front', subtitle: 'Clear photo of your CNIC front side', icon: Icons.credit_card),
    _DocItem(title: 'CNIC Back', subtitle: 'Clear photo of your CNIC back side', icon: Icons.credit_card_outlined),
    _DocItem(title: 'Workshop Permit', subtitle: 'Valid permit or registration document', icon: Icons.article_outlined),
  ];

  void _submit() {
    final uploaded = _docs.where((d) => d.uploaded).length;
    if (uploaded < _docs.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.darkError,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text('Please upload all documents first.',
              style: GoogleFonts.dmSans(color: Colors.white)),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkSuccess,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text('Documents submitted for review!',
            style: GoogleFonts.dmSans(color: Colors.white)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Upload Documents',
                      style: GoogleFonts.syne(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Info banner ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.darkPrimary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.darkPrimary.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.darkPrimary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Documents are reviewed within 24 hours. You\'ll be notified once approved.',
                        style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Upload cards ───────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    ..._docs.asMap().entries.map((entry) {
                      final i = entry.key;
                      final doc = entry.value;
                      return _UploadCard(
                        doc: doc,
                        onTap: () => setState(() => _docs[i].uploaded = !_docs[i].uploaded),
                      );
                    }),

                    const SizedBox(height: 24),

                    OnRaastaButton(label: 'Submit Documents', onPressed: _submit),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Model ─────────────────────────────────────────────────────────────────────

class _DocItem {
  final String title;
  final String subtitle;
  final IconData icon;
  bool uploaded;

  _DocItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.uploaded = false,
  });
}

// ── Upload card ───────────────────────────────────────────────────────────────

class _UploadCard extends StatelessWidget {
  final _DocItem doc;
  final VoidCallback onTap;

  const _UploadCard({required this.doc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: doc.uploaded ? AppColors.darkSuccess : AppColors.darkBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: doc.uploaded
                      ? AppColors.darkSuccess.withOpacity(0.1)
                      : const Color(0x1A2563EB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  doc.uploaded ? Icons.check_circle_rounded : doc.icon,
                  color: doc.uploaded
                      ? AppColors.darkSuccess
                      : AppColors.darkPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.title,
                        style: GoogleFonts.syne(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    Text(doc.subtitle,
                        style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8))),
                  ],
                ),
              ),
              if (doc.uploaded)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.darkSuccess.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.darkSuccess),
                  ),
                  child: Text('Uploaded',
                      style: GoogleFonts.dmSans(
                          fontSize: 11, color: AppColors.darkSuccess)),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Upload zone ───────────────────────────────────────────────
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF0A1628),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: doc.uploaded
                      ? AppColors.darkSuccess.withOpacity(0.4)
                      : AppColors.darkBorder,
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                child: doc.uploaded
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.image_rounded,
                              color: AppColors.darkSuccess, size: 20),
                          const SizedBox(width: 8),
                          Text('document_${doc.title.replaceAll(' ', '_').toLowerCase()}.jpg',
                              style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: AppColors.darkSuccess)),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_upload_outlined,
                              color: Color(0xFF94A3B8), size: 24),
                          const SizedBox(height: 6),
                          Text('Tap to upload',
                              style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: const Color(0xFF94A3B8))),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
