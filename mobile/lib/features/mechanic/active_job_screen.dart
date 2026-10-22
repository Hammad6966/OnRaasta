import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/bid_model.dart';
import '../../models/booking_arguments.dart';
import '../../providers/assignment_controller.dart';
import '../../providers/job_tracking_publisher.dart';
import '../../core/widgets/job_sharing_banner.dart';
import '../../services/assignment_service.dart';
import '../../services/socket_service.dart';
import '../../core/widgets/assignment_state_banner.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';
import '../../core/widgets/status_badge.dart';
import '../shared/job_contact_actions.dart';

// ── Step config ───────────────────────────────────────────────────────────────

const _stepKeys = ['en_route', 'arrived', 'in_progress', 'completed'];

const _stepMeta = [
  (label: 'En Route', icon: Icons.directions_car_rounded),
  (label: 'Arrived', icon: Icons.location_on_rounded),
  (label: 'In Progress', icon: Icons.build_rounded),
  (label: 'Completed', icon: Icons.check_circle_rounded),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class ActiveJobScreen extends StatefulWidget {
  final AcceptedBooking booking;
  final AssignmentDetailController? controller;
  final JobTrackingPublisher? tracking;

  const ActiveJobScreen(
      {super.key, required this.booking, this.controller, this.tracking});

  @override
  State<ActiveJobScreen> createState() => _ActiveJobScreenState();
}

class _ActiveJobScreenState extends State<ActiveJobScreen>
    with WidgetsBindingObserver {
  late final AssignmentDetailController _assignment;
  AcceptedBooking get _booking => _assignment.booking;
  String get _currentStatus => _booking.job['status'] as String;
  int get _stepIndex => _stepKeys.indexOf(_currentStatus);
  bool get _isLoading => _assignment.updating;
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
    if (mounted) {
      if (_assignment.verified)
        (widget.tracking ?? JobTrackingPublisher.current)
            ?.observeAssignment(_booking);
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _assignment.reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _assignment.removeListener(_changed);
    _assignment.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String target) => _assignment.updateStatus(target);

  @override
  Widget build(BuildContext context) {
    final description =
        _booking.job['description'] as String? ?? 'No description';
    final aiDiagnosis = _booking.job['aiDiagnosis'] as Map<String, dynamic>?;
    final faultClass =
        (aiDiagnosis?['fault_class'] as String? ?? '').replaceAll('_', ' ');
    final totalCost = _booking.bid.totalCost!;
    final earnings = money(totalCost * 0.85);
    final fee = money(totalCost * 0.15);

    if (_assignment.accessDenied) {
      return Scaffold(
          backgroundColor: AppColors.darkBg,
          body:
              SafeArea(child: AssignmentStateBanner(controller: _assignment)));
    }
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Column(
        children: [
          // ── Top bar ──────────────────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          AssignmentStateBanner(controller: _assignment),
          JobSharingBanner(
              publisher: widget.tracking ?? JobTrackingPublisher.current,
              jobId: _booking.jobId),
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
                          final done = i < _stepIndex;
                          final active = i == _stepIndex;
                          final meta = _stepMeta[i];
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
                                      margin: const EdgeInsets.only(bottom: 22),
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
                                textValue(_booking.driver['name']) ??
                                    'Customer name unavailable',
                                style: GoogleFonts.syne(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),

                  // ── Job details card ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: JobContactActions(
                        booking: _booking,
                        mechanic: true,
                        enabled: _assignment.verified && !_assignment.loading),
                  ),
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
                          if (aiDiagnosis != null && faultClass.isNotEmpty) ...[
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
                                earnings,
                                style: GoogleFonts.syne(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.darkSuccess,
                                ),
                              ),
                            ],
                          ),
                          Text(
                              '${money(_booking.bid.labourCost)} labour + ${money(_booking.bid.partsCost)} parts',
                              style: const TextStyle(
                                  color: AppColors.darkTextSecondary)),
                          Text(_booking.bid.priceLabel,
                              key: const Key('agreed-total'),
                              style:
                                  const TextStyle(color: AppColors.darkAccent)),
                          Text(
                              _booking.bid.eta == null
                                  ? 'ETA unavailable'
                                  : 'Offer ETA: ${_booking.bid.eta} min',
                              style: const TextStyle(
                                  color: AppColors.darkTextSecondary)),
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
                                fee,
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
              border: Border(top: BorderSide(color: AppColors.darkBorder)),
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
    if (!_assignment.verified || _assignment.loading || _assignment.updating) {
      return OnRaastaButton(
          label: 'Verifying saved job',
          isLoading: _assignment.loading || _assignment.updating,
          isDisabled: true,
          onPressed: null);
    }
    switch (_currentStatus) {
      case 'accepted':
        return OnRaastaButton(
            label: 'Start travel', onPressed: () => _updateStatus('en_route'));
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
        return OnRaastaButton(
          label: _currentStatus == 'completed'
              ? 'Job Completed'
              : _currentStatus == 'cancelled'
                  ? 'Job Cancelled'
                  : 'Job unavailable',
          isPrimary: false,
          isDisabled: true,
          onPressed: null,
        );
    }
  }
}
