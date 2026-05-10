import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({super.key, required this.status});

  static const _statusColors = <String, Color>{
    'pending':     AppColors.darkWarning,
    'bidding':     AppColors.darkPrimary,
    'accepted':    AppColors.darkSuccess,
    'en_route':    AppColors.darkPrimary,
    'arrived':     AppColors.darkSuccess,
    'in_progress': AppColors.darkAccent,
    'completed':   AppColors.darkSuccess,
    'cancelled':   AppColors.darkError,
  };

  Color get _color => _statusColors[status.toLowerCase()] ?? AppColors.darkTextSecondary;

  String get _label => status
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        _label,
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}
