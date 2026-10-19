import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../../providers/assignment_controller.dart';

class AssignmentStateBanner extends StatelessWidget {
  final AssignmentDetailController controller;
  const AssignmentStateBanner({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final message = controller.loading
        ? 'Loading saved booking…'
        : controller.error ?? controller.roomError;
    if (message == null) return const SizedBox.shrink();
    return Container(
      color: AppColors.darkSurface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Expanded(
            child: Text(message,
                style: const TextStyle(color: AppColors.darkTextSecondary))),
        if (controller.loading)
          const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
        else
          TextButton(onPressed: controller.reload, child: const Text('Retry')),
      ]),
    );
  }
}
