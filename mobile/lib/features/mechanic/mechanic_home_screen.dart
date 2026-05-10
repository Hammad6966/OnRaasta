import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';

// ── Dark map style ─────────────────────────────────────────────────────────────

const _darkMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#050A14"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#94A3B8"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#050A14"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#0F2040"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#1E3A5F"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0D1B2E"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]}
]''';

// ── Job request model ─────────────────────────────────────────────────────────

class JobRequest {
  final String jobId;
  final String description;
  final double distance;
  final DateTime createdAt;
  final Map<String, dynamic>? aiDiagnosis;
  bool isNew;

  JobRequest({
    required this.jobId,
    required this.description,
    required this.distance,
    required this.createdAt,
    this.aiDiagnosis,
    this.isNew = false,
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
      isNew:       true,
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
  String _mechanicId   = '';
  int    _totalJobs    = 0;
  double _rating       = 0.0;
  int    _earnings     = 0;

  final List<JobRequest> _jobs = [];

  GoogleMapController? _mapController;
  LatLng? _currentLocation;

  static const LatLng _fallback = LatLng(33.6844, 73.0479); // Islamabad

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _connectSocket();
    _initLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    SocketService.instance.off('job:new_request');
    super.dispose();
  }

  // ── Location ──────────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final loc = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _currentLocation = loc);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(loc, 14));
    } catch (_) {}
  }

  // ── Profile ───────────────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    try {
      final res  = await ApiService.instance.dio.get('/mechanics/profile');
      final data = res.data['data'] as Map<String, dynamic>;
      final user = data['userId'] as Map<String, dynamic>?;
      setState(() {
        _mechanicId   = data['_id']       as String? ?? '';
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
    if (token != null) SocketService.instance.connect(token);

    SocketService.instance.on('job:new_request', (data) {
      if (!mounted) return;
      final raw = data is Map
          ? Map<String, dynamic>.from(data as Map)
          : <String, dynamic>{};
      final job = JobRequest.fromJson(raw);
      setState(() => _jobs.insert(0, job));
      // Clear NEW badge after 30s
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted) setState(() => job.isNew = false);
      });
    });
  }

  // ── Online toggle ─────────────────────────────────────────────────────────────

  Future<void> _toggleOnline() async {
    final goingOnline = !_isOnline;
    setState(() => _isOnline = goingOnline);

    if (goingOnline) {
      double lat = _currentLocation?.latitude  ?? 0.0;
      double lng = _currentLocation?.longitude ?? 0.0;

      if (lat == 0.0) {
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
            if (mounted) {
              setState(() => _currentLocation = LatLng(lat, lng));
            }
          }
        } catch (_) {}
      }

      SocketService.instance.emit('mechanic:go_online', {
        'mechanicId': _mechanicId,
        'lat': lat,
        'lng': lng,
      });
    } else {
      SocketService.instance.emit('mechanic:go_offline', {
        'mechanicId': _mechanicId,
      });
    }
  }

  // ── Map widget ────────────────────────────────────────────────────────────────

  Widget _buildMap() {
    final center = _currentLocation ?? _fallback;
    final marker = Marker(
      markerId: const MarkerId('mechanic'),
      position: center,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      infoWindow: const InfoWindow(title: 'You'),
    );

    return SizedBox(
      height: 280,
      child: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 14),
            markers: {marker},
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            onMapCreated: (c) async {
              _mapController = c;
              await c.setMapStyle(_darkMapStyle);
              if (_currentLocation != null) {
                c.animateCamera(
                    CameraUpdate.newLatLngZoom(_currentLocation!, 14));
              }
            },
          ),

          // Top-left: online status pill
          Positioned(
            top: 12,
            left: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xD9050A14),
                border: Border.all(
                    color: AppColors.darkSuccess.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.darkSuccess,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Online · Islamabad',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'DM Sans',
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Top-right: notification icon
          Positioned(
            top: 12,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xD9050A14),
                border: Border.all(color: AppColors.darkBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.notifications_outlined,
                  color: Colors.white, size: 20),
            ),
          ),

          // Bottom-left: active requests count
          Positioned(
            bottom: 10,
            left: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xD9050A14),
                border: Border.all(color: AppColors.darkBorder),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_jobs.length} active requests nearby',
                style: const TextStyle(
                  color: AppColors.darkAccent,
                  fontFamily: 'DM Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Online bar ────────────────────────────────────────────────────────────────

  Widget _buildOnlineBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.darkSuccess.withOpacity(0.08),
          border: Border.all(
              color: AppColors.darkSuccess.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Status text
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.darkSuccess,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isOnline ? "You're Online" : "You're Offline",
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _isOnline
                          ? 'Receiving job requests'
                          : 'Go online to receive jobs',
                      style: const TextStyle(
                        color: AppColors.darkTextSecondary,
                        fontFamily: 'DM Sans',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            // Toggle
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
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
              child: Row(
                children: [
                  const Text(
                    'OnRaasta',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Syne',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (_mechanicName.isNotEmpty)
                    Text(
                      _mechanicName,
                      style: const TextStyle(
                        color: AppColors.darkTextSecondary,
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () async {
                      await const FlutterSecureStorage().deleteAll();
                      if (!mounted) return;
                      context.go('/splash');
                    },
                    icon: const Icon(Icons.logout_rounded,
                        color: AppColors.darkTextSecondary, size: 22),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // ── Map ──────────────────────────────────────────────────────────
            _buildMap(),

            // ── Online bar ───────────────────────────────────────────────────
            _buildOnlineBar(),

            const SizedBox(height: 12),

            // ── Job feed ──────────────────────────────────────────────────────
            Expanded(
              child: _jobs.isEmpty
                  ? _EmptyState(isOnline: _isOnline)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _jobs.length,
                      itemBuilder: (_, i) => _JobCard(
                        job: _jobs[i],
                        onDecline: () =>
                            setState(() => _jobs.removeAt(i)),
                        onView: () => context.push(
                          '/new-request-detail',
                          extra: _jobs[i].toJson(),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Job card ──────────────────────────────────────────────────────────────────

class _JobCard extends StatelessWidget {
  final JobRequest job;
  final VoidCallback onDecline;
  final VoidCallback onView;

  const _JobCard({
    required this.job,
    required this.onDecline,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10, top: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            border: Border.all(
              color: job.isNew ? AppColors.darkAccent : AppColors.darkBorder,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.faultLabel?.toUpperCase() ??
                              'Job Request',
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Syne',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded,
                                color: AppColors.darkAccent, size: 12),
                            const SizedBox(width: 3),
                            Text(
                              '${job.distance.toStringAsFixed(1)} km away',
                              style: const TextStyle(
                                color: AppColors.darkAccent,
                                fontFamily: 'DM Sans',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    job.timeAgo,
                    style: const TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontFamily: 'DM Sans',
                      fontSize: 11,
                    ),
                  ),
                ],
              ),

              // ── Body ────────────────────────────────────────────────────────
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0x1A2563EB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text('🚗',
                          style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.description,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (job.faultLabel != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.darkAccent.withOpacity(0.08),
                              border: Border.all(
                                  color: AppColors.darkAccent
                                      .withOpacity(0.2)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🤖',
                                    style: TextStyle(fontSize: 12)),
                                const SizedBox(width: 6),
                                Text(
                                  'AI: ${job.faultLabel}',
                                  style: const TextStyle(
                                    color: AppColors.darkAccent,
                                    fontFamily: 'DM Sans',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // ── Footer ──────────────────────────────────────────────────────
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: const BoxDecoration(
                  border: Border(
                      top: BorderSide(color: AppColors.darkBorder)),
                ),
                child: Row(
                  children: [
                    // Cost pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.darkAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Est. PKR ${job.costMin ?? '?'}–${job.costMax ?? '?'}',
                        style: const TextStyle(
                          color: AppColors.darkAccent,
                          fontFamily: 'DM Sans',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Decline
                    _SmallButton(
                      label: 'Decline',
                      isPrimary: false,
                      onTap: onDecline,
                    ),
                    const SizedBox(width: 8),
                    // View
                    _SmallButton(
                      label: 'View →',
                      isPrimary: true,
                      onTap: onView,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // NEW badge
        if (job.isNew)
          Positioned(
            top: -2,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.darkAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.darkError,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'NEW',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Syne',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Small button ──────────────────────────────────────────────────────────────

class _SmallButton extends StatelessWidget {
  final String label;
  final bool isPrimary;
  final VoidCallback onTap;

  const _SmallButton({
    required this.label,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isPrimary
              ? AppColors.darkPrimary
              : Colors.transparent,
          border: isPrimary
              ? null
              : Border.all(color: AppColors.darkBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isPrimary
                ? Colors.white
                : AppColors.darkTextSecondary,
            fontFamily: 'DM Sans',
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, color: AppColors.darkBorder, size: 56),
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
      ),
    );
  }
}
