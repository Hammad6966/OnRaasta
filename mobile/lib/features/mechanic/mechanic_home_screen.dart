import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';

// ── Job request model ─────────────────────────────────────────────────────────

class JobRequest {
  final String jobId;
  final String description;
  final double distance;
  final DateTime createdAt;
  final Map<String, dynamic>? aiDiagnosis;

  JobRequest({
    required this.jobId,
    required this.description,
    required this.distance,
    required this.createdAt,
    this.aiDiagnosis,
  });

  factory JobRequest.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['createdAt'] as String?;
    return JobRequest(
      jobId:       json['jobId']       as String? ?? json['_id'] as String? ?? '',
      description: json['description'] as String? ?? 'Job request',
      distance:    (json['distance']   as num?)?.toDouble() ?? 0.0,
      createdAt:   createdAtRaw != null
          ? DateTime.tryParse(createdAtRaw) ?? DateTime.now()
          : DateTime.now(),
      aiDiagnosis: json['aiDiagnosis'] as Map<String, dynamic>?,
    );
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  String? get faultLabel =>
      (aiDiagnosis?['fault_class'] as String?)?.replaceAll('_', ' ');
  String? get costMin => aiDiagnosis?['cost_min']?.toString();
  String? get costMax => aiDiagnosis?['cost_max']?.toString();

  Map<String, dynamic> toJson() => {
        'jobId':       jobId,
        'description': description,
        'distance':    distance,
        'createdAt':   createdAt.toIso8601String(),
        'aiDiagnosis': aiDiagnosis,
      };
}

// ── Screen ────────────────────────────────────────────────────────────────────

class MechanicHomeScreen extends StatefulWidget {
  const MechanicHomeScreen({super.key});

  @override
  State<MechanicHomeScreen> createState() => _MechanicHomeScreenState();
}

class _MechanicHomeScreenState extends State<MechanicHomeScreen> {
  bool _isOnline = false;
  String _mechanicName = '';
  String _mechanicId = '';
  final List<JobRequest> _jobs = [];
  int _selectedTab = 0;
  int _totalJobs = 0;
  double _rating = 0.0;
  int _earnings = 0;

