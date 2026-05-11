import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

class MechanicEarningsScreen extends StatelessWidget {
  const MechanicEarningsScreen({super.key});

  static const List<Map<String, dynamic>> _transactions = [
    {
      'title': 'Engine Overheating',
      'date': 'May 8, 2026',
      'gross': 2500,
      'net': 2125,
    },
    {
      'title': 'Flat Tyre Replacement',
      'date': 'May 5, 2026',
      'gross': 800,
      'net': 680,
    },
    {
      'title': 'Battery Replacement',
      'date': 'May 1, 2026',
      'gross': 1200,
      'net': 1020,
    },
    {
      'title': 'Brake Pads',
      'date': 'Apr 28, 2026',
      'gross': 3200,
      'net': 2720,
    },
    {
      'title': 'Gear Shift Repair',
      'date': 'Apr 20, 2026',
      'gross': 4500,
      'net': 3825,
    },
  ];

  @override
  Widget build(BuildContext context) {
    const totalEarned = 10370;
    const weeklyEarned = 2805;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────
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
                      child:
                          const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Earnings',
                      style: GoogleFonts.syne(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // ── Gradient total card ───────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1A3A6B), Color(0xFF2563EB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total Earned',
                              style: GoogleFonts.dmSans(
                                  fontSize: 13, color: Colors.white70)),
                          const SizedBox(height: 4),
                          Text(
                            'PKR $totalEarned',
                            style: GoogleFonts.syne(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.trending_up,
                                  color: Colors.white70, size: 16),
                              const SizedBox(width: 6),
                              Text('+12% from last month',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 12, color: Colors.white70)),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Weekly + fee cards ─────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryCard(
                            label: 'This Week',
                            value: 'PKR $weeklyEarned',
                            icon: Icons.date_range_rounded,
                            iconColor: AppColors.darkSuccess,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryCard(
                            label: 'Platform Fee',
                            value: '15%',
                            icon: Icons.percent_rounded,
                            iconColor: AppColors.darkAccent,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Transactions ───────────────────────────────────────
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('RECENT TRANSACTIONS',
                          style: GoogleFonts.dmSans(
                              fontSize: 11,
                              color: const Color(0xFF94A3B8),
                              letterSpacing: 0.8)),
                    ),
                    const SizedBox(height: 8),
                    ..._transactions
                        .map((t) => _TransactionRow(data: t)),

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

// ── Summary card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 10),
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: const Color(0xFF94A3B8))),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.syne(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

// ── Transaction row ───────────────────────────────────────────────────────────

class _TransactionRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TransactionRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.darkSuccess.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.payments_rounded,
                color: AppColors.darkSuccess, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['title'] as String,
                    style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(data['date'] as String,
                    style: GoogleFonts.dmSans(
                        fontSize: 11, color: const Color(0xFF94A3B8))),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'PKR ${data['net']}',
                style: GoogleFonts.syne(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkSuccess),
              ),
              Text(
                'Gross ${data['gross']}',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: const Color(0xFF94A3B8)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
