import 'package:flutter/material.dart';
import '../../models/booking_arguments.dart';
import '../../providers/assignment_controller.dart';
import '../theme/app_colors.dart';

class AssignmentPanel extends StatelessWidget {
  final AssignmentInboxController controller;
  final void Function(AcceptedBooking) onOpen;
  const AssignmentPanel(
      {super.key, required this.controller, required this.onOpen});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final active = controller.bookings;
        final closed = controller.recentClosed;
        final jobs = [...active, ...closed];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppColors.darkSurface,
              border: Border.all(color: AppColors.darkBorder),
              borderRadius: BorderRadius.circular(20)),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(
                      child: Text('Assigned jobs',
                          style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'Syne',
                              fontWeight: FontWeight.w700))),
                  IconButton(
                      tooltip: 'Refresh assignments',
                      onPressed: controller.loading ? null : controller.refresh,
                      icon: const Icon(Icons.refresh,
                          color: AppColors.darkTextSecondary))
                ]),
                if (controller.loading) const LinearProgressIndicator(),
                if (controller.error != null)
                  Text(controller.error!,
                      style: const TextStyle(
                          color: AppColors.darkError,
                          fontFamily: 'DM Sans',
                          fontSize: 12)),
                if (active.isEmpty &&
                    !controller.loading &&
                    controller.error == null)
                  const Text('No active assignments.',
                      style: TextStyle(
                          color: AppColors.darkTextSecondary,
                          fontFamily: 'DM Sans',
                          fontSize: 12)),
                if (closed.isNotEmpty)
                  const Text('Recent closed assignments are marked below.',
                      style: TextStyle(
                          color: AppColors.darkTextSecondary,
                          fontFamily: 'DM Sans',
                          fontSize: 12)),
                if (jobs.isNotEmpty)
                  SizedBox(
                      height: jobs.length == 1 ? 70 : 140,
                      child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: jobs.length,
                          itemBuilder: (_, index) {
                            final booking = jobs[index];
                            return ListTile(
                                key: ValueKey('assignment-${booking.jobId}'),
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                    '${booking.isActive ? '' : 'Closed: '}${booking.job['description'] is String ? booking.job['description'] : 'Saved job'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'DM Sans',
                                        fontSize: 14)),
                                subtitle: Text(
                                    '${booking.job['status']} · ${booking.bid.priceLabel}',
                                    style: const TextStyle(
                                        color: AppColors.darkTextSecondary,
                                        fontFamily: 'DM Sans',
                                        fontSize: 12)),
                                trailing: const Icon(Icons.arrow_forward,
                                    color: AppColors.darkPrimary),
                                onTap: () => onOpen(booking));
                          })),
              ]),
        );
      });
}
