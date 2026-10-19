import '../../core/widgets/assignment_panel.dart';
import '../../models/booking_arguments.dart';
import '../../providers/assignment_controller.dart';
import '../../services/assignment_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sos_button.dart';
import '../../models/bid_model.dart';
import '../../services/foreground_location.dart';
import '../../services/mechanic_service.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen>
    with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  late final AssignmentInboxController _assignments;
  bool _openingAssignment = false;
  LatLng? _userLocation;
  final Set<Marker> _markers = {};
  List<Map<String, dynamic>> _nearbyMechanics = [];
  bool _locationLoading = true;
  String? _nearbyError;
  int _generation = 0;
  Timer? _refresh;
  bool _foreground = true;

  static const LatLng _lahoreFallback = LatLng(31.5204, 74.3587);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _assignments = AssignmentInboxController(
        socket: SocketService(),
        loadActive: AssignmentService.instance.recover,
        loadOne: AssignmentService.instance.load);
    _assignments.refresh();
    _init();
    _startRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refresh?.cancel();
    _assignments.dispose();
    ++_generation;
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final token = await AuthService.instance.getAccessToken();
    if (!mounted) return;
    if (token != null) {
      SocketService().connect(token);
    }
    if (mounted) await _getLocation();
  }

  Future<void> _openAssignment(AcceptedBooking booking) async {
    if (_openingAssignment) return;
    _openingAssignment = true;
    try {
      await context.push('/live-tracking', extra: booking);
    } finally {
      if (mounted) {
        _openingAssignment = false;
        _assignments.refresh();
      }
    }
  }

  void _startRefresh() {
    _refresh?.cancel();
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_locationLoading) _getLocation();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _assignments.refresh();
      _startRefresh();
      _getLocation();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _foreground = false;
      _refresh?.cancel();
      ++_generation;
      if (mounted) {
        setState(() {
          _locationLoading = false;
          _nearbyMechanics = [];
          _markers.removeWhere((m) => m.markerId.value.startsWith('mechanic_'));
        });
      }
    }
  }

  Future<void> _getLocation() async {
    if (!mounted || !_foreground) return;
    final generation = ++_generation;
    setState(() {
      _locationLoading = true;
      _nearbyError = null;
    });
    try {
      final point = await DeviceForegroundLocation().current();
      if (!mounted || !_foreground || generation != _generation) return;
      final loc = LatLng(point.lat, point.lng);
      setState(() {
        _userLocation = loc;
        _markers.removeWhere((m) => m.markerId.value == 'user');
        _markers.add(Marker(
            markerId: const MarkerId('user'),
            position: loc,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure),
            infoWindow: const InfoWindow(title: 'You are here')));
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(loc, 14));
      final mechanics = await MechanicService.instance.nearby(point);
      if (!mounted || !_foreground || generation != _generation) return;
      final markers = <Marker>{};
      for (final m in mechanics) {
        final id = objectId(m['_id'])!;
        final name =
            textValue(objectMap(m['userId'])['name']) ?? 'Name unavailable';
        final distance = finiteNumber(m['distance'])!;
        markers.add(Marker(
            markerId: MarkerId('mechanic_$id'),
            position: LatLng(finiteNumber(m['lat'])!, finiteNumber(m['lng'])!),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(
                title: name,
                snippet: '${distance.toStringAsFixed(1)} km away')));
      }
      setState(() {
        _nearbyMechanics = mechanics;
        _markers.removeWhere((m) => m.markerId.value.startsWith('mechanic_'));
        _markers.addAll(markers);
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _nearbyError = e is LocationFailure
            ? e.message
            : 'Nearby discovery unavailable. Tap refresh to retry.';
        _nearbyMechanics = [];
        _markers.removeWhere((m) => m.markerId.value.startsWith('mechanic_'));
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _locationLoading = false);
      }
    }
  }

  void _recenter() {
    _getLocation();
    final target = _userLocation ?? _lahoreFallback;
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 14));
  }

  Future<void> _handleSos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Send SOS Alert?',
          style: TextStyle(
            fontFamily: 'Syne',
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        content: const Text(
          'This will alert all available mechanics and emergency contacts nearby. Are you sure?',
          style: TextStyle(
            color: AppColors.darkTextSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.darkTextSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.darkError,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              'Send SOS',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final loc = _userLocation ?? _lahoreFallback;
      SocketService().emit('sos:triggered', {
        'lat': loc.latitude,
        'lng': loc.longitude,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS sent! Help is on the way.'),
          backgroundColor: AppColors.darkError,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapCenter = _userLocation ?? _lahoreFallback;

    return Scaffold(
      body: Stack(
        children: [
          // ── Layer 1: Fullscreen map ─────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(target: mapCenter, zoom: 14),
            markers: _markers,
            myLocationButtonEnabled: false,
            myLocationEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              if (_userLocation != null) {
                controller.animateCamera(
                    CameraUpdate.newLatLngZoom(_userLocation!, 14));
              }
            },
          ),

          Positioned(
              top: 88,
              left: 0,
              right: 0,
              child: SafeArea(
                  bottom: false,
                  child: AssignmentPanel(
                      controller: _assignments, onOpen: _openAssignment))),

          // ── Layer 2: Top bar ────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xCC050A14),
                        border: Border.all(color: AppColors.darkBorder),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_rounded,
                              color: AppColors.darkSuccess, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _locationLoading
                                  ? 'Getting location…'
                                  : _userLocation != null
                                      ? 'Location found'
                                      : 'Location unavailable',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_locationLoading)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.darkPrimary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xCC050A14),
                      border: Border.all(color: AppColors.darkBorder),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.notifications_outlined,
                        color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
          ),

          // ── Layer 3: Mechanics count pill ───────────────────────────────
          if (!_locationLoading)
            Positioned(
              bottom: 330,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xCC050A14),
                    border: Border.all(color: AppColors.darkBorder),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _nearbyError ??
                        (_nearbyMechanics.isEmpty
                            ? 'No mechanics currently nearby'
                            : '${_nearbyMechanics.length} mechanics nearby. Tap a marker for details.'),
                    style: const TextStyle(
                        color: AppColors.darkTextSecondary, fontSize: 12),
                  ),
                ),
              ),
            ),

          // ── Layer 4: SOS button ─────────────────────────────────────────
          Positioned(
            bottom: 272,
            right: 16,
            child: SosButton(onPressed: _handleSos),
          ),

          // ── Layer 5: Recenter FAB ───────────────────────────────────────
          Positioned(
            bottom: 272,
            left: 16,
            child: GestureDetector(
              onTap: _recenter,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  border: Border.all(color: AppColors.darkBorder),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.my_location_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ),

          // ── Layer 6: Bottom panel ───────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomPanel(
              onBreakdownTap: () => context.push('/report-breakdown'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom panel ─────────────────────────────────────────────────────────────

class _BottomPanel extends StatelessWidget {
  final VoidCallback onBreakdownTap;
  const _BottomPanel({required this.onBreakdownTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x262563EB), // #2563EB at 15% opacity
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 14),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.darkBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Breakdown CTA card
                GestureDetector(
                  onTap: onBreakdownTap,
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.car_crash_rounded,
                              color: Colors.white, size: 40),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Vehicle Breakdown?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Syne',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Tap to report · AI diagnosis · instant help',
                                style: TextStyle(
                                  color: Color(0xB3FFFFFF),
                                  fontFamily: 'DM Sans',
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 20),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Quick services row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Quick Services',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Syne',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'See all',
                      style:
                          TextStyle(color: AppColors.darkPrimary, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Services grid
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ServiceChip(
                      icon: Icons.settings_rounded,
                      label: 'Engine Fix',
                      color: const Color(0xFFEF4444),
                      iconBg: const Color(0x26EF4444),
                      onTap: () => context.push('/report-breakdown', extra: {
                        'prefill': 'My engine is not working properly'
                      }),
                    ),
                    _ServiceChip(
                      icon: Icons.battery_charging_full_rounded,
                      label: 'Battery Jump',
                      color: const Color(0xFF22C55E),
                      iconBg: const Color(0x2622C55E),
                      onTap: () => context.push('/report-breakdown', extra: {
                        'prefill': 'My car battery is dead and won\'t start'
                      }),
                    ),
                    _ServiceChip(
                      icon: Icons.tire_repair_rounded,
                      label: 'Flat Tire',
                      color: const Color(0xFFF59E0B),
                      iconBg: const Color(0x26F59E0B),
                      onTap: () => context.push('/report-breakdown', extra: {
                        'prefill': 'I have a flat tyre and need help'
                      }),
                    ),
                    _ServiceChip(
                      icon: Icons.local_gas_station_rounded,
                      label: 'Fuel Delivery',
                      color: const Color(0xFFF97316),
                      iconBg: const Color(0x26F97316),
                      onTap: () => context.push('/report-breakdown',
                          extra: {'prefill': 'My car has run out of fuel'}),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Service chip ─────────────────────────────────────────────────────────────

class _ServiceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconBg;
  final VoidCallback? onTap;

  const _ServiceChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconBg,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          border: Border.all(color: AppColors.darkBorder),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'DM Sans',
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}
