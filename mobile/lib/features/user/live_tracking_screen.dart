import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/status_badge.dart';
import '../../models/bid_model.dart';
import '../../models/booking_arguments.dart';
import '../../providers/assignment_controller.dart';
import '../../providers/job_location_controller.dart';
import '../../services/job_location_service.dart';
import '../../services/assignment_service.dart';
import '../../services/socket_service.dart';
import '../../core/widgets/assignment_state_banner.dart';
import '../shared/job_contact_actions.dart';

// ── Dark map style (same as M05) ──────────────────────────────────────────────

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

// ── Screen ────────────────────────────────────────────────────────────────────

class LiveTrackingScreen extends StatefulWidget {
  final AcceptedBooking booking;
  final AssignmentDetailController? controller;
  final JobLocationController? locationController;
  const LiveTrackingScreen(
      {super.key,
      required this.booking,
      this.controller,
      this.locationController});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  bool _progressScheduled = false;
  late final JobLocationController _tracking;
  late final AssignmentDetailController _assignment;
  AcceptedBooking get _booking => _assignment.booking;

  LatLng? _userPosition;
  // A viewport fallback is not a claimed driver or mechanic position.
  static const LatLng _fallback = LatLng(33.6844, 73.0479);
  int get _currentStep => ['en_route', 'arrived', 'in_progress', 'completed']
      .indexOf(_booking.job['status'] as String);

