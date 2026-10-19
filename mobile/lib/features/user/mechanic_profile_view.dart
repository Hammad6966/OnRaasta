import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/bid_model.dart';
import '../../models/booking_arguments.dart';
import '../../services/bidding_service.dart';
import '../../services/review_service.dart';
import '../../services/socket_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';
import '../../core/widgets/skill_chip.dart';
import '../../core/widgets/mechanic_reviews_panel.dart';

class MechanicProfileView extends StatefulWidget {
  final BidSelection selection;
  const MechanicProfileView({super.key, required this.selection});

  @override
  State<MechanicProfileView> createState() => _MechanicProfileViewState();
}

class _MechanicProfileViewState extends State<MechanicProfileView> {
  int _selectedTab = 0;
  ReviewPage? _reputation;
  bool _accepting = false;

  late BidModel _bid;
  bool _loading = false;
  bool _available = true;
  int _refreshGeneration = 0;
  String? _error;
  String get _mechanicName => _bid.mechanicName;
  List<String> get _skills => _bid.skills;

  @override
  void initState() {
    super.initState();
    _bid = widget.selection.bid;
    SocketService().on('bid:accepted', _onAssigned);
    SocketService().on('connect', _onConnect);
    _refresh();
  }

  void _onAssigned(dynamic data) {
    if (objectId(objectMap(data)['jobId']) == _bid.jobId) _refresh();
  }

  void _onConnect(dynamic _) {
    _refresh();
  }

  @override
  void dispose() {
    ++_refreshGeneration;
    SocketService().off('bid:accepted', _onAssigned);
    SocketService().off('connect', _onConnect);
    super.dispose();
  }

  Future<void> _refresh() async {
    final generation = ++_refreshGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bids = await BiddingService.instance.loadBids(_bid.jobId);
      if (!mounted || generation != _refreshGeneration) return;
      final matches = bids.where((b) => b.bidId == _bid.bidId);
      if (matches.isEmpty) {
        setState(() {
          _available = false;
          _error = 'This bid is no longer available.';
        });
      } else {
        setState(() {
          _available = true;
          _bid = _bid.merge(matches.first);
        });
      }
    } on BidFlowException catch (e) {
      if (mounted && generation == _refreshGeneration) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted && generation == _refreshGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  String get _initials {
    final parts = _mechanicName
        .trim()
        .split(' ')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return _mechanicName.isNotEmpty ? _mechanicName[0].toUpperCase() : 'M';
  }

  // ── Accept bid ────────────────────────────────────────────────────────────

  Future<void> _acceptBid() async {
    if (_accepting || !_available) return;
    setState(() => _accepting = true);
    try {
      final booking = await BiddingService.instance
          .accept(BidSelection(job: widget.selection.job, bid: _bid));
      if (!mounted || booking == null) return;
      await context.push('/live-tracking', extra: booking);
      if (mounted) _refresh();
    } on BidFlowException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message), backgroundColor: AppColors.darkError));
      if (e.statusCode == 401) {
        context.go('/login');
      } else {
        _refresh();
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

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
                    if (_loading) const LinearProgressIndicator(),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_error!,
                              style:
                                  const TextStyle(color: AppColors.darkError))),
                    TextButton(
                        onPressed: _refresh,
                        child: const Text('Refresh profile')),
                    _buildStatsRow(),
                    _buildSkillChips(),
                    _buildTabs(),
                    const SizedBox(height: 8),
                    _selectedTab == 0 ? _buildReviewsTab() : _buildAboutTab(),
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
                      if (_bid.isApproved == true)
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
                        : 'Skills unavailable',
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
                  _reputation == null
                      ? _bid.ratingLabel
                      : _reputation!.rating.toStringAsFixed(1),
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
              _bid.totalJobs?.toString() ?? '?',
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
            value: Text(
              _bid.eta?.toString() ?? '?',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Syne',
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            label: 'ETA (min)',
          ),
        ],
      ),
    );
  }

  // ── Skill chips ───────────────────────────────────────────────────────────

  Widget _buildSkillChips() {
    final skills = _skills;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: skills.map((s) => SkillChip(label: s)).toList(),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                decoration: BoxDecoration(
                  color: active ? AppColors.darkPrimary : AppColors.darkSurface,
                  border:
                      active ? null : Border.all(color: AppColors.darkBorder),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    color: active ? Colors.white : AppColors.darkTextSecondary,
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

  Widget _buildReviewsTab() => Padding(
      padding: const EdgeInsets.all(16),
      child: MechanicReviewsPanel(
          mechanicId: _bid.mechanicId,
          onLoaded: (value) {
            if (mounted) setState(() => _reputation = value);
          }));

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
              value: _bid.shopAddress ?? 'Unavailable',
              valueColor: Colors.white,
            ),
            const Divider(color: AppColors.darkBorder, height: 20),
            _AboutRow(
              icon: Icons.access_time_rounded,
              iconColor: AppColors.darkPrimary,
              label: 'Offer ETA',
              value: _bid.eta == null ? 'Unavailable' : '${_bid.eta} min',
              valueColor: Colors.white,
            ),
            const Divider(color: AppColors.darkBorder, height: 20),
            _AboutRow(
              icon: Icons.verified_rounded,
              iconColor: AppColors.darkSuccess,
              label: 'Approval',
              value: _bid.isApproved == null
                  ? 'Unavailable'
                  : _bid.isApproved!
                      ? 'Approved'
                      : 'Not approved',
              valueColor: _bid.isApproved == true
                  ? AppColors.darkSuccess
                  : AppColors.darkTextSecondary,
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
                      _bid.priceLabel,
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
                    label: _bid.status == 'accepted'
                        ? 'View Booking'
                        : _bid.status == 'pending'
                            ? 'Accept This Bid →'
                            : _bid.status ?? 'Unavailable',
                    isLoading: _accepting,
                    onPressed: _available &&
                            (_bid.canAccept || _bid.status == 'accepted')
                        ? _acceptBid
                        : null,
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
  final Color iconColor;
  final String label;
  final String value;
  final Color valueColor;

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
        const SizedBox(width: 12),
        Expanded(
            child: Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: valueColor,
            fontFamily: 'DM Sans',
            fontSize: 13,
          ),
        )),
      ],
    );
  }
}
