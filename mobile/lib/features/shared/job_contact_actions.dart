import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/booking_arguments.dart';
import '../../services/job_contact_service.dart';
import 'job_chat_screen.dart';

class JobContactActions extends StatelessWidget {
  final AcceptedBooking booking;
  final bool mechanic;
  final bool enabled;
  const JobContactActions(
      {super.key,
      required this.booking,
      required this.mechanic,
      required this.enabled});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: OutlinedButton.icon(
          onPressed: enabled
              ? () => callAssignedPerson(context, booking, mechanic: mechanic)
              : null,
          icon: const Icon(Icons.phone_rounded,
              color: AppColors.darkSuccess, size: 20),
          label: const Text('Call'),
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: AppColors.darkSurface,
              side: const BorderSide(color: AppColors.darkBorder),
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
        )),
        const SizedBox(width: 12),
        Expanded(
            child: OutlinedButton.icon(
          onPressed: enabled
              ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) =>
                      JobChatScreen(booking: booking, mechanic: mechanic)))
              : null,
          icon: const Icon(Icons.message_rounded,
              color: AppColors.darkPrimary, size: 20),
          label: const Text('Chat'),
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: AppColors.darkSurface,
              side: const BorderSide(color: AppColors.darkBorder),
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
        )),
      ]);
}
