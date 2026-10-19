import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../../providers/opportunity_controller.dart';

class OpportunityBanner extends StatelessWidget {
  final OpportunityController controller;
  const OpportunityBanner({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => controller.canBid
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            Expanded(
                child: Text(
                    controller.loading
                        ? 'Checking job availability…'
                        : controller.error ?? 'Availability unknown',
                    style:
                        const TextStyle(color: AppColors.darkTextSecondary))),
            if (!controller.loading)
              TextButton(
                  onPressed: controller.refresh, child: const Text('Retry'))
          ]),
        );
}
