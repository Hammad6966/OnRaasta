import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:onraasta/core/widgets/onraasta_button.dart';
import 'package:onraasta/core/widgets/status_badge.dart';
import 'package:onraasta/services/socket_service.dart';

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

class JobInProgressScreen extends StatefulWidget {
  final Map<String, dynamic> bid;
  const JobInProgressScreen({super.key, required this.bid});
  @override
  State<JobInProgressScreen> createState() => _JobInProgressScreenState();
}

class _JobInProgressScreenState extends State<JobInProgressScreen> {
  int _step = 0;
  final List<String>   _statuses  = ['en_route', 'arrived', 'in_progress', 'completed'];
  final List<String>   _labels    = ['En Route', 'Arrived', 'In Progress', 'Completed'];
  final List<IconData> _icons     = [Icons.directions_car, Icons.location_on, Icons.build, Icons.check_circle];
  final List<String>   _btnLabels = ['Mechanic Arrived →', 'Repair Started →', 'Mark Complete ✓', 'Rate Mechanic →'];
  final List<String>   _titles    = ['Mechanic En Route', 'Mechanic Arrived', 'Repair In Progress', 'Job Completed'];
  final List<String>   _subtitles = [
    'Your mechanic is on the way',
    'Your mechanic is at your location',
    'Your mechanic is working on your vehicle',
    'Your vehicle has been repaired',
  ];

  // ── Map state ────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  LatLng? _userPosition;
  LatLng  _mechanicPosition = const LatLng(33.6964, 73.0679);
  Timer?  _mockTimer;

  static const LatLng _fallback = LatLng(33.6844, 73.0479);

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
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

