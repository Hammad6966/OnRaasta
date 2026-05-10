import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class OnRaastaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final bool isPrimary;
  final bool isFullWidth;
  final IconData? icon;

  const OnRaastaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.isPrimary = true,
    this.isFullWidth = true,
    this.icon,
  });

  VoidCallback? get _effectiveOnPressed =>
      (isLoading || isDisabled) ? null : onPressed;

  Widget _buildChild() {
    if (isLoading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }
    return Row(
      mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(isFullWidth ? double.infinity : 0, 52);

    final button = isPrimary
        ? SizedBox(
            width: isFullWidth ? double.infinity : null,
            height: 52,
            child: ElevatedButton(
              onPressed: _effectiveOnPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkPrimary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.darkPrimary,
                elevation: 0,
                minimumSize: size,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _buildChild(),
            ),
          )
        : SizedBox(
            width: isFullWidth ? double.infinity : null,
            height: 52,
            child: OutlinedButton(
              onPressed: _effectiveOnPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: AppColors.darkBorder, width: 1.5),
                minimumSize: size,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _buildChild(),
            ),
          );

    return isDisabled
        ? Opacity(opacity: 0.5, child: button)
        : button;
  }
}
