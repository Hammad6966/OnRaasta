import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _storage = const FlutterSecureStorage();
  String _userName  = '';
  String _userPhone = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final results = await Future.wait([
      _storage.read(key: 'user_name'),
      _storage.read(key: 'phone'),
    ]);
    setState(() {
      _userName  = results[0] ?? 'User';
      _userPhone = results[1] ?? '';
    });
  }

  Future<void> _signOut() async {
    await _storage.deleteAll();
    if (!mounted) return;
    context.go('/splash');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top bar ──────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Text('Profile', style: GoogleFonts.syne(
                      fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                    const Spacer(),
                    IconButton(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),

              // ── Avatar ───────────────────────────────────────────────────────
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: AppColors.darkPrimary,
                      child: const Icon(Icons.person, color: Colors.white, size: 52),
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.darkAccent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Name + phone + badge ─────────────────────────────────────────
              Center(child: Text(_userName.isNotEmpty ? _userName : 'User',
                  style: GoogleFonts.syne(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white))),
              const SizedBox(height: 4),
              if (_userPhone.isNotEmpty)
                Center(child: Text('+92 $_userPhone',
                    style: GoogleFonts.dmSans(fontSize: 14, color: const Color(0xFF94A3B8)))),
              const SizedBox(height: 8),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0x1A2563EB),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.darkPrimary),
                  ),
                  child: Text('Driver', style: GoogleFonts.dmSans(
                      fontSize: 13, color: AppColors.darkPrimary)),
                ),
              ),

              const SizedBox(height: 24),

              // ── Stats row ────────────────────────────────────────────────────
              Row(
                children: [
                  _StatCard(value: '3',      label: 'Trips'),
                  _StatCard(value: '4.8★',   label: 'Rating'),
                  _StatCard(value: 'PKR 0',  label: 'Saved'),
                ],
              ),

              const SizedBox(height: 24),

              // ── My Vehicles ──────────────────────────────────────────────────
              _SectionLabel('MY VEHICLES'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: Row(children: [
                  const Icon(Icons.directions_car, color: AppColors.darkPrimary, size: 24),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Toyota Corolla', style: GoogleFonts.dmSans(
                        fontSize: 14, color: Colors.white)),
                    Text('2020 • White • ABC-123', style: GoogleFonts.dmSans(
                        fontSize: 12, color: const Color(0xFF94A3B8))),
                  ]),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x1A22C55E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.darkSuccess),
                    ),
                    child: Text('Primary', style: GoogleFonts.dmSans(
                        fontSize: 11, color: AppColors.darkSuccess)),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              _DashedAddCard(
                icon: Icons.add,
                iconColor: AppColors.darkPrimary,
                label: 'Add Vehicle',
                labelColor: AppColors.darkPrimary,
                onTap: () {},
              ),

              const SizedBox(height: 24),

              // ── Emergency Contacts ───────────────────────────────────────────
              _SectionLabel('EMERGENCY CONTACTS'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: Row(children: [
                  const Icon(Icons.emergency, color: AppColors.darkError, size: 24),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Ahmed Khan', style: GoogleFonts.dmSans(
                        fontSize: 14, color: Colors.white)),
                    Text('+92 300 1234567', style: GoogleFonts.dmSans(
                        fontSize: 12, color: const Color(0xFF94A3B8))),
                  ]),
                ]),
              ),
              const SizedBox(height: 8),
              _DashedAddCard(
                icon: Icons.add,
                iconColor: AppColors.darkError,
                label: 'Add Emergency Contact',
                labelColor: AppColors.darkError,
                onTap: () {},
              ),

              const SizedBox(height: 24),

              // ── Settings ─────────────────────────────────────────────────────
              _SectionLabel('SETTINGS'),
              const SizedBox(height: 8),
              ...[
                (Icons.notifications, 'Notifications'),
                (Icons.language,      'Language'),
                (Icons.help,          'Help & Support'),
                (Icons.info,          'About OnRaasta'),
              ].map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.darkBorder),
                  ),
                  child: Row(children: [
                    Icon(item.$1, color: AppColors.darkPrimary, size: 20),
                    const SizedBox(width: 12),
                    Text(item.$2, style: GoogleFonts.dmSans(
                        fontSize: 14, color: Colors.white)),
                    const Spacer(),
                    const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                  ]),
                ),
              )),

              const SizedBox(height: 24),
              OnRaastaButton(
                label: 'Sign Out',
                isPrimary: false,
                onPressed: _signOut,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F2040),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E3A5F)),
        ),
        child: Column(children: [
          Text(value, style: GoogleFonts.syne(
              fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.dmSans(
              fontSize: 12, color: const Color(0xFF94A3B8))),
        ]),
      ),
    );
  }
}

class _DashedAddCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;
  const _DashedAddCard({
    required this.icon, required this.iconColor,
    required this.label, required this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F2040),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E3A5F), style: BorderStyle.solid),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.dmSans(fontSize: 14, color: labelColor)),
        ]),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: GoogleFonts.dmSans(
        fontSize: 11, color: const Color(0xFF94A3B8), letterSpacing: 0.8));
  }
}
