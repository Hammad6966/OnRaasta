import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/status_badge.dart';
import '../../services/socket_service.dart';

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
  final Map<String, dynamic> bid;
  const LiveTrackingScreen({super.key, required this.bid});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  GoogleMapController? _mapController;

  LatLng? _userPosition;
  LatLng  _mechanicPosition = const LatLng(33.6964, 73.0679); // mock start

  int  _etaMinutes  = 15;
  int  _currentStep = 0;
  int  _stepIndex   = 0; // tracks arrival to prevent double-navigation

  Timer? _mockTimer;

  static const LatLng _fallback = LatLng(33.6844, 73.0479);

  // ── Step definitions ───────────────────────────────────────────────────────

  static const _steps = [
    (label: 'En Route',    icon: Icons.directions_car_rounded),
    (label: 'Arrived',     icon: Icons.place_rounded),
    (label: 'In Progress', icon: Icons.build_rounded),
    (label: 'Completed',   icon: Icons.check_circle_rounded),
  ];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _etaMinutes = (widget.bid['eta'] as num?)?.toInt() ?? 15;
    _initLocation();
    _connectSocket();
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    _mapController?.dispose();
    SocketService().off('job:mechanic_location');
    super.dispose();
  }

  // ── Location ───────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _setUserPosition(_fallback);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final loc = LatLng(pos.latitude, pos.longitude);
      _setUserPosition(loc);
    } catch (_) {
      _setUserPosition(_fallback);
    }
  }

  void _setUserPosition(LatLng loc) {
    if (!mounted) return;
    setState(() {
      _userPosition = loc;
      // Mock mechanic starts ~0.02 degrees away (≈2 km)
      _mechanicPosition = LatLng(
        loc.latitude  + 0.02,
        loc.longitude + 0.01,
      );
    });
    _updateEta();
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(loc, 14));
    _startMockMovement();
  }

  // ── Socket ─────────────────────────────────────────────────────────────────

  void _connectSocket() {
    SocketService().on('job:mechanic_location', (data) {
      if (!mounted || data == null) return;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      setState(() => _mechanicPosition = LatLng(lat, lng));
      _updateEta();
    });
  }

  // ── ETA calculation ────────────────────────────────────────────────────────

  void _updateEta() {
    final user = _userPosition;
    if (user == null) return;

    final dLat = _mechanicPosition.latitude  - user.latitude;
    final dLng = _mechanicPosition.longitude - user.longitude;
    final dist  = math.sqrt(dLat * dLat + dLng * dLng);

    // ~111 km per degree; assume 30 km/h → 0.5 deg/min
    final eta = (dist / 0.005).round().clamp(1, 99);
    if (mounted) setState(() => _etaMinutes = eta);
  }

  // ── Mock movement (demo) ───────────────────────────────────────────────────

  void _startMockMovement() {
    _mockTimer?.cancel();
    _mockTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final user = _userPosition;
      if (!mounted || user == null) return;

      final dLat = user.latitude  - _mechanicPosition.latitude;
      final dLng = user.longitude - _mechanicPosition.longitude;
      final dist  = math.sqrt(dLat * dLat + dLng * dLng);

      if (dist < 0.002) {
        _mockTimer?.cancel();
        if (mounted) setState(() => _currentStep = 1); // Arrived
        if (_stepIndex == 0) {
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              context.push('/job-in-progress', extra: {
                'mechanicName': widget.bid['mechanicName'] ?? 'Mechanic',
                'rating':       widget.bid['rating']       ?? 4.5,
                'labourCost':   widget.bid['labourCost']   ?? 1000,
                'partsCost':    widget.bid['partsCost']    ?? 500,
                'totalCost':    widget.bid['totalCost']    ?? 1500,
                'jobId':        widget.bid['jobId']        ?? widget.bid['_id'] ?? '',
                'bidId':        widget.bid['bidId']        ?? widget.bid['_id'] ?? '',
              });
            }
          });
          _stepIndex = 1;
        }
        return;
      }

      setState(() {
        _mechanicPosition = LatLng(
          _mechanicPosition.latitude  + dLat * 0.06,
          _mechanicPosition.longitude + dLng * 0.06,
        );
      });
      _updateEta();
    });
  }

  // ── Recenter ───────────────────────────────────────────────────────────────

  void _recenter() {
    final target = _userPosition ?? _fallback;
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 14));
  }

  // ── Map markers & polyline ─────────────────────────────────────────────────

  Set<Marker> get _markers {
    final user = _userPosition;
    return {
      if (user != null)
        Marker(
          markerId: const MarkerId('user'),
          position: user,
          icon: BitmapDescriptor.defaultMarkerWithHue(210),
          infoWindow: const InfoWindow(title: 'You'),
          zIndex: 2,
        ),
      Marker(
        markerId: const MarkerId('mechanic'),
        position: _mechanicPosition,
        icon: BitmapDescriptor.defaultMarkerWithHue(30),
        infoWindow: InfoWindow(
          title: widget.bid['mechanicName'] as String? ?? 'Mechanic',
        ),
        zIndex: 3,
      ),
    };
  }

  Set<Polyline> get _polylines {
    final user = _userPosition;
    if (user == null) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        color: AppColors.darkPrimary,
        width: 4,
        points: [_mechanicPosition, user],
        patterns: [],
      ),
    };
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final center = _userPosition ?? _fallback;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Stack(
        children: [
          // ── Layer 1: Fullscreen map ────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 14),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            onMapCreated: (c) async {
              _mapController = c;
              await c.setMapStyle(_darkMapStyle);
              if (_userPosition != null) {
                c.animateCamera(
                    CameraUpdate.newLatLngZoom(_userPosition!, 14));
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.darkSurface,
                          border:
                              Border.all(color: AppColors.darkBorder),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mechanic En Route',
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'Syne',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Tracking live location',
                            style: TextStyle(
                              color: AppColors.darkTextSecondary,
                              fontFamily: 'DM Sans',
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(
                        status: _currentStep == 0
                            ? 'en_route'
                            : _currentStep == 1
                                ? 'arrived'
                                : 'in_progress'),
                  ],
                ),
              ),
            ),
          ),

          // ── Layer 3: ETA bottom sheet ──────────────────────────────────────
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
    final mechanicName =
        widget.bid['mechanicName'] as String? ?? 'Mechanic';
    final rating =
        (widget.bid['rating'] as num?)?.toStringAsFixed(1) ?? '4.5';

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
                        'ETA',
                        style: TextStyle(
                          color: AppColors.darkTextSecondary,
                          fontFamily: 'DM Sans',
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '$_etaMinutes min',
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

              // Call / Message buttons
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        border: Border.all(color: AppColors.darkBorder),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone_rounded,
                              color: AppColors.darkSuccess, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Call',
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'DM Sans',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        border: Border.all(color: AppColors.darkBorder),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.message_rounded,
                              color: AppColors.darkPrimary, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Message',
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'DM Sans',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

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
