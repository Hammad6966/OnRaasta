import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';

class MechanicProfileEditScreen extends StatefulWidget {
  const MechanicProfileEditScreen({super.key});

  @override
  State<MechanicProfileEditScreen> createState() =>
      _MechanicProfileEditScreenState();
}

class _MechanicProfileEditScreenState
    extends State<MechanicProfileEditScreen> {
  final _nameCtrl    = TextEditingController(text: 'Ahmed Khan');
  final _phoneCtrl   = TextEditingController(text: '3001234567');
  final _addressCtrl = TextEditingController(text: 'Workshop Street, Islamabad');

  final List<String> _allSkills = [
    'Engine Repair',
    'Tyre Change',
    'Battery',
    'Brakes',
    'AC Repair',
    'Electrical',
    'Body Work',
    'Towing',
  ];
  final Set<String> _selectedSkills = {'Engine Repair', 'Tyre Change', 'Battery'};

  double _serviceRadius = 10;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _save() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkSuccess,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text('Profile saved!',
            style: GoogleFonts.dmSans(color: Colors.white)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
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
                      child: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Edit Profile',
                      style: GoogleFonts.syne(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Avatar ────────────────────────────────────────────────
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 52,
                            backgroundColor: AppColors.darkSurface,
                            child: Text(
                              'A',
                              style: GoogleFonts.syne(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.darkPrimary),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.darkAccent,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.camera_alt,
                                  color: Colors.white, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Basic info ────────────────────────────────────────────
                    _SectionLabel('BASIC INFO'),
                    const SizedBox(height: 8),
                    _Field(label: 'Full Name', controller: _nameCtrl),
                    const SizedBox(height: 10),
                    _Field(
                        label: 'Phone',
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 10),
                    _Field(
                        label: 'Workshop / Home Address',
                        controller: _addressCtrl,
                        maxLines: 2),

                    const SizedBox(height: 24),

                    // ── Skills ────────────────────────────────────────────────
                    _SectionLabel('SKILLS'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _allSkills.map((skill) {
                        final selected = _selectedSkills.contains(skill);
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (selected) {
                              _selectedSkills.remove(skill);
                            } else {
                              _selectedSkills.add(skill);
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.darkPrimary
                                  : AppColors.darkSurface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? AppColors.darkPrimary
                                    : AppColors.darkBorder,
                              ),
                            ),
                            child: Text(
                              skill,
                              style: GoogleFonts.dmSans(
                                fontSize: 13,
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF94A3B8),
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 24),

                    // ── Service radius ────────────────────────────────────────
                    _SectionLabel('SERVICE RADIUS'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.darkBorder),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Radius',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 13,
                                      color: const Color(0xFF94A3B8))),
                              Text(
                                '${_serviceRadius.round()} km',
                                style: GoogleFonts.syne(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.darkPrimary),
                              ),
                            ],
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppColors.darkPrimary,
                              inactiveTrackColor: AppColors.darkBorder,
                              thumbColor: AppColors.darkPrimary,
                              overlayColor:
                                  AppColors.darkPrimary.withOpacity(0.2),
                            ),
                            child: Slider(
                              value: _serviceRadius,
                              min: 1,
                              max: 50,
                              divisions: 49,
                              onChanged: (v) =>
                                  setState(() => _serviceRadius = v),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('1 km',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 11,
                                      color: const Color(0xFF94A3B8))),
                              Text('50 km',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 11,
                                      color: const Color(0xFF94A3B8))),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    OnRaastaButton(label: 'Save Changes', onPressed: _save),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.dmSans(
          fontSize: 11,
          color: const Color(0xFF94A3B8),
          letterSpacing: 0.8),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final int maxLines;

  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 12, color: const Color(0xFF94A3B8))),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: GoogleFonts.dmSans(fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.darkSurface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.darkBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.darkBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.darkPrimary),
            ),
          ),
        ),
      ],
    );
  }
}
