import '../../services/auth_service.dart';
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/profile_service.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';
import '../../services/api_service.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class AiDiagnosis {
  final String faultClass;
  final double confidence;
  final int costMin;
  final int costMax;
  final String skillRequired;

  const AiDiagnosis({
    required this.faultClass,
    required this.confidence,
    required this.costMin,
    required this.costMax,
    required this.skillRequired,
  });

  factory AiDiagnosis.fromJson(Map<String, dynamic> json) => AiDiagnosis(
        faultClass: json['fault_class'] as String? ?? 'unknown',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        costMin:
            ((json['cost_range'] as Map?)?['min_pkr'] as num?)?.toInt() ?? 0,
        costMax:
            ((json['cost_range'] as Map?)?['max_pkr'] as num?)?.toInt() ?? 0,
        skillRequired: json['skill_required'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'fault_class': faultClass,
        'confidence': confidence,
        'cost_min': costMin,
        'cost_max': costMax,
        'skill_required': skillRequired,
      };
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ReportBreakdownScreen extends StatefulWidget {
  const ReportBreakdownScreen({super.key});

  @override
  State<ReportBreakdownScreen> createState() => _ReportBreakdownScreenState();
}

class _ReportBreakdownScreenState extends State<ReportBreakdownScreen> {
  final _descController = TextEditingController();
  Map<String, dynamic>? _vehicle;
  bool _loadingVehicles = false;

  GoogleMapController? _mapController;
  Position? _userPosition;
  AiDiagnosis? _aiDiagnosis;
  final List<File?> _photos = [null, null, null];

  bool _isSubmitting = false;

  Timer? _debounce;

  static const LatLng _islamabadFallback = LatLng(33.6844, 73.0479);

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _getLocation();
    _descController.addListener(_onDescChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
      if (extra != null && extra['prefill'] != null) {
        _descController.text = extra['prefill'] as String;
        Future.delayed(
          const Duration(milliseconds: 500),
          () => _diagnoseText(),
        );
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _descController.removeListener(_onDescChanged);
    _descController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ── Location ─────────────────────────────────────────────────────────────────

  Future<void> _getLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      setState(() => _userPosition = pos);
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15),
      );
    } catch (_) {}
  }

  // ── AI Diagnosis ─────────────────────────────────────────────────────────────

  void _onDescChanged() {
    _debounce?.cancel();
    final text = _descController.text;
    if (text.length > 3) {
      _debounce = Timer(const Duration(milliseconds: 800), _diagnoseText);
    } else if (_aiDiagnosis != null) {
      setState(() => _aiDiagnosis = null);
    }
  }

  Future<void> _diagnoseText() async {
    if (_descController.text.length < 3) return;
    try {
      final response = await Dio().post(
        '${ApiConstants.aiUrl}/diagnose/text',
        data: {'text': _descController.text},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      if (response.statusCode == 200 && mounted) {
        final data = response.data as Map<String, dynamic>;
        setState(() {
          _aiDiagnosis = AiDiagnosis(
            faultClass: data['fault_class'] as String? ?? 'unknown',
            confidence: (data['confidence'] as num?)?.toDouble() ?? 0.0,
            costMin: (data['cost_range']?['min_pkr'] as num?)?.toInt() ?? 500,
            costMax: (data['cost_range']?['max_pkr'] as num?)?.toInt() ?? 5000,
            skillRequired:
                data['skill_required'] as String? ?? 'General Mechanic',
          );
        });
      }
    } catch (e) {
      print('AI diagnosis error: $e');
    }
  }

  // ── Photos ───────────────────────────────────────────────────────────────────

  Future<void> _pickPhoto(int index) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Photo uploads are deferred. No photo will be uploaded.')));
  }

  Future<void> _chooseVehicle() async {
    if (_loadingVehicles || _isSubmitting) return;
    final epoch = AuthService.instance.epoch;
    setState(() => _loadingVehicles = true);
    try {
      final vehicles = await ProfileService.instance.vehicles();
      if (!mounted || epoch != AuthService.instance.epoch) return;
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          builder: (c) => SafeArea(
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                const ListTile(title: Text('Choose saved vehicle')),
                if (vehicles.isEmpty)
                  const ListTile(
                      title: Text('No saved vehicles. Add one in Profile.')),
                for (final v in vehicles)
                  ListTile(
                      title: Text('${v['make'] ?? ''} ${v['model'] ?? ''}'),
                      subtitle: Text(
                          '${v['plate']}${v['isPrimary'] == true ? ' ? Primary' : ''}'),
                      onTap: () => Navigator.pop(c, v)),
              ]))));
      if (mounted && epoch == AuthService.instance.epoch && selected != null)
        setState(() => _vehicle = selected);
    } catch (e) {
      if (mounted && epoch == AuthService.instance.epoch)
        _showSubmissionError(profileError(e));
    } finally {
      if (mounted) setState(() => _loadingVehicles = false);
    }
  }

  void _removePhoto(int index) {
    setState(() => _photos[index] = null);
  }

  // ── Submit ───────────────────────────────────────────────────────────────────

  Future<void> _handleFindMechanics() async {
    if (_isSubmitting) return;

    if (_descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe the issue'),
          backgroundColor: AppColors.darkError,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final token = await AuthService.instance.getAccessToken();
      if (!mounted) return;

      if (token == null || token.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session expired. Please login again.')),
        );
        context.go('/login');
        return;
      }

      final position = _userPosition;
      if (position == null ||
          !position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180 ||
          position.latitude == 0 && position.longitude == 0) {
        _showSubmissionError(
            'A current GPS location is required. Enable location services and permission, then retry GPS location.');
        return;
      }
      final response = await ApiService.instance.dio.post('/jobs', data: {
        'description': _descController.text,
        'location': {
          'lat': position.latitude,
          'lng': position.longitude,
          'address': 'Current Location',
        },
        'aiDiagnosis': _aiDiagnosis?.toJson(),
        if (_vehicle != null) 'vehicleId': _vehicle!['_id'],
      });

      if (!mounted) return;
      final body = response.data;
      final status = response.statusCode ?? 0;
      if (status < 200 ||
          status >= 300 ||
          body is! Map ||
          body['success'] != true) {
        _showSubmissionError(_submissionErrorMessage(body));
        return;
      }

      final savedJob = body['data'];
      final jobId = savedJob is Map ? savedJob['_id'] : null;
      if (savedJob is! Map<String, dynamic> ||
          jobId is! String ||
          jobId.trim().isEmpty) {
        _showSubmissionError(
          'The server returned an invalid job. Unable to find mechanics.',
        );
        return;
      }

      context.push('/mechanics-found', extra: savedJob);
    } on DioException catch (e) {
      if (!mounted) return;
      _showSubmissionError(_submissionErrorMessage(e.response?.data));
    } catch (_) {
      if (!mounted) return;
      _showSubmissionError('Failed to create job. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _submissionErrorMessage(dynamic body) {
    final message = body is Map ? body['message'] : null;
    return message is String && message.trim().isNotEmpty
        ? message
        : 'Failed to create job. Please try again.';
  }

  void _showSubmissionError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.darkError),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final mapCenter = _userPosition != null
        ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
        : _islamabadFallback;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Column(
        children: [
          // ── Top: Map (40% screen height) ─────────────────────────────────
          SizedBox(
            height: screenHeight * 0.4,
            child: GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: mapCenter, zoom: 15),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              markers: _userPosition != null
                  ? {
                      Marker(
                        markerId: const MarkerId('user'),
                        position: mapCenter,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueAzure),
                        infoWindow: const InfoWindow(title: 'You are here'),
                      ),
                    }
                  : {},
              onMapCreated: (controller) {
                _mapController = controller;
                if (_userPosition != null) {
                  controller
                      .animateCamera(CameraUpdate.newLatLngZoom(mapCenter, 15));
                }
              },
            ),
          ),

          // ── Bottom: Scrollable content ────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // Header row
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.darkSurface,
                            border: Border.all(color: AppColors.darkBorder),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.arrow_back,
                              color: Colors.white, size: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Report Breakdown',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Syne',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Description label
                  const Text(
                    'DESCRIBE THE ISSUE',
                    style: TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontFamily: 'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.8,
                    ),
                  ),

                  const SizedBox(height: 8),

                  TextButton.icon(
                      onPressed: _loadingVehicles || _isSubmitting
                          ? null
                          : _chooseVehicle,
                      icon: const Icon(Icons.directions_car),
                      label: Text(_loadingVehicles
                          ? 'Loading vehicles...'
                          : _vehicle == null
                              ? 'Choose saved vehicle (optional)'
                              : 'Vehicle: ${_vehicle!['plate']}')),
                  if (_vehicle != null)
                    TextButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => setState(() => _vehicle = null),
                        child: const Text('Clear vehicle selection')),
                  if (_userPosition == null)
                    TextButton(
                        onPressed: _isSubmitting ? null : _getLocation,
                        child: const Text('Retry GPS location')),
                  // Description input + mic
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.darkSurface,
                      border: Border.all(color: AppColors.darkBorder),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _descController,
                            maxLines: 4,
                            style: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 14,
                              color: Colors.white,
                              height: 1.5,
                            ),
                            decoration: const InputDecoration(
                              hintText:
                                  'Describe what happened with your vehicle...',
                              hintStyle: TextStyle(
                                color: AppColors.darkTextSecondary,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: null,
                          icon: const Icon(Icons.mic),
                          color: AppColors.darkTextSecondary,
                          iconSize: 22,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // AI diagnosis chip
                  if (_aiDiagnosis != null)
                    _AiDiagnosisChip(diagnosis: _aiDiagnosis!),

                  const SizedBox(height: 16),

                  // Photos label
                  const Text(
                    'PHOTO UPLOADS ? DEFERRED',
                    style: TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontFamily: 'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.8,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Photo slots
                  Row(
                    children: List.generate(3, (index) {
                      final photo = _photos[index];
                      return Expanded(
                        child: Padding(
                          padding:
                              EdgeInsets.only(right: index < 2 ? 8.0 : 0.0),
                          child: SizedBox(
                            height: 80,
                            child: photo != null
                                ? _FilledPhotoSlot(
                                    file: photo,
                                    onRemove: () => _removePhoto(index),
                                  )
                                : _EmptyPhotoSlot(
                                    onTap: () => _pickPhoto(index),
                                  ),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 24),

                  // Submit button
                  OnRaastaButton(
                    label: 'Find Mechanics →',
                    isLoading: _isSubmitting,
                    onPressed: _handleFindMechanics,
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── AI Diagnosis chip ─────────────────────────────────────────────────────────

class _AiDiagnosisChip extends StatelessWidget {
  final AiDiagnosis diagnosis;
  const _AiDiagnosisChip({required this.diagnosis});

  @override
  Widget build(BuildContext context) {
    final label = diagnosis.faultClass.replaceAll('_', ' ').toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0x1A2563EB),
        border: Border.all(color: AppColors.darkPrimary),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: const [
              Icon(Icons.psychology_rounded,
                  color: AppColors.darkPrimary, size: 20),
              SizedBox(width: 8),
              Text(
                'AI Diagnosis',
                style: TextStyle(
                  color: AppColors.darkPrimary,
                  fontFamily: 'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Fault class + confidence
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Syne',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${(diagnosis.confidence * 100).toInt()}% confident',
                style: const TextStyle(
                  color: AppColors.darkTextSecondary,
                  fontFamily: 'DM Sans',
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Cost range
          Text(
            'Estimated cost: PKR ${diagnosis.costMin} – ${diagnosis.costMax}',
            style: const TextStyle(
              color: AppColors.darkAccent,
              fontFamily: 'DM Sans',
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          // Skill required
          Text(
            'Skill needed: ${diagnosis.skillRequired}',
            style: const TextStyle(
              color: AppColors.darkTextSecondary,
              fontFamily: 'DM Sans',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Photo slots ───────────────────────────────────────────────────────────────

class _FilledPhotoSlot extends StatelessWidget {
  final File file;
  final VoidCallback onRemove;
  const _FilledPhotoSlot({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(file, fit: BoxFit.cover),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPhotoSlot extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyPhotoSlot({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          border:
              Border.all(color: AppColors.darkBorder, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined,
                color: AppColors.darkTextSecondary, size: 24),
            SizedBox(height: 4),
            Text(
              'Add',
              style: TextStyle(
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
