import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  String? _selectedRole; // 'user' | 'mechanic' | null

  // ── Role card ──────────────────────────────────────────────────────────────

  Widget _roleCard({
    required String role,
    required IconData cardIcon,
    required Color iconBg,
    required Color iconColor,
    required Color checkColor,
    required Color glowColor,
    required String title,
    required String subtitle,
    required List<String> features,
  }) {
    final isSelected = _selectedRole == role;

    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 160),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? Border.all(color: checkColor, width: 2)
              : Border.all(color: AppColors.darkBorder, width: 1),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: glowColor.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Icon container
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(cardIcon, color: iconColor, size: 32),
                ),
                const SizedBox(width: 16),
                // Title + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.syne(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: AppColors.darkTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Check icon — only when selected
                if (isSelected)
                  Icon(Icons.check_circle, color: checkColor, size: 22),
              ],
            ),
            const SizedBox(height: 16),
            // Feature list
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: AppColors.darkSuccess,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      f,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: AppColors.darkTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Progress dots ──────────────────────────────────────────────────────────

  Widget _progressDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 24,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.darkPrimary,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.darkBorder,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.darkBorder,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final buttonLabel = switch (_selectedRole) {
      'user'     => 'Continue as Driver →',
      'mechanic' => 'Continue as Mechanic →',
      _          => 'Select a role to continue',
    };

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // Back button
              GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.darkBorder),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              Text(
                'Who are you\njoining as?',
                style: GoogleFonts.syne(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkTextPrimary,
                  height: 1.2,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Choose your role to get started',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: AppColors.darkTextSecondary,
                ),
              ),

              const SizedBox(height: 32),

              // Driver card
              _roleCard(
                role: 'user',
                cardIcon: Icons.directions_car,
                iconBg: const Color(0xFF2563EB).withOpacity(0.15),
                iconColor: AppColors.darkPrimary,
                checkColor: AppColors.darkPrimary,
                glowColor: const Color(0xFF2563EB),
                title: 'Driver',
                subtitle: 'I need roadside help',
                features: const [
                  'Get instant roadside assistance',
                  'Real-time mechanic tracking',
                  'AI-powered fault diagnosis',
                ],
              ),

              const SizedBox(height: 24),

              // Mechanic card
              _roleCard(
                role: 'mechanic',
                cardIcon: Icons.build,
                iconBg: const Color(0xFFF97316).withOpacity(0.15),
                iconColor: AppColors.darkAccent,
                checkColor: AppColors.darkAccent,
                glowColor: const Color(0xFFF97316),
                title: 'Mechanic',
                subtitle: 'I provide repair services',
                features: const [
                  'Receive job requests nearby',
                  'Set your own pricing',
                  'Build your reputation',
                ],
              ),

              const SizedBox(height: 48),

              // Continue button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OnRaastaButton(
                  label: buttonLabel,
                  isDisabled: _selectedRole == null,
                  onPressed: () {
                    if (_selectedRole == 'user') {
                      context.go('/signup', extra: 'user');
                    } else if (_selectedRole == 'mechanic') {
                      context.go('/signup', extra: 'mechanic');
                    }
                  },
                ),
              ),

              const SizedBox(height: 24),

              _progressDots(),
            ],
          ),
        ),
      ),
    );
  }
}