  // ── Location ──────────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _setUserPosition(_fallback);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _setUserPosition(LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      _setUserPosition(_fallback);
    }
  }

  void _setUserPosition(LatLng loc) {
    if (!mounted) return;
    setState(() {
      _userPosition = loc;
      _mechanicPosition = LatLng(loc.latitude + 0.015, loc.longitude + 0.01);
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(loc, 14));
    _startMockMovement();
  }

  // ── Socket ────────────────────────────────────────────────────────────────────

  void _connectSocket() {
    SocketService().on('job:mechanic_location', (data) {
      if (!mounted || data == null) return;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        setState(() => _mechanicPosition = LatLng(lat, lng));
      }
    });
  }

  // ── Mock mechanic movement ────────────────────────────────────────────────────

  void _startMockMovement() {
    _mockTimer?.cancel();
    _mockTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final user = _userPosition;
      if (!mounted || user == null) return;
      final dLat = user.latitude  - _mechanicPosition.latitude;
      final dLng = user.longitude - _mechanicPosition.longitude;
      final dist = math.sqrt(dLat * dLat + dLng * dLng);
      if (dist < 0.002) {
        _mockTimer?.cancel();
        return;
      }
      setState(() {
        _mechanicPosition = LatLng(
          _mechanicPosition.latitude  + dLat * 0.06,
          _mechanicPosition.longitude + dLng * 0.06,
        );
      });
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Color _color() {
    switch (_step) {
      case 1:  return const Color(0xFF22C55E);
      case 2:  return const Color(0xFFF97316);
      case 3:  return const Color(0xFF22C55E);
      default: return const Color(0xFF2563EB);
    }
  }

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
        infoWindow: InfoWindow(title: widget.bid['mechanicName'] as String? ?? 'Mechanic'),
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
        color: const Color(0xFF2563EB),
        width: 4,
        points: [_mechanicPosition, user],
      ),
    };
  }

  // ── Build ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final center = _userPosition ?? _fallback;

    return Scaffold(
      backgroundColor: const Color(0xFF050A14),
      body: SafeArea(
        child: Column(children: [
          // ── Top bar ────────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2040),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E3A5F)),
                  ),
                  child: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Job In Progress', style: TextStyle(fontFamily: 'Syne', fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
              const Spacer(),
              StatusBadge(status: _statuses[_step]),
            ]),
          ),

          // ── Map ────────────────────────────────────────────────────────────────
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16), bottom: Radius.circular(16)),
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(target: center, zoom: 14),
                    markers: _markers,
                    polylines: _polylines,
                    myLocationEnabled: false,
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
                  // Mechanic label overlay
                  Positioned(
                    top: 10, left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xE6050A14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF1E3A5F)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.directions_car, color: Color(0xFFF97316), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          widget.bid['mechanicName'] as String? ?? 'Mechanic',
                          style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: Colors.white),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ── Scrollable cards ────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                // Status banner
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: _color().withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _color()),
                  ),
                  child: Row(children: [
                    Icon(_icons[_step], color: _color(), size: 24),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_titles[_step], style: const TextStyle(fontFamily: 'Syne', fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                      Text(_subtitles[_step], style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: Color(0xFF94A3B8))),
                    ]),
                  ]),
                ),

                // Progress steps
                Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2040),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF1E3A5F)),
                  ),
                  child: Row(
                    children: List.generate(_labels.length * 2 - 1, (i) {
                      if (i.isOdd) {
                        return Expanded(child: Container(
                          height: 2,
                          color: i ~/ 2 < _step ? const Color(0xFF22C55E) : const Color(0xFF1E3A5F),
                        ));
                      }
                      final idx = i ~/ 2;
                      return Column(children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: idx < _step
                                ? const Color(0xFF22C55E)
                                : idx == _step
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF1E3A5F),
                          ),
                          child: Icon(
                            idx < _step ? Icons.check : _icons[idx],
                            color: idx <= _step ? Colors.white : const Color(0xFF94A3B8),
                            size: 18,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(_labels[idx], style: TextStyle(
                          fontFamily: 'DM Sans', fontSize: 10,
                          color: idx < _step
                              ? const Color(0xFF22C55E)
                              : idx == _step
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF94A3B8),
                        )),
                      ]);
                    }),
                  ),
                ),

                // Mechanic card
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2040),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF1E3A5F)),
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF2563EB),
                      child: Text(
                        (widget.bid['mechanicName'] ?? 'M').toString().substring(0, 1),
                        style: const TextStyle(fontFamily: 'Syne', fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.bid['mechanicName'] ?? 'Mechanic', style: const TextStyle(fontFamily: 'Syne', fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                      Row(children: [
                        const Icon(Icons.star, color: Color(0xFFF97316), size: 14),
                        Text(' ${widget.bid['rating'] ?? 4.5}', style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: Color(0xFF94A3B8))),
                      ]),
                    ]),
                  ]),
                ),

                // Bid details
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2040),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF1E3A5F)),
                  ),
                  child: Column(children: [
                    const Text('Bid Details', style: TextStyle(fontFamily: 'Syne', fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(height: 12),
                    Row(children: [const Text('Labour', style: TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: Color(0xFF94A3B8))), const Spacer(), Text('PKR ${widget.bid['labourCost'] ?? 1000}', style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: Colors.white))]),
                    const Divider(color: Color(0xFF1E3A5F), height: 20),
                    Row(children: [const Text('Parts', style: TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: Color(0xFF94A3B8))), const Spacer(), Text('PKR ${widget.bid['partsCost'] ?? 500}', style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: Colors.white))]),
                    const Divider(color: Color(0xFF1E3A5F), height: 20),
                    Row(children: [const Text('Total', style: TextStyle(fontFamily: 'Syne', fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)), const Spacer(), Text('PKR ${widget.bid['totalCost'] ?? 1500}', style: const TextStyle(fontFamily: 'Syne', fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFF97316)))]),
                  ]),
                ),
              ]),
            ),
          ),

          // ── Bottom button ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF0F2040),
              border: Border(top: BorderSide(color: Color(0xFF1E3A5F))),
            ),
            child: SafeArea(
              top: false,
              child: OnRaastaButton(
                label: _btnLabels[_step],
                onPressed: () {
                  if (_step < 3) {
                    setState(() => _step++);
                  } else {
                    context.push('/rate-review', extra: widget.bid);
                  }
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
