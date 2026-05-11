import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';
import '../../core/widgets/status_badge.dart';

// ── Step config ───────────────────────────────────────────────────────────────

const _stepKeys = ['en_route', 'arrived', 'in_progress', 'completed'];

const _stepMeta = [
  (label: 'En Route',    icon: Icons.directions_car_rounded),
  (label: 'Arrived',     icon: Icons.location_on_rounded),
  (label: 'In Progress', icon: Icons.build_rounded),
  (label: 'Completed',   icon: Icons.check_circle_rounded),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class ActiveJobScreen extends StatefulWidget {
  final Map<String, dynamic> job;

  const ActiveJobScreen({super.key, required this.job});

  @override
  State<ActiveJobScreen> createState() => _ActiveJobScreenState();
}

class _ActiveJobScreenState extends State<ActiveJobScreen> {
  late String _currentStatus;
  late int _stepIndex;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.job['status'] as String? ?? 'en_route';
    _stepIndex = _stepKeys.indexOf(_currentStatus);
    if (_stepIndex == -1) _stepIndex = 0;
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isLoading = true);
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'access_token');
      final jobId = widget.job['_id'] as String? ??
          widget.job['jobId'] as String? ?? '';

      final dio = Dio();
      await dio.patch(
        '${ApiConstants.baseUrl}/jobs/$jobId/status',
        data: {'status': newStatus},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      setState(() {
        _currentStatus = newStatus;
        _stepIndex = _stepKeys.indexOf(newStatus);
      });

      if (newStatus == 'completed') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Job completed! Great work 🎉',
                style: GoogleFonts.dmSans()),
            backgroundColor: AppColors.darkSuccess,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on DioException catch (e) {
      final msg =
          (e.response?.data as Map?)?['message'] as String? ?? 'Update failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.darkError,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final description =
        widget.job['description'] as String? ?? 'No description';
    final aiDiagnosis =
        widget.job['aiDiagnosis'] as Map<String, dynamic>?;
    final faultClass =
        (aiDiagnosis?['fault_class'] as String? ?? '').replaceAll('_', ' ');
    final totalCost = (widget.job['totalCost'] as num?)?.toInt() ?? 0;
    final earnings  = (totalCost * 0.85).round();
    final fee       = (totalCost * 0.15).round();

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Column(
        children: [
          // ── Top bar ──────────────────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(
                    'Active Job',
                    style: GoogleFonts.syne(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  StatusBadge(status: _currentStatus),
                ],
              ),
            ),
          ),

          // ── Scrollable content ────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // ── Progress tracker ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Row(
                        children: List.generate(_stepMeta.length, (i) {
                          final done   = i < _stepIndex;
                          final active = i == _stepIndex;
                          final meta   = _stepMeta[i];
                          final isLast = i == _stepMeta.length - 1;

                          return Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: done
                                              ? AppColors.darkSuccess
                                              : active
                                                  ? AppColors.darkPrimary
                                                  : const Color(0xFF1E3A5F),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          done
                                              ? Icons.check_rounded
                                              : meta.icon,
                                          size: 16,
                                          color: (done || active)
                                              ? Colors.white
                                              : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        meta.label,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.dmSans(
                                          fontSize: 10,
                                          color: (done || active)
                                              ? Colors.white
                                              : const Color(0xFF94A3B8),
                                          fontWeight: active
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isLast)
                                  Expanded(
                                    child: Container(
                                      height: 2,
                                      margin:
                                          const EdgeInsets.only(bottom: 22),
                                      color: done
                                          ? AppColors.darkSuccess
                                          : const Color(0xFF1E3A5F),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ),

                  // ── User info card ────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 24,
                            backgroundColor: Color(0xFF1E3A5F),
                            child: Icon(
                              Icons.person,
                              color: Color(0xFF94A3B8),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Customer',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                              Text(
                                'OnRaasta User',
                                style: GoogleFonts.syne(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0x2622C55E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: const Color(0x4D22C55E)),
                            ),
                            child: const Icon(
                              Icons.phone,
                              color: AppColors.darkSuccess,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Job details card ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Job Details',
                            style: GoogleFonts.syne(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            description,
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                          if (aiDiagnosis != null &&
                              faultClass.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(
                                  Icons.psychology,
                                  color: AppColors.darkPrimary,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  faultClass,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    color: AppColors.darkAccent,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // ── Earnings card ─────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text(
                                'Your Earnings',
                                style: GoogleFonts.syne(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'PKR $earnings',
                                style: GoogleFonts.syne(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.darkSuccess,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                'Platform fee (15%)',
                                style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'PKR $fee',
                                style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: AppColors.darkError,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom action button ──────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: AppColors.darkSurface,
              border:
                  Border(top: BorderSide(color: AppColors.darkBorder)),
            ),
            padding: const EdgeInsets.all(16),
            child: SafeArea(
              top: false,
              child: _buildActionButton(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    switch (_currentStatus) {
      case 'en_route':
        return OnRaastaButton(
          label: "I've Arrived →",
          isLoading: _isLoading,
          onPressed: () => _updateStatus('arrived'),
        );
      case 'arrived':
        return OnRaastaButton(
          label: 'Start Repair →',
          isLoading: _isLoading,
          onPressed: () => _updateStatus('in_progress'),
        );
      case 'in_progress':
        return OnRaastaButton(
          label: 'Mark Complete ✓',
          isLoading: _isLoading,
          onPressed: () => _updateStatus('completed'),
        );
      default:
        return const OnRaastaButton(
          label: 'Job Completed ✓',
          isPrimary: false,
          isDisabled: true,
          onPressed: null,
        );
    }
  }
}
