import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';

class RateReviewScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> bid;

  const RateReviewScreen({super.key, required this.bid});

  @override
  ConsumerState<RateReviewScreen> createState() => _RateReviewScreenState();
}

class _RateReviewScreenState extends ConsumerState<RateReviewScreen>
    with SingleTickerProviderStateMixin {
  int _selectedStars = 0;
  final List<String> _selectedTags = [];
  final TextEditingController _commentController = TextEditingController();
  bool _isLoading = false;

  int _animatingStar = -1;
  late AnimationController _starAnimController;
  late Animation<double> _starScaleAnim;

  static const _tags = [
    'Professional',
    'On Time',
    'Fair Price',
    'Quality Work',
    'Friendly',
    'Clean Work',
    'Skilled',
    'Fast Service',
  ];

  @override
  void initState() {
    super.initState();
    _commentController.addListener(() => setState(() {}));

    _starAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _starScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _starAnimController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _commentController.dispose();
    _starAnimController.dispose();
    super.dispose();
  }

  String get _ratingLabel {
    switch (_selectedStars) {
      case 1:
        return 'Poor 😞';
      case 2:
        return 'Fair 😐';
      case 3:
        return 'Good 🙂';
      case 4:
        return 'Great 😊';
      case 5:
        return 'Excellent! 🌟';
      default:
        return 'Tap to rate';
    }
  }

  Future<void> _submitReview() async {
    if (_selectedStars == 0) {
      _showSnack('Please select a star rating');
      return;
    }

    setState(() => _isLoading = true);

    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');

      final jobId = widget.bid['jobId'] ?? widget.bid['_id'] ?? '';

      final dio = Dio();
      await dio.post(
        '${ApiConstants.baseUrl}/jobs/$jobId/review',
        data: {
          'stars': _selectedStars,
          'tags': _selectedTags,
          'comment': _commentController.text.trim(),
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      _showSnack('Thank you for your review! ⭐');
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) context.go('/user-home');
    } on DioException catch (e) {
      final msg = (e.response?.data as Map?)?['message'] as String? ??
          'Something went wrong';
      _showSnack(msg);
    } catch (_) {
      _showSnack('Something went wrong');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.dmSans()),
        backgroundColor: AppColors.darkSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onStarTap(int index) {
    setState(() {
      _selectedStars = index + 1;
      _animatingStar = index;
    });
    _starAnimController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final mechanicName =
        widget.bid['mechanicName'] as String? ?? 'Mechanic';
    final initials = mechanicName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    _MechanicCard(initials: initials, name: mechanicName),
                    _StarRow(
                      selectedStars: _selectedStars,
                      animatingStar: _animatingStar,
                      scaleAnim: _starScaleAnim,
                      onTap: _onStarTap,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _ratingLabel,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel('WHAT WENT WELL?'),
                    const SizedBox(height: 12),
                    _TagWrap(
                      tags: _tags,
                      selectedTags: _selectedTags,
                      onToggle: (tag) {
                        setState(() {
                          if (_selectedTags.contains(tag)) {
                            _selectedTags.remove(tag);
                          } else if (_selectedTags.length < 3) {
                            _selectedTags.add(tag);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel('ADDITIONAL COMMENTS (OPTIONAL)'),
                    const SizedBox(height: 8),
                    _CommentField(controller: _commentController),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_commentController.text.length}/300',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    OnRaastaButton(
                      label: _isLoading ? 'Submitting...' : 'Submit Review',
                      isLoading: _isLoading,
                      isDisabled: _selectedStars == 0,
                      onPressed: _submitReview,
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => context.go('/user-home'),
                      child: Text(
                        'Skip for now',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          color: const Color(0xFF94A3B8),
                          decoration: TextDecoration.underline,
                          decorationColor: const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Rate Your Experience',
            style: GoogleFonts.syne(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mechanic card ─────────────────────────────────────────────────────────────

class _MechanicCard extends StatelessWidget {
  final String initials;
  final String name;

  const _MechanicCard({required this.initials, required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: AppColors.darkPrimary,
            child: Text(
              initials,
              style: GoogleFonts.syne(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: GoogleFonts.syne(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'How was your experience?',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Star row ──────────────────────────────────────────────────────────────────

class _StarRow extends StatelessWidget {
  final int selectedStars;
  final int animatingStar;
  final Animation<double> scaleAnim;
  final void Function(int) onTap;

  const _StarRow({
    required this.selectedStars,
    required this.animatingStar,
    required this.scaleAnim,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final filled = i < selectedStars;
        final isAnimating = i == animatingStar;

        Widget star = GestureDetector(
          onTap: () => onTap(i),
          child: Icon(
            filled ? Icons.star_rounded : Icons.star_border_rounded,
            color:
                filled ? AppColors.darkAccent : const Color(0xFF1E3A5F),
            size: 48,
          ),
        );

        if (isAnimating) {
          star = AnimatedBuilder(
            animation: scaleAnim,
            builder: (_, child) =>
                Transform.scale(scale: scaleAnim.value, child: child),
            child: star,
          );
        }

        return star;
      }),
    );
  }
}

// ── Tag wrap ──────────────────────────────────────────────────────────────────

class _TagWrap extends StatelessWidget {
  final List<String> tags;
  final List<String> selectedTags;
  final void Function(String) onToggle;

  const _TagWrap({
    required this.tags,
    required this.selectedTags,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags.map((tag) {
        final selected = selectedTags.contains(tag);
        return GestureDetector(
          onTap: () => onToggle(tag),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0x262563EB)
                  : AppColors.darkSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? AppColors.darkPrimary
                    : AppColors.darkBorder,
              ),
            ),
            child: Text(
              tag,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: selected
                    ? AppColors.darkPrimary
                    : const Color(0xFF94A3B8),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Comment field ─────────────────────────────────────────────────────────────

class _CommentField extends StatelessWidget {
  final TextEditingController controller;

  const _CommentField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: TextField(
        controller: controller,
        maxLines: 4,
        maxLength: 300,
        style: GoogleFonts.dmSans(fontSize: 14, color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Share your experience...',
          hintStyle: GoogleFonts.dmSans(
            fontSize: 14,
            color: const Color(0xFF94A3B8),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(12),
          counterText: '',
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.dmSans(
        fontSize: 11,
        color: const Color(0xFF94A3B8),
        letterSpacing: 0.8,
      ),
    );
  }
}
