import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';
import '../../core/widgets/skill_chip.dart';

class MechanicProfileView extends StatefulWidget {
  final Map<String, dynamic> bid;
  const MechanicProfileView({super.key, required this.bid});

  @override
  State<MechanicProfileView> createState() => _MechanicProfileViewState();
}

class _MechanicProfileViewState extends State<MechanicProfileView> {
  int _selectedTab = 0;
  bool _accepting  = false;

  // ── Derived bid fields ────────────────────────────────────────────────────

  String get _bidId =>
      widget.bid['bidId']  as String? ??
      widget.bid['_id']    as String? ?? '';

  String get _mechanicName =>
      widget.bid['mechanicName'] as String? ?? 'Mechanic';

  double get _rating =>
      (widget.bid['rating'] as num?)?.toDouble() ?? 0.0;

  int get _totalJobs =>
      (widget.bid['totalJobs'] as num?)?.toInt() ??
      (widget.bid['jobsDone']  as num?)?.toInt() ?? 0;

  int get _totalCost =>
      (widget.bid['totalCost'] as num?)?.toInt() ?? 0;

  List<String> get _skills {
    final raw = widget.bid['skills'];
    if (raw is List) return raw.cast<String>();
    return [];
  }

  String get _initials {
    final parts = _mechanicName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return _mechanicName.isNotEmpty ? _mechanicName[0].toUpperCase() : 'M';
  }

  // ── Accept bid ────────────────────────────────────────────────────────────

