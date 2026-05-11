import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

class MechanicRatingsScreen extends StatelessWidget {
  const MechanicRatingsScreen({super.key});

  static const double _avgRating = 4.7;

  static const List<Map<String, dynamic>> _reviews = [
    {
      'user': 'Hamza K.',
      'rating': 5,
      'date': 'May 8, 2026',
      'comment': 'Very professional and fast. Fixed my engine issue in no time!',
      'tags': ['Fast', 'Professional', 'Fair Price'],
    },
    {
      'user': 'Sana M.',
      'rating': 4,
      'date': 'May 5, 2026',
      'comment': 'Good service, arrived on time. A bit pricey.',
      'tags': ['On Time', 'Friendly'],
    },
    {
      'user': 'Ali R.',
      'rating': 5,
      'date': 'May 1, 2026',
      'comment': 'Excellent! Replaced my battery in under 20 minutes.',
      'tags': ['Fast', 'Skilled'],
    },
    {
      'user': 'Fatima Z.',
      'rating': 4,
      'date': 'Apr 28, 2026',
      'comment': 'Reliable mechanic. Will definitely use again.',
      'tags': ['Reliable', 'Professional'],
    },
    {
      'user': 'Usman T.',
      'rating': 5,
      'date': 'Apr 20, 2026',
      'comment': 'Best roadside mechanic I have ever used. Highly recommend!',
      'tags': ['Excellent', 'Fast', 'Skilled'],
    },
  ];

  // Star distribution (5→4→3→2→1)
  static const List<int> _starDist = [3, 1, 0, 0, 0];

  @override
  Widget build(BuildContext context) {
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
                  Text('My Ratings',
                      style: GoogleFonts.syne(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // ── Summary card ────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Row(
                        children: [
                          // Big number
                          Column(
                            children: [
                              Text(
                                _avgRating.toStringAsFixed(1),
                                style: GoogleFonts.syne(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white),
                              ),
                              Row(
                                children: List.generate(
                                  5,
                                  (i) => Icon(
                                    i < _avgRating.floor()
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    color: AppColors.darkAccent,
                                    size: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_reviews.length} reviews',
                                style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    color: const Color(0xFF94A3B8)),
                              ),
                            ],
                          ),

                          const SizedBox(width: 24),

                          // Star bars
                          Expanded(
                            child: Column(
                              children: List.generate(5, (i) {
                                final star = 5 - i;
                                final count = _starDist[i];
                                final frac = _reviews.isEmpty
                                    ? 0.0
                                    : count / _reviews.length;
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    children: [
                                      Text('$star',
                                          style: GoogleFonts.dmSans(
                                              fontSize: 11,
                                              color: const Color(0xFF94A3B8))),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.star_rounded,
                                          color: AppColors.darkAccent,
                                          size: 11),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: frac,
                                            backgroundColor: AppColors.darkBorder,
                                            valueColor:
                                                const AlwaysStoppedAnimation(
                                                    AppColors.darkAccent),
                                            minHeight: 6,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text('$count',
                                          style: GoogleFonts.dmSans(
                                              fontSize: 11,
                                              color: const Color(0xFF94A3B8))),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Section label ──────────────────────────────────
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('REVIEWS',
                          style: GoogleFonts.dmSans(
                              fontSize: 11,
                              color: const Color(0xFF94A3B8),
                              letterSpacing: 0.8)),
                    ),
                    const SizedBox(height: 8),

                    // ── Review list ────────────────────────────────────
                    ..._reviews.map((r) => _ReviewCard(review: r)),

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

// ── Review card ───────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final tags = (review['tags'] as List).cast<String>();
    final rating = review['rating'] as int;

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
          // ── Header ──────────────────────────────────────────────────
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0x1A2563EB),
                child: Text(
                  (review['user'] as String).substring(0, 1),
                  style: GoogleFonts.syne(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkPrimary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(review['user'] as String,
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: Colors.white,
                            fontWeight: FontWeight.w500)),
                    Text(review['date'] as String,
                        style: GoogleFonts.dmSans(
                            fontSize: 11,
                            color: const Color(0xFF94A3B8))),
                  ],
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: AppColors.darkAccent,
                    size: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {},
                child: const Icon(Icons.flag_outlined,
                    color: Color(0xFF94A3B8), size: 16),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text(review['comment'] as String,
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: const Color(0xFFCBD5E1))),

          const SizedBox(height: 10),

          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.darkPrimary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.darkPrimary.withOpacity(0.3)),
                    ),
                    child: Text(tag,
                        style: GoogleFonts.dmSans(
                            fontSize: 11,
                            color: AppColors.darkPrimary)),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
