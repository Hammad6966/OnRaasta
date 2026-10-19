import 'package:flutter/material.dart';
import '../../providers/job_tracking_publisher.dart';
import '../theme/app_colors.dart';

class JobSharingBanner extends StatelessWidget {
  final JobTrackingPublisher? publisher;
  final String jobId;
  const JobSharingBanner(
      {super.key, required this.publisher, required this.jobId});
  @override
  Widget build(BuildContext context) {
    Widget content() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Expanded(
              child: Text(
                  publisher?.message(jobId) ??
                      'Location sharing is unavailable. Reopen Mechanic Home.',
                  key: const Key('job-location-sharing'),
                  style: const TextStyle(color: AppColors.darkTextSecondary))),
          if (publisher != null)
            TextButton(
                onPressed: publisher!.loading ? null : publisher!.reconcile,
                child: const Text('Retry GPS'))
        ]));
    return publisher == null
        ? content()
        : AnimatedBuilder(animation: publisher!, builder: (_, __) => content());
  }
}