  Future<void> _acceptBid() async {
    setState(() => _accepting = true);
    try {
      final storage = const FlutterSecureStorage();
      final token   = await storage.read(key: 'access_token');
      if (token == null) {
        if (!mounted) return;
        context.go('/login');
        return;
      }

      final dio = Dio(BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ));

      await dio.patch('/bids/$_bidId/accept');

      if (!mounted) return;
      context.go('/live-tracking', extra: widget.bid);
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data as Map?)?['message'] as String? ??
          'Failed to accept bid. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.darkError,
        ),
      );
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _buildSliverAppBar(),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatsRow(),
                    _buildSkillChips(),
                    _buildTabs(),
                    const SizedBox(height: 8),
                    _selectedTab == 0
                        ? _buildReviewsTab()
                        : _buildAboutTab(),
                    // Bottom bar clearance
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ],
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  // ── Sliver app bar ────────────────────────────────────────────────────────

  SliverAppBar _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: AppColors.darkBg,
      automaticallyImplyLeading: false,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: GestureDetector(
          onTap: () => context.pop(),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0x99050A14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Gradient background
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.darkBg, AppColors.darkSurface],
                ),
              ),
            ),
            // Content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 32),
                  // Avatar with verified badge
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: AppColors.darkPrimary,
                        child: Text(
                          _initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Syne',
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppColors.darkSuccess,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _mechanicName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Syne',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _skills.isNotEmpty
                        ? _skills.take(3).join(' · ')
                        : 'General Mechanic',
                    style: const TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontFamily: 'DM Sans',
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Stats row ─────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          _StatCard(
            value: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _rating.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Syne',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(Icons.star_rounded,
                    color: AppColors.darkAccent, size: 18),
              ],
            ),
            label: 'Rating',
          ),
          _StatCard(
            value: Text(
              '$_totalJobs',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Syne',
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            label: 'Jobs Done',
          ),
          _StatCard(
            value: const Text(
              '5',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Syne',
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            label: 'Years Exp',
          ),
        ],
      ),
    );
  }

  // ── Skill chips ───────────────────────────────────────────────────────────

  Widget _buildSkillChips() {
    final skills = _skills.isNotEmpty
        ? _skills
        : ['General Mechanic'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: skills
            .map((s) => SkillChip(label: s, isVerified: true))
            .toList(),
      ),
    );
  }

  // ── Tabs ──────────────────────────────────────────────────────────────────

  Widget _buildTabs() {
    const tabs = ['Reviews', 'About'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = _selectedTab == i;
          return Padding(
            padding: EdgeInsets.only(right: i == 0 ? 8.0 : 0.0),
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 9),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.darkPrimary
                      : AppColors.darkSurface,
                  border: active
                      ? null
                      : Border.all(color: AppColors.darkBorder),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    color: active
                        ? Colors.white
                        : AppColors.darkTextSecondary,
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Reviews tab ───────────────────────────────────────────────────────────

  Widget _buildReviewsTab() {
    // Fractions per star level (5→1), loosely based on the rating
    final fractions = [0.82, 0.65, 0.20, 0.08, 0.03];
    final counts    = [41, 32, 10, 4, 2];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          // Star distribution
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              border: Border.all(color: AppColors.darkBorder),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: List.generate(5, (i) {
                final star = 5 - i;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '$star★',
                          style: const TextStyle(
                            color: AppColors.darkTextSecondary,
                            fontFamily: 'DM Sans',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.darkBorder,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: fractions[i],
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.darkAccent,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${counts[i]}',
                          style: const TextStyle(
                            color: AppColors.darkTextSecondary,
                            fontFamily: 'DM Sans',
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 12),

          // Mock review cards
          ..._mockReviews(),
        ],
      ),
    );
  }

  List<Widget> _mockReviews() {
    final reviews = [
      ('Ahmad K.',  'Great mechanic! Fixed my car quickly and professionally.', '2 days ago',  5),
      ('Sara M.',   'Very knowledgeable and honest about pricing. Will use again.',  '1 week ago',  5),
      ('Fahad R.',  'Arrived on time and solved the issue in under an hour.',      '2 weeks ago', 4),
    ];

    return reviews.map((r) {
      final (name, comment, time, stars) = r;
      final initial = name[0];
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
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
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.darkBorder,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Syne',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        time,
                        style: const TextStyle(
                          color: AppColors.darkTextSecondary,
                          fontFamily: 'DM Sans',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: List.generate(
                    stars,
                    (_) => const Icon(Icons.star_rounded,
                        color: AppColors.darkAccent, size: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              comment,
              style: const TextStyle(
                color: AppColors.darkTextSecondary,
                fontFamily: 'DM Sans',
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // ── About tab ─────────────────────────────────────────────────────────────

  Widget _buildAboutTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          border: Border.all(color: AppColors.darkBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _AboutRow(
              icon: Icons.location_on_rounded,
              iconColor: AppColors.darkPrimary,
              label: 'Shop Location',
              value: 'Islamabad',
              valueColor: Colors.white,
            ),
            const Divider(color: AppColors.darkBorder, height: 20),
            _AboutRow(
              icon: Icons.access_time_rounded,
              iconColor: AppColors.darkPrimary,
              label: 'Response Time',
              value: '~15 min',
              valueColor: Colors.white,
            ),
            const Divider(color: AppColors.darkBorder, height: 20),
            _AboutRow(
              icon: Icons.verified_rounded,
              iconColor: AppColors.darkSuccess,
              label: 'Documents',
              value: 'Verified ✓',
              valueColor: AppColors.darkSuccess,
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom accept bar ─────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.darkSurface,
          border: Border(top: BorderSide(color: AppColors.darkBorder)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Bid Amount',
                      style: TextStyle(
                        color: AppColors.darkTextSecondary,
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'PKR $_totalCost',
                      style: const TextStyle(
                        color: AppColors.darkAccent,
                        fontFamily: 'Syne',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OnRaastaButton(
                    label: 'Accept This Bid →',
                    isLoading: _accepting,
                    onPressed: _acceptBid,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final Widget value;
  final String label;
  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          border: Border.all(color: AppColors.darkBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            value,
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.darkTextSecondary,
                fontFamily: 'DM Sans',
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── About row ─────────────────────────────────────────────────────────────────

class _AboutRow extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   label;
  final String   value;
  final Color    valueColor;

  const _AboutRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.darkTextSecondary,
            fontFamily: 'DM Sans',
            fontSize: 13,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontFamily: 'DM Sans',
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