  static const _steps = [
    (label: 'En Route', icon: Icons.directions_car_rounded),
    (label: 'Arrived', icon: Icons.place_rounded),
    (label: 'In Progress', icon: Icons.build_rounded),
    (label: 'Completed', icon: Icons.check_circle_rounded),
  ];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _assignment = widget.controller ??
        AssignmentDetailController(
            booking: widget.booking,
            socket: SocketService(),
            load: AssignmentService.instance.load);
    _tracking = widget.locationController ??
        JobLocationController(
            assignment: _assignment,
            socket: SocketService(),
            load: JobLocationService.instance.latest);
    _tracking.addListener(_locationChanged);
    _assignment.addListener(_changed);
    _assignment.reload();
    _updatePosition();
  }

  void _locationChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (mounted) {
      setState(_updatePosition);
      if (!_progressScheduled &&
          _assignment.verified &&
          !_assignment.accessDenied &&
          ['in_progress', 'completed'].contains(_booking.job['status'])) {
        _progressScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_assignment.verified &&
              !_assignment.accessDenied &&
              ['in_progress', 'completed'].contains(_booking.job['status']) &&
              (ModalRoute.of(context)?.isCurrent ?? false)) {
            context.pushReplacement('/job-in-progress', extra: _booking);
          } else {
            _progressScheduled = false;
          }
        });
      }
    }
  }

  void _updatePosition() {
    _userPosition = null;
    final location = objectMap(_booking.job['location']);
    final lat = finiteNumber(location['lat']);
    final lng = finiteNumber(location['lng']);
    if (lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180) {
      _userPosition = LatLng(lat, lng);
    }
    // The breakdown coordinate is saved data; only authorized observations move the mechanic marker.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tracking.setForeground(true);
      _assignment.reload();
    } else if ([
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached
    ].contains(state)) {
      _tracking.setForeground(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tracking.removeListener(_locationChanged);
    _tracking.dispose();
    _assignment.removeListener(_changed);
    _assignment.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _recenter() {
    final point = _tracking.location;
    final target = point == null
        ? _userPosition ?? _fallback
        : LatLng(point.lat, point.lng);
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 14));
  }

  // ── Map markers & polyline ─────────────────────────────────────────────────

  Set<Marker> get _markers {
    final user = _userPosition;
    final mechanic = _tracking.location;
    return {
      if (mechanic != null)
        Marker(
            markerId: const MarkerId('mechanic'),
            position: LatLng(mechanic.lat, mechanic.lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(30),
            infoWindow: InfoWindow(
                title: _booking.bid.mechanicName, snippet: _tracking.label)),
      if (user != null)
        Marker(
          markerId: const MarkerId('user'),
          position: user,
          icon: BitmapDescriptor.defaultMarkerWithHue(210),
          infoWindow: const InfoWindow(title: 'Breakdown location'),
          zIndex: 2,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final center = _userPosition ?? _fallback;

    if (_assignment.accessDenied) {
      return Scaffold(
          backgroundColor: AppColors.darkBg,
          body:
              SafeArea(child: AssignmentStateBanner(controller: _assignment)));
    }
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Stack(
        children: [
          // ── Layer 1: Fullscreen map ────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 14),
            markers: _markers,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            onMapCreated: (c) async {
              _mapController = c;
              await c.setMapStyle(_darkMapStyle);
              if (_userPosition != null) {
                c.animateCamera(CameraUpdate.newLatLngZoom(_userPosition!, 14));
              }
            },
          ),

          // ── Layer 2: Top status bar ────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                color: const Color(0xE6050A14),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.darkSurface,
                          border: Border.all(color: AppColors.darkBorder),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _booking.job['status'] == 'cancelled'
                                ? 'Booking Cancelled'
                                : 'Booking Confirmed',
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Syne',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _tracking.location == null &&
                                    _booking.job['status'] != 'en_route'
                                ? 'Live location unavailable'
                                : _tracking.label,
                            style: const TextStyle(
                              color: AppColors.darkTextSecondary,
                              fontFamily: 'DM Sans',
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(status: _booking.job['status'] as String),
                  ],
                ),
              ),
            ),
          ),

          // ── Layer 3: ETA bottom sheet ──────────────────────────────────────
          Positioned(
              top: 140,
              left: 12,
              right: 12,
              child: SafeArea(
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                          onPressed:
                              _tracking.foreground ? _tracking.retry : null,
                          child: const Text('Refresh mechanic location'))))),
          Positioned(
              top: 92,
              left: 12,
              right: 12,
              child: SafeArea(
                  child: AssignmentStateBanner(controller: _assignment))),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomSheet(),
          ),

          // ── Layer 4: Recenter FAB ──────────────────────────────────────────
          Positioned(
            bottom: 280,
            right: 16,
            child: GestureDetector(
              onTap: _recenter,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.darkPrimary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.darkPrimary.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.my_location_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom sheet ───────────────────────────────────────────────────────────

  Widget _buildBottomSheet() {
    final bid = _booking.bid;
    final mechanicName = bid.mechanicName;
    final rating = bid.ratingLabel;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.darkBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mechanic info row
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.darkPrimary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.build_circle_rounded,
                        color: AppColors.darkPrimary, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mechanicName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Syne',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                color: AppColors.darkAccent, size: 14),
                            Text(
                              ' $rating',
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Mechanic ETA estimate',
                        style: TextStyle(
                          color: AppColors.darkTextSecondary,
                          fontFamily: 'DM Sans',
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        bid.eta == null ? 'Unavailable' : '${bid.eta} min',
                        style: const TextStyle(
                          color: AppColors.darkAccent,
                          fontFamily: 'Syne',
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(color: AppColors.darkBorder, height: 1),
              const SizedBox(height: 16),

              Text(
                  '${money(bid.labourCost)} labour + ${money(bid.partsCost)} parts',
                  style: const TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontFamily: 'DM Sans')),
              Text(bid.priceLabel,
                  key: const Key('confirmed-total'),
                  style: const TextStyle(
                      color: AppColors.darkAccent,
                      fontFamily: 'Syne',
                      fontSize: 18)),
              const SizedBox(height: 12),
              JobContactActions(
                  booking: _booking,
                  mechanic: false,
                  enabled: _assignment.verified && !_assignment.loading),

              const SizedBox(height: 12),

              // 4-step progress tracker
              _buildProgressTracker(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Progress tracker ───────────────────────────────────────────────────────

  Widget _buildProgressTracker() {
    return Row(
      children: [
        for (int i = 0; i < _steps.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: i <= _currentStep
                        ? AppColors.darkPrimary
                        : AppColors.darkSurfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _steps[i].icon,
                    color: i <= _currentStep
                        ? Colors.white
                        : AppColors.darkTextSecondary,
                    size: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _steps[i].label,
                  style: TextStyle(
                    color: i <= _currentStep
                        ? AppColors.darkPrimary
                        : AppColors.darkTextSecondary,
                    fontFamily: 'DM Sans',
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          if (i < _steps.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 18),
                color: i < _currentStep
                    ? AppColors.darkPrimary
                    : AppColors.darkBorder,
              ),
            ),
        ],
      ],
    );
  }
}
