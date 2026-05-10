import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sos_button.dart';
import '../../services/api_service.dart'; // exports: apiDio
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  GoogleMapController? _mapController;
  LatLng? _userLocation;
  final Set<Marker> _markers = {};
  List<Map<String, dynamic>> _nearbyMechanics = [];
  bool _locationLoading = true;

  static const LatLng _lahoreFallback = LatLng(31.5204, 74.3587);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final token = await AuthService.instance.getAccessToken();
    if (token != null) {
      SocketService.instance.connect(token);
    }
    await _getLocation();
  }

  Future<void> _getLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      setState(() => _locationLoading = false);
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final loc = LatLng(pos.latitude, pos.longitude);

      setState(() {
        _userLocation = loc;
        _markers.add(Marker(
          markerId: const MarkerId('user'),
          position: loc,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          zIndex: 2,
          infoWindow: const InfoWindow(title: 'You are here'),
        ));
      });

      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(loc, 14));
      await _fetchNearbyMechanics(pos.latitude, pos.longitude);
    } catch (_) {
      setState(() => _locationLoading = false);
    }
  }

  Future<void> _fetchNearbyMechanics(double lat, double lng) async {
    try {
      final res = await apiDio.get(
        '/mechanics/nearby',
        queryParameters: {'lat': lat, 'lng': lng},
      );
      final data = (res.data['data'] as List?) ?? [];
      final mechanics = List<Map<String, dynamic>>.from(data);

      final Set<Marker> mechanicMarkers = {};
      for (final m in mechanics) {
        final mLat = (m['lat'] as num?)?.toDouble() ?? 0.0;
        final mLng = (m['lng'] as num?)?.toDouble() ?? 0.0;
        final id = m['_id'] as String? ?? Object().hashCode.toString();
        final name =
            ((m['userId'] as Map?)?['name'] as String?) ?? 'Mechanic';
        final dist = (m['distance'] as num?)?.toStringAsFixed(1) ?? '?';

        mechanicMarkers.add(Marker(
          markerId: MarkerId('mechanic_$id'),
          position: LatLng(mLat, mLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(title: name, snippet: '$dist km away'),
        ));
      }

      setState(() {
        _nearbyMechanics = mechanics;
        _markers.addAll(mechanicMarkers);
        _locationLoading = false;
      });
    } catch (_) {
      setState(() => _locationLoading = false);
    }
  }

  void _recenter() {
    final target = _userLocation ?? _lahoreFallback;
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 14));
  }

  Future<void> _handleSos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
      SocketService.instance.emit('sos:triggered', {
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
                controller
                    .animateCamera(CameraUpdate.newLatLngZoom(_userLocation!, 14));
              }
            },
          ),

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
          if (_nearbyMechanics.isNotEmpty)
            Positioned(
              bottom: 276,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xCC050A14),
                    border: Border.all(color: AppColors.darkBorder),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '📍  ${_nearbyMechanics.length} mechanic${_nearbyMechanics.length == 1 ? '' : 's'} nearby  ·  tap marker for details',
                    style: const TextStyle(
                        color: AppColors.darkTextSecondary, fontSize: 12),
                  ),
                ),
              ),
            ),

          // ── Layer 4: SOS button ─────────────────────────────────────────
          Positioned(
            bottom: 210,
            right: 16,
            child: SosButton(onPressed: _handleSos),
          ),

          // ── Layer 5: Recenter FAB ───────────────────────────────────────
          Positioned(
            bottom: 210,
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
            color: Colors.black54,
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
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(
                            child: Text('🚨', style: TextStyle(fontSize: 22)),
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Vehicle Breakdown?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Syne',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Tap to report · AI diagnosis · instant help',
                                style: TextStyle(
                                  color: Color(0xB3FFFFFF),
                                  fontSize: 12,
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
                      style: TextStyle(
                          color: AppColors.darkPrimary, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Services grid
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    _ServiceChip(emoji: '🔧', label: 'Engine Fix'),
                    _ServiceChip(emoji: '🔋', label: 'Battery Jump'),
                    _ServiceChip(emoji: '🛞', label: 'Flat Tire'),
                    _ServiceChip(emoji: '⛽', label: 'Fuel Delivery'),
                  ],
                ),
              ],
            ),
          ),

          // Bottom nav
          Container(
            decoration: const BoxDecoration(
              color: AppColors.darkSurfaceVariant,
              border: Border(
                  top: BorderSide(color: AppColors.darkBorder)),
            ),
            padding: const EdgeInsets.only(top: 12, bottom: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: const [
                _NavItem(
                    icon: Icons.home_rounded, label: 'Home', active: true),
                _NavItem(
                    icon: Icons.receipt_long_rounded, label: 'History'),
                _NavItem(icon: Icons.person_rounded, label: 'Profile'),
                _NavItem(
                    icon: Icons.support_agent_rounded, label: 'Support'),
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
  final String emoji;
  final String label;
  const _ServiceChip({required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        border: Border.all(color: AppColors.darkBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

// ── Nav item ─────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _NavItem(
      {required this.icon, required this.label, this.active = false});

  @override
  Widget build(BuildContext context) {
    final color =
        active ? AppColors.darkPrimary : AppColors.darkTextSecondary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
