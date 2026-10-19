import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/history_models.dart';
import '../../models/bid_model.dart';
import '../../services/history_service.dart';
import '../../services/assignment_service.dart';
import '../../services/profile_service.dart';
import '../../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'status_badge.dart';

class HistoryJobCard extends StatelessWidget {
  const HistoryJobCard(
      {super.key,
      required this.job,
      required this.service,
      this.mechanic = false});
  final HistoryJob job;
  final HistoryService service;
  final bool mechanic;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.build_rounded, color: AppColors.darkPrimary),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(job.description,
                      style: const TextStyle(
                          fontFamily: 'Syne',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  if (!mechanic)
                    Text(job.mechanicName,
                        style: const TextStyle(
                            color: AppColors.darkTextSecondary)),
                ])),
            StatusBadge(status: job.status)
          ]),
          const Divider(color: AppColors.darkBorder),
          Text(job.date,
              style: const TextStyle(color: AppColors.darkTextSecondary)),
          Text(
              '${job.data['pricingStatus'] == 'booked' ? 'Booked' : 'Agreed'}: ${job.total}',
              style: const TextStyle(color: AppColors.darkAccent)),
          if (mechanic && job.data['pricingStatus'] == 'booked')
            Text('Calculated net: ${pkr(job.pricing['netMinor'])}',
                style: const TextStyle(color: AppColors.darkSuccess)),
          TextButton(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _JobDetail(
                      id: job.id, service: service, mechanic: mechanic)),
              child: const Text('View Details')),
        ]),
      );
}

class _JobDetail extends StatefulWidget {
  const _JobDetail(
      {required this.id, required this.service, required this.mechanic});
  final String id;
  final HistoryService service;
  final bool mechanic;
  @override
  State<_JobDetail> createState() => _JobDetailState();
}

class _JobDetailState extends State<_JobDetail> {
  Map<String, dynamic>? job;
  String? error;
  bool loading = true, opening = false;
  late final int epoch;
  @override
  void initState() {
    super.initState();
    epoch = AuthService.instance.epoch;
    AuthService.instance.addListener(_session);
    load();
  }

  void _session() {
    if (mounted && epoch != AuthService.instance.epoch) Navigator.pop(context);
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_session);
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await widget.service.detail(widget.id);
      if (mounted && epoch == AuthService.instance.epoch) {
        setState(() => job = data);
      }
    } catch (e) {
      if (mounted) setState(() => error = profileError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resume() async {
    if (opening) return;
    setState(() => opening = true);
    try {
      final booking = await AssignmentService.instance.load(widget.id);
      if (!mounted || epoch != AuthService.instance.epoch) return;
      final route = widget.mechanic
          ? '/active-job'
          : ['in_progress', 'completed'].contains(booking.job['status'])
              ? '/job-in-progress'
              : '/live-tracking';
      final router = GoRouter.of(context);
      Navigator.pop(context);
      router.push(route, extra: booking);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is AssignmentFailure ? e.message : profileError(e);
          opening = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          backgroundColor: AppColors.darkSurface,
          title: const Text('Job Details'),
          content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (loading) const CircularProgressIndicator(),
                if (job != null) ...[
                  Text(job!['description'] as String? ??
                      'Description unavailable'),
                  StatusBadge(status: job!['status'] as String? ?? ''),
                  Text('Created: ${historyDate(job!['createdAt'])}'),
                  if (job!['status'] == 'completed')
                    Text('Completed: ${historyDate(job!['completedAt'])}'),
                  Text(job!['status'] == 'completed'
                      ? 'Booked amount: ${pkr(objectMap(job!['accounting'])['totalMinor'])}'
                      : 'Agreed amount: ${pkr(objectMap(job!['agreedPricing'])['totalMinor'])}'),
                  const Text('Payment is handled outside OnRaasta.'),
                  if (objectId(job!['acceptedBidId']) != null &&
                      job!['status'] != 'cancelled')
                    TextButton(
                        onPressed: loading || opening ? null : resume,
                        child: Text(opening
                            ? 'Loading assignment...'
                            : 'Open Assignment')),
                ],
                if (error != null)
                  Text(error!,
                      style: const TextStyle(color: AppColors.darkError)),
              ])),
          actions: [
            TextButton(
                onPressed: loading ? null : load, child: const Text('Refresh')),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'))
          ]);
}
