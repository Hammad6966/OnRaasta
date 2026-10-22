import '../../core/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/profile_controller.dart';
import '../../services/profile_service.dart';
import '../../models/bid_model.dart';
import '../../core/widgets/onraasta_button.dart';

class MechanicProfileEditScreen extends StatefulWidget {
  const MechanicProfileEditScreen({super.key, this.service});
  final ProfileService? service;

  @override
  State<MechanicProfileEditScreen> createState() =>
      _MechanicProfileEditScreenState();
}

class _MechanicProfileEditScreenState extends State<MechanicProfileEditScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final List<String> _allSkills = [...supportedMechanicSkills];
  final Set<String> _selectedSkills = {};
  double _serviceRadius = 15;
  late final ProfileController _profile;
  String? _validation;
  @override
  void initState() {
    super.initState();
    _profile = ProfileController(service: widget.service, mechanic: true)
      ..addListener(_changed);
    _load();
  }

  void _changed() {
    if (_profile.user == null) {
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _addressCtrl.clear();
      _selectedSkills.clear();
      for (final skill in _selectedSkills) {
        if (!_allSkills.contains(skill)) _allSkills.add(skill);
      }
      _serviceRadius = 15;
    }
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await _profile.load();
    if (!mounted || _profile.error != null || _profile.user == null) return;
    final m = _profile.mechanicProfile!;
    setState(() {
      _nameCtrl.text = _profile.user!['name'] as String? ?? '';
      _phoneCtrl.text = _profile.user!['phone'] as String? ?? '';
      _addressCtrl.text = m['shopAddress'] as String? ?? '';
      _selectedSkills
        ..clear()
        ..addAll((m['skills'] as List? ?? []).whereType<String>());
      _serviceRadius =
          (finiteNumber(m['serviceRadius']) ?? 15).clamp(1, 100).toDouble();
    });
  }

  @override
  void dispose() {
    _profile.removeListener(_changed);
    _profile.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_profile.saving || _profile.loading) return;
    if (_nameCtrl.text.trim().length < 2 ||
        _nameCtrl.text.length > 100 ||
        _addressCtrl.text.length > 500) {
      setState(() => _validation =
          'Check name (2?100 characters) and address (up to 500).');
      return;
    }
    if (_selectedSkills.any((s) => !supportedMechanicSkills.contains(s))) {
      setState(() => _validation =
          'Remove unsupported legacy skills and choose the supported skills below.');
      return;
    }
    setState(() => _validation = null);
    final ok = await _profile.save('PATCH', '/mechanics/profile', {
      'name': _nameCtrl.text.trim(),
      'shopAddress': _addressCtrl.text.trim(),
      'skills': _selectedSkills.toList(),
      'serviceRadius': _serviceRadius,
    });
    if (!mounted || !ok) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Profile saved. Skill changes require approval before going online.')));
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
                    if (_profile.loading)
                      const Center(child: CircularProgressIndicator()),
                    if (_profile.error != null)
                      Text(_profile.error!,
                          style: const TextStyle(color: AppColors.darkError)),
                    if (_profile.user == null || _profile.error != null)
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    if (_validation != null)
                      Text(_validation!,
                          style: const TextStyle(color: AppColors.darkError)),
                    if (_profile.mechanicProfile != null)
                      Text(
                          _profile.mechanicProfile!['isApproved'] == true
                              ? 'Approved'
                              : ['rejected', 'revoked'].contains(
                                      _profile.mechanicProfile![
                                          'accountApprovalStatus'])
                                  ? 'Approval rejected or revoked - contact support'
                                  : 'Pending approval',
                          style: const TextStyle(
                              color: AppColors.darkTextSecondary)),
                    ListTile(
                        leading: const Icon(Icons.verified_user_outlined),
                        title: const Text('Documents & Verification'),
                        subtitle: Text(objectMap(_profile
                                    .mechanicProfile?['verification'])['status']
                                as String? ??
                            'Not submitted'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/document-upload')),
                    // ── Avatar ────────────────────────────────────────────────
                    Center(
                        child: ProfileAvatar(
                            userId: _profile.user?['_id'] as String?,
                            name: _profile.user?['name'] as String? ?? '',
                            revision:
                                objectMap(_profile.user?['photo'])['fileId'],
                            onChanged: _profile.load)),

                    const SizedBox(height: 24),

                    // ── Basic info ────────────────────────────────────────────
                    const _SectionLabel('BASIC INFO'),
                    const SizedBox(height: 8),
                    _Field(label: 'Full Name', controller: _nameCtrl),
                    const SizedBox(height: 10),
                    _Field(
                        label: 'Phone',
                        controller: _phoneCtrl,
                        readOnly: true,
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 10),
                    _Field(
                        label: 'Workshop / Home Address',
                        controller: _addressCtrl,
                        maxLines: 2),

                    const SizedBox(height: 24),

                    // ── Skills ────────────────────────────────────────────────
                    const _SectionLabel('SKILLS'),
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
                    const _SectionLabel('SERVICE RADIUS'),
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
                                  AppColors.darkPrimary.withValues(alpha: 0.2),
                            ),
                            child: Slider(
                              value: _serviceRadius,
                              min: 1,
                              max: 100,
                              divisions: 99,
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
                              Text('100 km',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 11,
                                      color: const Color(0xFF94A3B8))),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    OnRaastaButton(
                        label: 'Save Changes',
                        isLoading: _profile.saving,
                        isDisabled: _profile.user == null || _profile.loading,
                        onPressed: _save),
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
          fontSize: 11, color: const Color(0xFF94A3B8), letterSpacing: 0.8),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final int maxLines;
  final bool readOnly;

  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.readOnly = false,
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
          readOnly: readOnly,
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