  static const _tabLabels = ['New Requests', 'Active Jobs'];

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _connectSocket();
  }

  @override
  void dispose() {
    SocketService.instance.off('job:new_request');
    super.dispose();
  }

  // ── Profile ───────────────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    try {
      final res = await ApiService.instance.dio.get('/mechanics/profile');
      final data = res.data['data'] as Map<String, dynamic>;
      final user = data['userId'] as Map<String, dynamic>?;
      setState(() {
        _mechanicId   = data['_id']      as String? ?? '';
        _totalJobs    = (data['totalJobs'] as num?)?.toInt()    ?? 0;
        _rating       = (data['rating']    as num?)?.toDouble() ?? 0.0;
        _earnings     = (data['earnings']  as num?)?.toInt()    ?? 0;
        _mechanicName = user?['name']      as String? ?? 'Mechanic';
      });
    } catch (_) {}
  }

  // ── Socket ────────────────────────────────────────────────────────────────────

  Future<void> _connectSocket() async {
    final token = await AuthService.instance.getAccessToken();
    if (token != null) {
      SocketService.instance.connect(token);
    }

    SocketService.instance.on('job:new_request', (data) {
      if (!mounted) return;
      final raw = data is Map
          ? Map<String, dynamic>.from(data as Map)
          : <String, dynamic>{};
      setState(() => _jobs.insert(0, JobRequest.fromJson(raw)));
    });
  }

  // ── Online toggle ─────────────────────────────────────────────────────────────

  Future<void> _toggleOnline() async {
    final goingOnline = !_isOnline;
    setState(() => _isOnline = goingOnline);

    if (goingOnline) {
      double lat = 0.0, lng = 0.0;
      try {
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm != LocationPermission.denied &&
            perm != LocationPermission.deniedForever) {
          final pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high);
          lat = pos.latitude;
          lng = pos.longitude;
        }
      } catch (_) {}

      SocketService.instance.emit('mechanic:go_online', {
        'mechanicId': _mechanicId,
        'lat':        lat,
        'lng':        lng,
      });
    } else {
      SocketService.instance.emit('mechanic:go_offline', {
        'mechanicId': _mechanicId,
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final displayJobs = _selectedTab == 0 ? _jobs : <JobRequest>[];

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar ────────────────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'OnRaasta',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Syne',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Welcome, $_mechanicName',
                        style: const TextStyle(
                          color: AppColors.darkTextSecondary,
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Logout
                  IconButton(
                    onPressed: () async {
                      await const FlutterSecureStorage().deleteAll();
                      if (!mounted) return;
                      context.go('/splash');
                    },
                    icon: const Icon(Icons.logout_rounded,
                        color: AppColors.darkTextSecondary, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),

                  // Online / offline toggle
                  Row(
                    children: [
                      Text(
                        _isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: _isOnline
                              ? AppColors.darkSuccess
                              : AppColors.darkTextSecondary,
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _toggleOnline,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 52,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _isOnline
                                ? AppColors.darkSuccess
                                : AppColors.darkBorder,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Stack(
                            children: [
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                                left: _isOnline ? 26.0 : 2.0,
                                top: 2,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Stats row ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _StatCard(
                    value: '$_totalJobs', label: 'Jobs Done'),
                _StatCard(
                    value: _rating.toStringAsFixed(1), label: 'Rating'),
                _StatCard(
                    value: 'PKR $_earnings', label: 'PKR Earned'),
              ],
            ),
          ),

          // ── Tabs ───────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: List.generate(_tabLabels.length, (i) {
                final active = _selectedTab == i;
                return Padding(
                  padding: EdgeInsets.only(right: i == 0 ? 8.0 : 0.0),
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

          const SizedBox(height: 4),

          // ── Job feed / empty state ─────────────────────────────────────────
          Expanded(
            child: displayJobs.isEmpty
                ? _EmptyState(isOnline: _isOnline)
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: displayJobs.length,
                    itemBuilder: (_, i) => _JobRequestCard(
                      job: displayJobs[i],
                      onViewDetails: () => context.push(
                          '/new-request-detail',
                          extra: displayJobs[i].toJson()),
                      onPlaceBid: () => context.push(
                          '/submit-bid',
                          extra: displayJobs[i].toJson()),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          border: Border.all(color: AppColors.darkBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Syne',
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.darkTextSecondary,
                fontFamily: 'DM Sans',
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Job request card ──────────────────────────────────────────────────────────

class _JobRequestCard extends StatelessWidget {
  final JobRequest job;
  final VoidCallback onViewDetails;
  final VoidCallback onPlaceBid;

  const _JobRequestCard({
    required this.job,
    required this.onViewDetails,
    required this.onPlaceBid,
  });

  @override
  Widget build(BuildContext context) {
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
          // ── Info row ──────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0x262563EB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.car_repair_rounded,
                    color: AppColors.darkPrimary, size: 24),
              ),
              const SizedBox(width: 12),

              // Description + meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.description,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'DM Sans',
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            color: AppColors.darkTextSecondary, size: 14),
                        const SizedBox(width: 3),
                        Text(
                          '${job.distance.toStringAsFixed(1)} km away',
                          style: const TextStyle(
                            color: AppColors.darkTextSecondary,
                            fontFamily: 'DM Sans',
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded,
                            color: AppColors.darkTextSecondary, size: 14),
                        const SizedBox(width: 3),
                        Text(
                          job.timeAgo,
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
              ),

              // AI diagnosis badge + cost
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (job.faultLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.darkAccent.withOpacity(0.15),
                        border: Border.all(color: AppColors.darkAccent),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        job.faultLabel!,
                        style: const TextStyle(
                          color: AppColors.darkAccent,
                          fontFamily: 'DM Sans',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'PKR ${job.costMin ?? '?'}-${job.costMax ?? '?'}',
                    style: const TextStyle(
                      color: AppColors.darkAccent,
                      fontFamily: 'Syne',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: AppColors.darkBorder, height: 1),
          const SizedBox(height: 12),

          // ── Action buttons ─────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OnRaastaButton(
                  label: 'View Details',
                  isPrimary: false,
                  onPressed: onViewDetails,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OnRaastaButton(
                  label: 'Place Bid',
                  onPressed: onPlaceBid,
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
  final bool isOnline;
  const _EmptyState({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded,
              color: AppColors.darkBorder, size: 64),
          const SizedBox(height: 16),
          Text(
            isOnline ? 'No new requests nearby' : 'You are offline',
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Syne',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isOnline
                ? 'New jobs will appear here when users need help'
                : 'Go online to start receiving job requests',
            style: const TextStyle(
              color: AppColors.darkTextSecondary,
              fontFamily: 'DM Sans',
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
