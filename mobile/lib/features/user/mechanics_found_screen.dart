import '../../models/recommendation.dart';
import '../../providers/recommendation_controller.dart';
import '../../services/ai_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';
import '../../core/widgets/skill_chip.dart';
import '../../services/auth_service.dart';

import '../../models/bid_model.dart';
import '../../models/booking_arguments.dart';
import '../../providers/job_provider.dart';
import '../../services/bidding_service.dart';
import '../../services/socket_service.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class MechanicsFoundScreen extends StatefulWidget {
  final Map<String, dynamic> job;

  const MechanicsFoundScreen(
      {super.key, required this.job, this.bidding, this.ai});
  final BiddingService? bidding;
  final AiService? ai;

  @override
  State<MechanicsFoundScreen> createState() => _MechanicsFoundScreenState();
}

class _MechanicsFoundScreenState extends State<MechanicsFoundScreen>
    with WidgetsBindingObserver {
  late final JobBidsController _controller;
  late final RecommendationController _recommendations;
  BiddingService get _bidding => widget.bidding ?? BiddingService.instance;
  List<BidModel> get _bids => _controller.bids;
  int _selectedTab = 0;
  bool _isAccepting = false;
  static const _tabLabels = ['Recommended', 'Cheapest', 'Fastest'];

  List<BidModel> get _sortedBids =>
      sortedOffers(_bids, _selectedTab, _recommendations.rankings);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recommendations = RecommendationController(
        jobId: objectId(widget.job['_id']) ?? '',
        load: (widget.ai ?? AiService.instance).recommendations)
      ..addListener(_rankingUpdated);
    _controller = JobBidsController(
        jobId: objectId(widget.job['_id']) ?? '', load: _bidding.loadBids);
    _controller.addListener(_updated);
    SocketService().on('bid:new', _onBid);
    SocketService().on('job:status_changed', _onStatus);
    SocketService().on('bid:accepted', _onStatus);
    SocketService().on('connect', _onReconnect);
    _connectSocket();
    _controller.refresh();
  }

  void _updated() {
    _recommendations.updateBids(_controller.bids);
    if (mounted) setState(() {});
  }

  void _rankingUpdated() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshAll() async {
    await _controller.refresh();
    if (mounted && _bids.any((b) => b.canAccept)) {
      await _recommendations.refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAll();
  }

  void _onReconnect(dynamic _) => _refreshAll();
  void _onBid(dynamic data) => _controller.receive(data);
  void _onStatus(dynamic data) {
    if (objectId(objectMap(data)['jobId']) == _controller.jobId) {
      _recommendations.invalidate();
      _refreshAll();
    }
  }

  Future<void> _connectSocket() async {
    final token = await AuthService.instance.getAccessToken();
    if (mounted && token != null && token.isNotEmpty) {
      SocketService().connect(token);
    }
    // R02 joins the authenticated personal room on the server.
  }

  @override
  void dispose() {
    SocketService().off('bid:new', _onBid);
    SocketService().off('job:status_changed', _onStatus);
    SocketService().off('bid:accepted', _onStatus);
    SocketService().off('connect', _onReconnect);
    WidgetsBinding.instance.removeObserver(this);
    _recommendations.removeListener(_rankingUpdated);
    _recommendations.dispose();
    _controller.removeListener(_updated);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _viewProfile(BidModel bid) async {
    await context.push('/mechanic-profile',
        extra: BidSelection(job: widget.job, bid: bid));
    if (mounted) _refreshAll();
  }

  Future<void> _acceptBid(BidModel bid) async {
    if (_isAccepting) return;
    setState(() => _isAccepting = true);
    try {
      final booking =
          await _bidding.accept(BidSelection(job: widget.job, bid: bid));
      if (!mounted || booking == null) return;
      await context.push('/live-tracking', extra: booking);
      if (mounted) _controller.refresh();
    } on BidFlowException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message), backgroundColor: AppColors.darkError));
      if (e.statusCode == 401) {
        context.go('/login');
      } else {
        _controller.refresh();
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

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
    final ranked = {
      for (final rank in _recommendations.rankings) rank.bidId: rank
    };

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
                  const Spacer(),
                  IconButton(
                      tooltip: 'Refresh bids',
                      onPressed: _refreshAll,
                      icon: const Icon(Icons.refresh, color: Colors.white)),
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
          if (_selectedTab == 0 && _bids.isNotEmpty)
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          _recommendations.loading
                              ? 'Calculating ranking. Offers remain available in bid ID order.'
                              : _recommendations.error ??
                                  (_recommendations.rankings.isEmpty
                                      ? 'No eligible offers ranked. Offers shown in bid ID order.'
                                      : 'Weighted recommendation rules: skill, straight-line distance, rating and price. Unranked offers follow in bid ID order.'),
                          style: TextStyle(
                              color: _recommendations.error == null
                                  ? AppColors.darkTextSecondary
                                  : AppColors.darkWarning,
                              fontSize: 12)),
                      if (_recommendations.truncated)
                        const Text(
                            'Ranking covers a bounded candidate snapshot; additional offers may be unranked.',
                            style: TextStyle(
                                color: AppColors.darkTextSecondary,
                                fontSize: 12)),
                      if (!_recommendations.loading)
                        TextButton(
                            onPressed: _recommendations.refresh,
                            child: const Text('Retry Ranking')),
                    ])),
          if (_controller.loading) const LinearProgressIndicator(),
          if (_controller.error != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_controller.error!,
                    style: const TextStyle(color: AppColors.darkError))),
          Expanded(
            child: sorted.isEmpty
                ? _controller.loading
                    ? const Center(child: CircularProgressIndicator())
                    : _EmptyState(onRefresh: _controller.refresh)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: sorted.length,
                    itemBuilder: (_, index) => _BidCard(
                      bid: sorted[index],
                      recommendation: ranked[sorted[index].bidId],
                      explain: _selectedTab == 0,
                      isAccepting: _isAccepting,
                      initials: _initials(sorted[index].mechanicName),
                      onAccept: sorted[index].canAccept ||
                              sorted[index].status == 'accepted'
                          ? () => _acceptBid(sorted[index])
                          : null,
                      onViewProfile: () => _viewProfile(sorted[index]),
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
  final BidModel bid;
  final Recommendation? recommendation;
  final bool explain;
  final bool isAccepting;
  final String initials;
  final VoidCallback? onAccept;
  final VoidCallback onViewProfile;

  const _BidCard({
    required this.bid,
    this.recommendation,
    this.explain = false,
    required this.isAccepting,
    required this.initials,
    required this.onAccept,
    required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    final visibleSkills =
        (recommendation?.skills ?? bid.skills).take(2).toList();

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
                          recommendation == null
                              ? bid.ratingLabel
                              : recommendation!.rating?.toStringAsFixed(1) ??
                                  'Unrated',
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
                    bid.priceLabel,
                    style: const TextStyle(
                      color: AppColors.darkAccent,
                      fontFamily: 'Syne',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    bid.etaLabel,
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

          if (recommendation != null) ...[
            const SizedBox(height: 8),
            Text(
                '${recommendation!.distanceKm.toStringAsFixed(2)} km straight-line (presence snapshot)',
                style: const TextStyle(
                    color: AppColors.darkTextSecondary, fontSize: 12)),
            if (explain)
              Text(recommendation!.explanation,
                  style: const TextStyle(
                      color: AppColors.darkTextSecondary, fontSize: 12)),
          ],
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
                  label: bid.status == 'accepted'
                      ? 'View Booking'
                      : bid.status == 'pending'
                          ? 'Accept Bid'
                          : bid.status ?? 'Unavailable',
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
  final VoidCallback onRefresh;
  const _EmptyState({required this.onRefresh});
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('No bids yet. New offers will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.darkTextSecondary, fontFamily: 'DM Sans')),
        TextButton(onPressed: onRefresh, child: const Text('Refresh bids')),
      ]));
}
