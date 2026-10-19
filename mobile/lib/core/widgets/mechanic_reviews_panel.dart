import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../../services/review_service.dart';
import '../../services/mechanic_service.dart';

class MechanicReviewsPanel extends StatefulWidget {
  final String? mechanicId;
  final ReviewService? service;
  final ValueChanged<ReviewPage>? onLoaded;
  const MechanicReviewsPanel(
      {super.key, this.mechanicId, this.service, this.onLoaded});
  @override
  State<MechanicReviewsPanel> createState() => _MechanicReviewsPanelState();
}

class _MechanicReviewsPanelState extends State<MechanicReviewsPanel> {
  ReviewPage? _data;
  final List<Map<String, dynamic>> _reviews = [];
  bool _loading = false;
  String? _error, _id;
  int _generation = 0;
  double get _avgRating => _data!.rating;
  List<int> get _starDist =>
      [for (var i = 5; i >= 1; i--) _data!.distribution[i]!];
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MechanicReviewsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mechanicId != widget.mechanicId ||
        oldWidget.service != widget.service) {
      ++_generation;
      _loading = false;
      _data = null;
      _id = null;
      _reviews.clear();
      _load();
    }
  }

  Future<void> _load({bool next = false}) async {
    if (_loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _id ??= widget.mechanicId ??
          (await MechanicService.instance.profile())['_id'] as String;
      final data = await (widget.service ?? ReviewService.instance)
          .reviews(_id!, page: next ? _data!.page + 1 : 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!next) _reviews.clear();
        _reviews.addAll(data.reviews);
        _data = data;
      });
      widget.onLoaded?.call(data);
    } on ReviewFailure catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Unable to load reviews. Please retry.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: AppColors.darkError)),
          TextButton(
              onPressed: () => _load(), child: const Text('Retry reviews'))
        ],
        if (_data != null) ...[
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
                      '${_data!.count} verified reviews',
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: const Color(0xFF94A3B8)),
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
                      final frac =
                          _data!.count == 0 ? 0.0 : count / _data!.count;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Text('$star',
                                style: GoogleFonts.dmSans(
                                    fontSize: 11,
                                    color: const Color(0xFF94A3B8))),
                            const SizedBox(width: 4),
                            const Icon(Icons.star_rounded,
                                color: AppColors.darkAccent, size: 11),
                            const SizedBox(width: 6),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: frac,
                                  backgroundColor: AppColors.darkBorder,
                                  valueColor: const AlwaysStoppedAnimation(
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
          if (_reviews.isEmpty)
            const Text('No verified reviews yet.',
                style: TextStyle(color: AppColors.darkTextSecondary)),
          ..._reviews.map((r) => _ReviewCard(review: r)),
          if (_data!.hasMore)
            TextButton(
                onPressed: _loading ? null : () => _load(next: true),
                child: const Text('Load more reviews')),
        ],
      ]);
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final tags = (review['tags'] as List).cast<String>();
    final rating = review['stars'] as int;

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
                  ('Verified customer').substring(0, 1),
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
                    Text('Verified customer',
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: Colors.white,
                            fontWeight: FontWeight.w500)),
                    Text((review['createdAt'] as String).split('T').first,
                        style: GoogleFonts.dmSans(
                            fontSize: 11, color: const Color(0xFF94A3B8))),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.darkPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.darkPrimary.withValues(alpha: 0.3)),
                    ),
                    child: Text(tag,
                        style: GoogleFonts.dmSans(
                            fontSize: 11, color: AppColors.darkPrimary)),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
