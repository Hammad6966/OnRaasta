import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import 'mechanic_home_screen.dart';

class NewRequestDetailScreen extends StatelessWidget {
  final Map<String, dynamic> job;

  const NewRequestDetailScreen({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    final request = JobRequest.fromJson(job);
    final ai = request.aiDiagnosis;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        border: Border.all(color: AppColors.darkBorder),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Job Request',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Syne',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.darkSuccess.withOpacity(0.15),
                      border: Border.all(
                          color: AppColors.darkSuccess.withOpacity(0.4)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      request.timeAgo,
                      style: const TextStyle(
                        color: AppColors.darkSuccess,
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Scrollable content ───────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info chips row
                    _InfoRow(request: request),

                    const SizedBox(height: 16),

                    // Location card
                    _SectionCard(
                      icon: Icons.location_on_rounded,
                      iconColor: AppColors.darkError,
                      title: 'Location',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (job['location'] as Map?)?['address'] as String? ??
                                'Current Location',
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'DM Sans',
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.near_me_rounded,
                                  color: AppColors.darkTextSecondary, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                '${request.distance.toStringAsFixed(1)} km away',
                                style: const TextStyle(
                                  color: AppColors.darkTextSecondary,
                                  fontFamily: 'DM Sans',
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Description card
                    _SectionCard(
                      icon: Icons.description_rounded,
                      iconColor: AppColors.darkPrimary,
                      title: 'Problem Description',
                      child: Text(
                        request.description,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'DM Sans',
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                    ),

                    // AI diagnosis card (conditional)
                    if (ai != null) ...[
                      const SizedBox(height: 12),
                      _AiDiagnosisCard(ai: ai),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── Bottom action buttons ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: const BoxDecoration(
                color: AppColors.darkSurface,
                border: Border(top: BorderSide(color: AppColors.darkBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.darkBorder),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'Decline',
                        style: TextStyle(
                          color: AppColors.darkTextSecondary,
                          fontFamily: 'DM Sans',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => context.push('/submit-bid', extra: job),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.darkPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.gavel_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Place a Bid',
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'DM Sans',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final JobRequest request;
  const _InfoRow({required this.request});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _InfoChip(
          icon: Icons.near_me_rounded,
          value: '${request.distance.toStringAsFixed(1)} km',
          label: 'Distance',
        ),
        const SizedBox(width: 10),
        _InfoChip(
          icon: Icons.access_time_rounded,
          value: request.timeAgo,
          label: 'Posted',
        ),
        if (request.faultLabel != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _InfoChip(
              icon: Icons.auto_fix_high_rounded,
              value: request.faultLabel!,
              label: 'Fault',
              valueColor: AppColors.darkWarning,
              expand: true,
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color valueColor;
  final bool expand;

  const _InfoChip({
    required this.icon,
    required this.value,
    required this.label,
    this.valueColor = Colors.white,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: expand ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        border: Border.all(color: AppColors.darkBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.darkTextSecondary, size: 13),
              const SizedBox(width: 4),
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.darkTextSecondary,
                  fontFamily: 'DM Sans',
                  fontSize: 10,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontFamily: 'DM Sans',
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    return content;
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        border: Border.all(color: AppColors.darkBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.darkTextSecondary,
                  fontFamily: 'DM Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── AI diagnosis card ─────────────────────────────────────────────────────────

class _AiDiagnosisCard extends StatelessWidget {
  final Map<String, dynamic> ai;
  const _AiDiagnosisCard({required this.ai});

  @override
  Widget build(BuildContext context) {
    final faultClass =
        (ai['fault_class'] as String? ?? 'Unknown').replaceAll('_', ' ');
    final confidence = (ai['confidence'] as num?)?.toDouble() ?? 0.0;
    final costMin = ai['cost_min']?.toString() ?? '?';
    final costMax = ai['cost_max']?.toString() ?? '?';
    final skillRequired = ai['skill_required'] as String? ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2E),
        border: Border.all(color: AppColors.darkWarning.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.darkWarning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.psychology_rounded,
                    color: AppColors.darkWarning, size: 16),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'AI Diagnosis',
                  style: TextStyle(
                    color: AppColors.darkWarning,
                    fontFamily: 'Syne',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${(confidence * 100).toInt()}% confidence',
                style: const TextStyle(
                  color: AppColors.darkTextSecondary,
                  fontFamily: 'DM Sans',
                  fontSize: 12,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Fault class
          Text(
            faultClass.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Syne',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),

          if (skillRequired.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Skill required: $skillRequired',
              style: const TextStyle(
                color: AppColors.darkTextSecondary,
                fontFamily: 'DM Sans',
                fontSize: 13,
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Cost range
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.darkBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.monetization_on_rounded,
                    color: AppColors.darkSuccess, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'Estimated Cost:',
                  style: TextStyle(
                    color: AppColors.darkTextSecondary,
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text(
                  'PKR $costMin – $costMax',
                  style: const TextStyle(
                    color: AppColors.darkSuccess,
                    fontFamily: 'DM Sans',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
