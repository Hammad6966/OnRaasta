import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:onraasta/core/widgets/onraasta_button.dart';
import 'package:onraasta/core/widgets/status_badge.dart';
import 'package:onraasta/services/socket_service.dart';
import '../../models/bid_model.dart';
import '../../models/booking_arguments.dart';
import '../../providers/assignment_controller.dart';
import '../../services/assignment_service.dart';
import '../../core/widgets/assignment_state_banner.dart';

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
  final AcceptedBooking booking;
  final AssignmentDetailController? controller;
  const JobInProgressScreen(
      {super.key, required this.booking, this.controller});
  @override
  State<JobInProgressScreen> createState() => _JobInProgressScreenState();
}

class _JobInProgressScreenState extends State<JobInProgressScreen>
    with WidgetsBindingObserver {
  late final AssignmentDetailController _assignment;
  AcceptedBooking get _booking => _assignment.booking;
  String get _status => _booking.job['status'] as String;
  final _statuses = ['en_route', 'arrived', 'in_progress', 'completed'];
  final _labels = ['En Route', 'Arrived', 'In Progress', 'Completed'];
  final _icons = [
    Icons.directions_car,
    Icons.location_on,
    Icons.build,
    Icons.check_circle
  ];
  int get _step => _statuses.indexOf(_status);
  String get _title => switch (_status) {
        'accepted' => 'Booking accepted',
        'en_route' => 'Mechanic En Route',
        'arrived' => 'Mechanic Arrived',
        'in_progress' => 'Repair In Progress',
        'completed' => 'Job Completed',
        'cancelled' => 'Job Cancelled',
        _ => 'Saved Job'
      };
  String get _subtitle => switch (_status) {
        'accepted' => 'Waiting for the mechanic to start travel',
        'en_route' => 'Your mechanic is on the way',
        'arrived' => 'Your mechanic confirmed arrival',
        'in_progress' => 'Your mechanic is working on your vehicle',
        'completed' => 'Your mechanic confirmed completion',
        'cancelled' => 'This job has been cancelled',
        _ => 'Reload the saved job'
      };
  GoogleMapController? _mapController;
  static const _fallback = LatLng(33.6844, 73.0479); // Viewport only.
  LatLng? get _userPosition {
    final location = objectMap(_booking.job['location']),
        lat = finiteNumber(objectMap(_booking.job['location'])['lat']),
        lng = finiteNumber(location['lng']);
    return lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180
        ? LatLng(lat, lng)
        : null;
  }

  bool _openingReview = false;
  bool get _reviewed => objectMap(_booking.job['review'])['stars'] != null;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _assignment = widget.controller ??
        AssignmentDetailController(
            booking: widget.booking,
            socket: SocketService(),
            load: AssignmentService.instance.load);
    _assignment.addListener(_changed);
    _assignment.reload();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _assignment.reload();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _assignment.removeListener(_changed);
    _assignment.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _review() async {
    if (_openingReview ||
        !_assignment.verified ||
        _reviewed ||
        _status != 'completed') {
      return;
    }
    setState(() => _openingReview = true);
    try {
      await _assignment.reload();
      if (!mounted ||
          !_assignment.verified ||
          _assignment.accessDenied ||
          _status != 'completed' ||
          _reviewed) {
        return;
      }
      await context.push('/rate-review', extra: _booking);
      if (mounted) await _assignment.reload();
    } finally {
      if (mounted) setState(() => _openingReview = false);
    }
  }

  Color _color() {
    switch (_step) {
      case 1:
        return const Color(0xFF22C55E);
      case 2:
        return const Color(0xFFF97316);
      case 3:
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFF2563EB);
    }
  }

  Set<Marker> get _markers => {
        if (_userPosition != null)
          Marker(
              markerId: const MarkerId('job'),
              position: _userPosition!,
              infoWindow: const InfoWindow(title: 'Breakdown location'))
      };

  @override
  Widget build(BuildContext context) {
    final center = _userPosition ?? _fallback;

    if (_assignment.accessDenied) {
      return Scaffold(
          backgroundColor: const Color(0xFF050A14),
          body:
              SafeArea(child: AssignmentStateBanner(controller: _assignment)));
    }
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
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2040),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E3A5F)),
                  ),
                  child: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Job In Progress',
                  style: TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const Spacer(),
              StatusBadge(status: _status),
            ]),
          ),

          // ── Map ────────────────────────────────────────────────────────────────
          AssignmentStateBanner(controller: _assignment),
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16), bottom: Radius.circular(16)),
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition:
                        CameraPosition(target: center, zoom: 14),
                    markers: _markers,
                    myLocationEnabled: false,
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
                  // Mechanic label overlay
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xE6050A14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF1E3A5F)),
                      ),
                      child:
                          const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.directions_car,
                            color: Color(0xFFF97316), size: 14),
                        SizedBox(width: 6),
                        Text(
                          'Live mechanic location unavailable',
                          style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 12,
                              color: Colors.white),
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
                    Icon(_step >= 0 ? _icons[_step] : Icons.info_outline,
                        color: _color(), size: 24),
                    const SizedBox(width: 12),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_title,
                              style: const TextStyle(
                                  fontFamily: 'Syne',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                          Text(_subtitle,
                              style: const TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 13,
                                  color: Color(0xFF94A3B8))),
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
                        return Expanded(
                            child: Container(
                          height: 2,
                          color: i ~/ 2 < _step
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF1E3A5F),
                        ));
                      }
                      final idx = i ~/ 2;
                      return Column(children: [
                        Container(
                          width: 40,
                          height: 40,
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
                            color: idx <= _step
                                ? Colors.white
                                : const Color(0xFF94A3B8),
                            size: 18,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(_labels[idx],
                            style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 10,
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
                        _booking.bid.mechanicName.substring(0, 1),
                        style: const TextStyle(
                            fontFamily: 'Syne',
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_booking.bid.mechanicName,
                              style: const TextStyle(
                                  fontFamily: 'Syne',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                          Row(children: [
                            const Icon(Icons.star,
                                color: Color(0xFFF97316), size: 14),
                            Text(' ${_booking.bid.ratingLabel}',
                                style: const TextStyle(
                                    fontFamily: 'DM Sans',
                                    fontSize: 13,
                                    color: Color(0xFF94A3B8))),
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
                    const Text('Bid Details',
                        style: TextStyle(
                            fontFamily: 'Syne',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Text('Labour',
                          style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 13,
                              color: Color(0xFF94A3B8))),
                      const Spacer(),
                      Text(money(_booking.bid.labourCost),
                          style: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 13,
                              color: Colors.white))
                    ]),
                    const Divider(color: Color(0xFF1E3A5F), height: 20),
                    Row(children: [
                      const Text('Parts',
                          style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 13,
                              color: Color(0xFF94A3B8))),
                      const Spacer(),
                      Text(money(_booking.bid.partsCost),
                          style: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 13,
                              color: Colors.white))
                    ]),
                    const Divider(color: Color(0xFF1E3A5F), height: 20),
                    Row(children: [
                      const Text('Total',
                          style: TextStyle(
                              fontFamily: 'Syne',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                      const Spacer(),
                      Text(_booking.bid.priceLabel,
                          style: const TextStyle(
                              fontFamily: 'Syne',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF97316)))
                    ]),
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
                label: _status == 'completed'
                    ? (_reviewed ? 'Review submitted' : 'Rate Mechanic')
                    : _status == 'cancelled'
                        ? 'Job Cancelled'
                        : 'Waiting for mechanic confirmation',
                isLoading: _openingReview,
                isDisabled: _reviewed ||
                    !_assignment.verified ||
                    _assignment.loading ||
                    _status != 'completed',
                onPressed: _assignment.verified &&
                        !_assignment.loading &&
                        _status == 'completed'
                    ? _review
                    : null,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
