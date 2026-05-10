import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';
import '../../core/widgets/skill_chip.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class BidCard {
  final String bidId;
  final String mechanicId;
  final String mechanicName;
  final int totalCost;
  final int labourCost;
  final int partsCost;
  final int eta;
  final double rating;
  final String distance;
  final List<String> skills;
  bool isNew;
  final String status;

  BidCard({
    required this.bidId,
    required this.mechanicId,
    required this.mechanicName,
    required this.totalCost,
    required this.labourCost,
    required this.partsCost,
    required this.eta,
    required this.rating,
    required this.distance,
    required this.skills,
    this.isNew = false,
    required this.status,
  });

  factory BidCard.fromJson(Map<String, dynamic> json) {
    final mechanic = json['mechanic'] as Map<String, dynamic>? ?? {};
    final user = mechanic['userId'] as Map<String, dynamic>?;
    final name = user?['name'] as String? ??
        mechanic['name'] as String? ??
        json['mechanicName'] as String? ??
        'Mechanic';

    final skillsRaw = mechanic['skills'] as List? ?? json['skills'] as List? ?? [];
    final skills = skillsRaw.map((s) => s.toString()).toList();

    final dist = mechanic['distance'] as num? ?? json['distance'] as num? ?? 0;
    final distStr = '${dist.toStringAsFixed(1)} km';

    return BidCard(
      bidId:      json['_id'] as String?         ?? json['bidId'] as String? ?? '',
      mechanicId: json['mechanicId'] as String?  ?? mechanic['_id'] as String? ?? '',
      mechanicName: name,
      totalCost:  (json['totalCost']  as num?)?.toInt() ?? 0,
      labourCost: (json['labourCost'] as num?)?.toInt() ?? 0,
      partsCost:  (json['partsCost']  as num?)?.toInt() ?? 0,
      eta:        (json['eta']        as num?)?.toInt() ?? 0,
      rating:     (mechanic['rating'] as num?)?.toDouble() ?? 0.0,
      distance:   distStr,
      skills:     skills,
      isNew:      json['isNew'] as bool? ?? false,
      status:     json['status'] as String? ?? 'pending',
    );
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class MechanicsFoundScreen extends StatefulWidget {
  final Map<String, dynamic> job;

  const MechanicsFoundScreen({super.key, required this.job});

  @override
  State<MechanicsFoundScreen> createState() => _MechanicsFoundScreenState();
}

class _MechanicsFoundScreenState extends State<MechanicsFoundScreen> {
  final List<BidCard> _bids = [];
  int _selectedTab = 0;
  bool _isAccepting = false;

  static const _tabLabels = ['Recommended', 'Cheapest', 'Fastest'];

  List<BidCard> get _sortedBids {
    final copy = List<BidCard>.from(_bids);
    switch (_selectedTab) {
      case 1:
        copy.sort((a, b) => a.totalCost.compareTo(b.totalCost));
      case 2:
        copy.sort((a, b) => a.eta.compareTo(b.eta));
      default:
        copy.sort((a, b) => b.rating.compareTo(a.rating));
    }
    return copy;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _connectSocket();
    _loadExistingBids();
  }

  @override
  void dispose() {
    SocketService.instance.off('bid:new');
    super.dispose();
  }

  // ── Socket ────────────────────────────────────────────────────────────────────

  Future<void> _connectSocket() async {
    final token = await AuthService.instance.getAccessToken();
    if (token != null) {
      SocketService.instance.connect(token);
    }

    SocketService.instance.on('bid:new', (data) {
      final raw = data is Map ? Map<String, dynamic>.from(data as Map) : <String, dynamic>{};
      final newBid = BidCard.fromJson(raw)..isNew = true;

      // Only add if it belongs to this job
      final jobId = widget.job['_id'] as String? ?? '';
      final bidJobId = raw['jobId'] as String? ?? '';
      if (bidJobId != jobId) return;

      setState(() => _bids.insert(0, newBid));

      // Clear "NEW" badge after 30 s
      Future.delayed(const Duration(seconds: 30), () {
        if (!mounted) return;
        setState(() => newBid.isNew = false);
      });
    });
  }

  // ── Load bids ─────────────────────────────────────────────────────────────────

  Future<void> _loadExistingBids() async {
    final jobId = widget.job['_id'] as String? ?? '';
    if (jobId.isEmpty) return;
    try {
      final res = await ApiService.instance.dio.get(
        '/bids',
        queryParameters: {'jobId': jobId},
      );
      final list = (res.data['data'] as List?) ?? [];
      setState(() {
        _bids.addAll(list.map(
          (e) => BidCard.fromJson(Map<String, dynamic>.from(e as Map)),
        ));
      });
    } on DioException catch (_) {
      // silent — socket will deliver incoming bids
    }
  }

  // ── Accept bid ────────────────────────────────────────────────────────────────

  Future<void> _acceptBid(BidCard bid) async {
    setState(() => _isAccepting = true);
    try {
      await ApiService.instance.dio.patch('/bids/${bid.bidId}/accept');
      if (!mounted) return;
      context.go('/live-tracking', extra: {
        'job': widget.job,
        'bid': bid,
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data?['message'] as String? ??
          'Failed to accept bid. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.darkError),
      );
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String _initials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts.isNotEmpty ? parts[0][0].toUpperCase() : '?';
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedBids;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar ──────────────────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
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
                        border: Border.all(color: AppColors.darkBorder),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mechanics Found',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Syne',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${_bids.length} bid${_bids.length == 1 ? '' : 's'} received',
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
          ),

          // ── Sort tabs ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: List.generate(_tabLabels.length, (i) {
                final active = _selectedTab == i;
                return Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 8.0 : 0.0),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedTab = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
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
                        _tabLabels[i],
                        style: TextStyle(
                          color: active
                              ? Colors.white
                              : AppColors.darkTextSecondary,
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // ── Bids list / empty state ──────────────────────────────────────────
          Expanded(
            child: sorted.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: sorted.length,
                    itemBuilder: (_, index) =>
                        _BidCard(
                          bid: sorted[index],
                          isAccepting: _isAccepting,
                          initials: _initials(sorted[index].mechanicName),
                          onAccept: () => _acceptBid(sorted[index]),
                          onViewProfile: () => context.push(
                            '/mechanic-profile',
                            extra: sorted[index],
                          ),
                        ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Bid card widget ───────────────────────────────────────────────────────────

class _BidCard extends StatelessWidget {
  final BidCard bid;
  final bool isAccepting;
  final String initials;
  final VoidCallback onAccept;
  final VoidCallback onViewProfile;

  const _BidCard({
    required this.bid,
    required this.isAccepting,
    required this.initials,
    required this.onAccept,
    required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    final visibleSkills = bid.skills.take(2).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        border: Border.all(color: AppColors.darkBorder),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          // ── Top row: avatar + info + price ─────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.darkPrimary,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Syne',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Name + rating + skills
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bid.mechanicName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Syne',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: AppColors.darkAccent, size: 14),
                        const SizedBox(width: 3),
                        Text(
                          bid.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            color: AppColors.darkTextSecondary,
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                          ),
                        ),
                        const Text(
                          ' • ',
                          style: TextStyle(
                              color: AppColors.darkTextSecondary,
                              fontSize: 13),
                        ),
                        Text(
                          bid.distance,
                          style: const TextStyle(
                            color: AppColors.darkTextSecondary,
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    if (visibleSkills.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: visibleSkills
                            .map((s) => SkillChip(label: s))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),

              // Price + NEW badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (bid.isNew)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.darkAccent.withOpacity(0.15),
                        border: Border.all(color: AppColors.darkAccent),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: AppColors.darkAccent,
                          fontFamily: 'DM Sans',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'PKR ${bid.totalCost}',
                    style: const TextStyle(
                      color: AppColors.darkAccent,
                      fontFamily: 'Syne',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'ETA ${bid.eta} min',
                    style: const TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: AppColors.darkBorder, height: 1),
          const SizedBox(height: 12),

          // ── Action buttons ──────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OnRaastaButton(
                  label: 'View Profile',
                  isPrimary: false,
                  onPressed: onViewProfile,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OnRaastaButton(
                  label: 'Accept Bid',
                  isLoading: isAccepting,
                  onPressed: onAccept,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.darkPrimary),
          SizedBox(height: 16),
          Text(
            'Waiting for mechanics...',
            style: TextStyle(
              color: AppColors.darkTextSecondary,
              fontFamily: 'DM Sans',
              fontSize: 14,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Nearby mechanics are being notified',
            style: TextStyle(
              color: AppColors.darkTextSecondary,
              fontFamily: 'DM Sans',
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
