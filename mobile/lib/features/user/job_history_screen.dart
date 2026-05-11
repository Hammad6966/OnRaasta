import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/status_badge.dart';

class JobHistoryScreen extends StatefulWidget {
  const JobHistoryScreen({super.key});

  @override
  State<JobHistoryScreen> createState() => _JobHistoryScreenState();
}

class _JobHistoryScreenState extends State<JobHistoryScreen> {
  int _filterIndex = 0;
  final List<String> _filters = ['All', 'Active', 'Completed', 'Cancelled'];

  final List<Map<String, dynamic>> _allJobs = [
    {
      'id': 'JOB-001',
      'title': 'Engine Overheating',
      'mechanic': 'Ahmed Khan',
      'date': 'May 8, 2026',
      'amount': 2500,
      'status': 'completed',
    },
    {
      'id': 'JOB-002',
      'title': 'Flat Tyre Replacement',
      'mechanic': 'Bilal Raza',
      'date': 'May 5, 2026',
      'amount': 800,
      'status': 'completed',
    },
    {
      'id': 'JOB-003',
      'title': 'Battery Dead',
      'mechanic': 'Usman Shah',
      'date': 'May 1, 2026',
      'amount': 1200,
      'status': 'in_progress',
    },
    {
      'id': 'JOB-004',
      'title': 'Brake Pads Worn',
      'mechanic': 'Kamran Ali',
      'date': 'Apr 28, 2026',
      'amount': 3200,
      'status': 'cancelled',
    },
    {
      'id': 'JOB-005',
      'title': 'Gear Shift Issue',
      'mechanic': 'Tariq Mehmood',
      'date': 'Apr 20, 2026',
      'amount': 4500,
      'status': 'completed',
    },
  ];

  List<Map<String, dynamic>> get _filtered {
    if (_filterIndex == 0) return _allJobs;
    final label = _filters[_filterIndex].toLowerCase();
    if (label == 'active') {
      return _allJobs
          .where((j) => j['status'] == 'in_progress' || j['status'] == 'en_route')
          .toList();
    }
    return _allJobs.where((j) => j['status'] == label).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ──────────────────────────────────────────────────────
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
                  Text(
                    'Job History',
                    style: GoogleFonts.syne(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Filter tabs ──────────────────────────────────────────────────
            SizedBox(
              height: 36,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filters.length,
                itemBuilder: (_, i) {
                  final active = i == _filterIndex;
                  return GestureDetector(
                    onTap: () => setState(() => _filterIndex = i),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.darkPrimary
                            : AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active
                              ? AppColors.darkPrimary
                              : AppColors.darkBorder,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _filters[i],
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: active
                                ? Colors.white
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // ── Job list ────────────────────────────────────────────────────
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.history_rounded,
                              color: Color(0xFF1E3A5F), size: 64),
                          const SizedBox(height: 12),
                          Text('No jobs found',
                              style: GoogleFonts.syne(
                                  fontSize: 16,
                                  color: const Color(0xFF94A3B8))),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) =>
                          _JobHistoryCard(job: _filtered[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _JobHistoryCard extends StatelessWidget {
  final Map<String, dynamic> job;
  const _JobHistoryCard({required this.job});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0x1A2563EB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.build_rounded,
                    color: AppColors.darkPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job['title'] as String,
                      style: GoogleFonts.syne(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                    Text(
                      job['mechanic'] as String,
                      style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: const Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
              StatusBadge(status: job['status'] as String),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: Color(0xFF1E3A5F), height: 1),
          const SizedBox(height: 12),

          // ── Meta row ────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded,
                  color: Color(0xFF94A3B8), size: 13),
              const SizedBox(width: 4),
              Text(
                job['date'] as String,
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: const Color(0xFF94A3B8)),
              ),
              const Spacer(),
              Text(
                'PKR ${job['amount']}',
                style: GoogleFonts.syne(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkAccent),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Actions ─────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0x1A2563EB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.darkPrimary),
                    ),
                    child: Center(
                      child: Text(
                        'View Details',
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: AppColors.darkPrimary,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
              if (job['status'] == 'completed') ...[
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.darkSuccess.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.darkSuccess),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.download_rounded,
                              color: AppColors.darkSuccess, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'Receipt',
                            style: GoogleFonts.dmSans(
                                fontSize: 13,
                                color: AppColors.darkSuccess,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
