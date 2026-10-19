import '../../models/bid_model.dart';
import '../../core/widgets/assignment_panel.dart';
import '../../models/booking_arguments.dart';
import '../../providers/assignment_controller.dart';
import '../../services/assignment_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../models/job_request.dart';
export '../../models/job_request.dart' show JobRequest;
import '../../providers/mechanic_presence_controller.dart';
import '../../providers/job_tracking_publisher.dart';
import '../../services/foreground_location.dart';
import '../../services/mechanic_service.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import 'mechanic_earnings_screen.dart';
import 'mechanic_profile_edit.dart';
import '../../services/profile_service.dart';

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

class MechanicHomeScreen extends StatefulWidget {
  final MechanicPresenceController? presence;
  final AssignmentInboxController? assignments;
  final JobTrackingPublisher? tracking;
  const MechanicHomeScreen(
      {super.key, this.presence, this.assignments, this.tracking});

  @override
  State<MechanicHomeScreen> createState() => _MechanicHomeScreenState();
}

class _MechanicHomeScreenState extends State<MechanicHomeScreen>
    with WidgetsBindingObserver {
  late final MechanicPresenceController _presence;
  late final AssignmentInboxController _assignments;
  bool _openingAssignment = false;
  JobTrackingPublisher? _tracking;
  bool get _isOnline => _presence.online;
  String get _mechanicName => _presence.name;
  List<JobRequest> get _jobs => _presence.jobs;
  GoogleMapController? _mapController;
  LatLng? get _currentLocation => _presence.location == null
      ? null
      : LatLng(_presence.location!.lat, _presence.location!.lng);
  static const LatLng _fallback =
      LatLng(33.6844, 73.0479); // Viewport only, never submitted as GPS.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _presence = widget.presence ??
        MechanicPresenceController(
            socket: SocketService(),
            gps: DeviceForegroundLocation.shared,
            token: AuthService.instance.getAccessToken,
            profile: MechanicService.instance.profile,
            loadRequests: MechanicService.instance.requests);
    _assignments = widget.assignments ??
        AssignmentInboxController(
            socket: SocketService(),
            loadActive: AssignmentService.instance.recover,
            loadOne: AssignmentService.instance.load,
            onUnavailable: _presence.invalidateOpportunity);
    _assignments.refresh();
    _presence.addListener(_updated);
    _presence.initialize();
    _presence.socket.on('job:status_changed', _completedStatus);
    ProfileService.mechanicChanges.addListener(_profileChanged);
    _tracking = widget.tracking ??
        (widget.presence == null
            ? JobTrackingPublisher(
                socket: SocketService(),
                gps: DeviceForegroundLocation.shared,
                assignments: AssignmentService.instance.active,
                profile: MechanicService.instance.profile,
                token: AuthService.instance.getAccessToken)
            : null);
    if (_tracking != null) {
      JobTrackingPublisher.current = _tracking;
      _tracking!.reconcile();
    }
  }

  void _completedStatus(dynamic data) {
    if (objectMap(data)['status'] == 'completed') _presence.initialize();
  }

  void _profileChanged() {
    _presence.initialize();
    _tracking?.reconcile();
  }

  void _updated() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _assignments.refresh();
      _presence.initialize();
      _presence.setForeground(true);
      _tracking?.setForeground(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _tracking?.setForeground(false);
      _presence.setForeground(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tracking?.dispose();
    _assignments.dispose();
    _presence.removeListener(_updated);
    ProfileService.mechanicChanges.removeListener(_profileChanged);
    _presence.socket.off('job:status_changed', _completedStatus);
    _presence.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _openAssignment(AcceptedBooking booking) async {
    if (_openingAssignment) return;
    _openingAssignment = true;
    try {
      await context.push('/active-job', extra: booking);
    } finally {
      if (mounted) {
        _openingAssignment = false;
        _assignments.refresh();
      }
    }
  }

  Future<void> _toggleOnline() => _presence.toggle();

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
            markers: _currentLocation == null ? {} : {marker},
            myLocationEnabled: false,
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xD9050A14),
                border:
                    Border.all(color: AppColors.darkSuccess.withOpacity(0.3)),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          border: Border.all(color: AppColors.darkSuccess.withOpacity(0.2)),
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
              onTap: _presence.busy ||
                      _presence.loadingProfile ||
                      !_presence.approved
                  ? null
                  : _toggleOnline,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 52,
                height: 28,
                decoration: BoxDecoration(
                  color:
                      _isOnline ? AppColors.darkSuccess : AppColors.darkBorder,
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
                      await AuthService.instance.logout();
                      if (!context.mounted) return;
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
            if (_presence.completedJobs != null)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('${_presence.completedJobs} completed jobs',
                      style: const TextStyle(
                          color: AppColors.darkTextSecondary, fontSize: 11))),
            _buildMap(),

            // ── Online bar ───────────────────────────────────────────────────
            AssignmentPanel(controller: _assignments, onOpen: _openAssignment),
            _buildOnlineBar(),
            if (_presence.busy ||
                _presence.loadingProfile ||
                _presence.feedLoading)
              const LinearProgressIndicator(),
            if (_presence.error != null || _presence.feedError != null)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(_presence.error ?? _presence.feedError!,
                      style: const TextStyle(color: AppColors.darkError))),
            TextButton(
                onPressed: _presence.busy
                    ? null
                    : _presence.online
                        ? _presence.refreshRequests
                        : _presence.initialize,
                child: Text(_presence.online
                    ? 'Refresh requests'
                    : 'Refresh approval')),

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
                        onDecline: () => _presence.decline(_jobs[i].jobId),
                        onView: () => context.push(
                          '/new-request-detail',
                          extra: _jobs[i].toJson(),
                        ),
                        onActiveJob: () => context.push(
                          '/submit-bid',
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
  final VoidCallback onActiveJob;

  const _JobCard({
    required this.job,
    required this.onDecline,
    required this.onView,
    required this.onActiveJob,
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
                          job.faultLabel?.toUpperCase() ?? 'Job Request',
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
                              job.distanceLabel,
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
                      child: Text('🚗', style: TextStyle(fontSize: 18)),
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
                                  color: AppColors.darkAccent.withOpacity(0.2)),
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
                  border: Border(top: BorderSide(color: AppColors.darkBorder)),
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
                    const SizedBox(width: 8),
                    _SmallButton(
                      label: 'Submit Bid',
                      isPrimary: false,
                      onTap: onActiveJob,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.darkPrimary : Colors.transparent,
          border: isPrimary ? null : Border.all(color: AppColors.darkBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isPrimary ? Colors.white : AppColors.darkTextSecondary,
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

// ── Mechanic home wrapper (bottom nav shell) ──────────────────────────────────

class MechanicHomeWrapper extends StatefulWidget {
  const MechanicHomeWrapper({super.key});

  @override
  State<MechanicHomeWrapper> createState() => _MechanicHomeWrapperState();
}

class _MechanicHomeWrapperState extends State<MechanicHomeWrapper> {
  int _currentIndex = 0;

  static const _pages = <Widget>[
    MechanicHomeScreen(),
    MechanicEarningsScreen(),
    MechanicProfileEditScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: const Color(0xFF0F2040),
        selectedItemColor: AppColors.darkAccent,
        unselectedItemColor: const Color(0xFF94A3B8),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.payments_rounded),
            label: 'Earnings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
