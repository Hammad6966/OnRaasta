import 'package:flutter/material.dart';
import '../../providers/profile_controller.dart';
import '../../services/profile_service.dart';
import '../../core/widgets/profile_edit_dialog.dart';
import '../../models/bid_model.dart';
import '../../models/history_models.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';
import '../../services/auth_service.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, this.service});
  final ProfileService? service;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with WidgetsBindingObserver {
  late final ProfileController _profile;
  String get _userName => _profile.user?['name'] as String? ?? '';
  String get _userPhone => _profile.user?['phone'] as String? ?? '';
  List<Map<String, dynamic>> get _contacts =>
      (_profile.user?['emergencyContacts'] as List? ?? [])
          .map(objectMap)
          .toList();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _profile = ProfileController(service: widget.service)
      ..addListener(_changed);
    _profile.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _profile.removeListener(_changed);
    _profile.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _profile.load();
  }

  Future<void> _editAccount() async {
    await editProfileFields(context, title: 'Edit Profile', values: {
      'Name': _userName,
      'Email': _profile.user?['email'] as String? ?? ''
    }, save: (v) async {
      if (v['Name']!.length < 2 || v['Name']!.length > 100) {
        return 'Name must contain 2-100 characters.';
      }
      if (v['Email']!.isNotEmpty &&
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v['Email']!)) {
        return 'Enter a valid email.';
      }
      final ok = await _profile.save('PATCH', '/users/profile',
          {'name': v['Name'], if (v['Email']!.isNotEmpty) 'email': v['Email']});
      return ok ? null : _profile.error ?? 'Unable to save.';
    });
    if (mounted) await _profile.load();
  }

  Future<void> _editVehicle([Map<String, dynamic>? vehicle]) async {
    await editProfileFields(context,
        title: vehicle == null ? 'Add Vehicle' : 'Edit Vehicle',
        values: {
          for (final k in ['make', 'model', 'plate', 'year', 'color'])
            k: vehicle?[k]?.toString() ?? ''
        }, save: (v) async {
      if (['make', 'model', 'plate'].any((k) => v[k]!.isEmpty)) {
        return 'Make, model and plate are required.';
      }
      final year = int.tryParse(v['year']!);
      if (v['year']!.isNotEmpty &&
          (year == null || year < 1900 || year > DateTime.now().year + 1)) {
        return 'Enter a valid year.';
      }
      final ok = await _profile.save(vehicle == null ? 'POST' : 'PATCH',
          '/users/vehicles${vehicle == null ? '' : '/${vehicle['_id']}'}', {
        'make': v['make'],
        'model': v['model'],
        'plate': v['plate'],
        if (year != null) 'year': year,
        if (v['color']!.isNotEmpty) 'color': v['color']
      });
      return ok ? null : _profile.error ?? 'Unable to save.';
    });
    if (mounted) await _profile.load();
  }

  Future<void> _vehicleAction(Map<String, dynamic> v, String action) async {
    if (action == 'edit') {
      await _editVehicle(v);
      return;
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('Delete vehicle?'),
                  content:
                      const Text('Vehicles referenced by jobs are retained.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Delete'))
                  ]));
      if (confirmed != true || !mounted) return;
    }
    await _profile.save(
        action == 'delete' ? 'DELETE' : 'PATCH',
        '/users/vehicles/${v['_id']}',
        action == 'delete' ? null : {'isPrimary': true});
    if (_profile.error == null) await _profile.load();
  }

  Future<void> _editContact([int? index]) async {
    final old = index == null ? <String, dynamic>{} : _contacts[index];
    await editProfileFields(context, title: 'Emergency Contact', values: {
      'Name': old['name'] as String? ?? '',
      'Phone': old['phone'] as String? ?? ''
    }, save: (v) async {
      if (v['Name']!.isEmpty ||
          v['Name']!.length > 100 ||
          !RegExp(r'^\+?\d{10,15}$').hasMatch(v['Phone']!)) {
        return 'Enter a name and 10-15 digit phone number.';
      }
      final contacts = _contacts
          .map((c) => {'name': c['name'], 'phone': c['phone']})
          .toList();
      final item = {'name': v['Name'], 'phone': v['Phone']};
      if (index == null) {
        contacts.add(item);
      } else {
        contacts[index] = item;
      }
      if (contacts.length > 5 ||
          contacts.map((c) => c['phone']).toSet().length != contacts.length) {
        return 'Use up to five distinct contact numbers.';
      }
      final ok = await _profile
          .save('PATCH', '/users/profile', {'emergencyContacts': contacts});
      return ok ? null : _profile.error ?? 'Unable to save.';
    });
    if (mounted) await _profile.load();
  }

  Future<void> _removeContact(int index) async {
    final contacts = _contacts
        .map((c) => {'name': c['name'], 'phone': c['phone']})
        .toList()
      ..removeAt(index);
    if (await _profile
        .save('PATCH', '/users/profile', {'emergencyContacts': contacts})) {
      await _profile.load();
    }
  }

  Future<void> _signOut() async {
    await AuthService.instance.logout();
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
                    Text('Profile',
                        style: GoogleFonts.syne(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
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
                    const CircleAvatar(
                      radius: 52,
                      backgroundColor: AppColors.darkPrimary,
                      child: Icon(Icons.person, color: Colors.white, size: 52),
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

              const SizedBox(height: 16),

              // ── Name + phone + badge ─────────────────────────────────────────
              Center(
                  child: Text(_userName.isNotEmpty ? _userName : 'User',
                      style: GoogleFonts.syne(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white))),
              const SizedBox(height: 4),
              if (_userPhone.isNotEmpty)
                Center(
                    child: Text('+92 $_userPhone',
                        style: GoogleFonts.dmSans(
                            fontSize: 14, color: const Color(0xFF94A3B8)))),
              const SizedBox(height: 8),
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0x1A2563EB),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.darkPrimary),
                  ),
                  child: Text('Driver',
                      style: GoogleFonts.dmSans(
                          fontSize: 13, color: AppColors.darkPrimary)),
                ),
              ),

              const SizedBox(height: 24),

              // ── Stats row ────────────────────────────────────────────────────
              if (_profile.loading)
                const Center(child: CircularProgressIndicator()),
              if (_profile.error != null) ...[
                Text(_profile.error!,
                    style: const TextStyle(color: AppColors.darkError)),
                TextButton(
                    onPressed: _profile.load, child: const Text('Retry')),
              ],
              if (_profile.user != null) ...[
                if (objectMap(_profile.user!['statistics'])['completedJobs'] !=
                    null) ...[
                  Text(
                      'Completed jobs: ${objectMap(_profile.user!['statistics'])['completedJobs']}',
                      style:
                          const TextStyle(color: AppColors.darkTextSecondary)),
                  Text(
                      'Booked completed amount: ${pkr(objectMap(_profile.user!['statistics'])['pricedJobs'] == 0 && (objectMap(_profile.user!['statistics'])['unpricedJobs'] as int? ?? 0) > 0 ? null : objectMap(_profile.user!['statistics'])['grossMinor'])}',
                      style:
                          const TextStyle(color: AppColors.darkTextSecondary)),
                  if ((objectMap(_profile.user!['statistics'])['unpricedJobs']
                              as int? ??
                          0) >
                      0)
                    const Text(
                        'Some historical prices are unavailable; totals include priced jobs only.',
                        style: TextStyle(color: AppColors.darkWarning)),
                ],
                if (_profile.user!['email'] != null)
                  Center(
                      child: Text(_profile.user!['email'],
                          style: const TextStyle(
                              color: AppColors.darkTextSecondary))),
                Center(
                    child: Text(
                        _profile.user!['isVerified'] == true
                            ? 'Phone verified'
                            : 'Phone verification pending',
                        style: const TextStyle(
                            color: AppColors.darkTextSecondary))),
                Center(
                    child: TextButton(
                        onPressed: _profile.saving ? null : _editAccount,
                        child: const Text('Edit Profile'))),
                const _SectionLabel('MY VEHICLES'),
                if (_profile.vehicles.isEmpty)
                  const Text('No vehicles saved.',
                      style: TextStyle(color: AppColors.darkTextSecondary)),
                for (final v in _profile.vehicles)
                  Card(
                      color: AppColors.darkSurface,
                      child: ListTile(
                        leading: const Icon(Icons.directions_car,
                            color: AppColors.darkPrimary),
                        title: Text('${v['make'] ?? ''} ${v['model'] ?? ''}',
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                            '${v['plate']} ? ${v['year'] ?? ''} ${v['color'] ?? ''}${v['isPrimary'] == true ? ' ? Primary' : ''}',
                            style: const TextStyle(
                                color: AppColors.darkTextSecondary)),
                        trailing: PopupMenuButton<String>(
                            enabled: !_profile.saving,
                            onSelected: (a) => _vehicleAction(v, a),
                            itemBuilder: (_) => [
                                  const PopupMenuItem(
                                      value: 'edit', child: Text('Edit')),
                                  if (v['isPrimary'] != true)
                                    const PopupMenuItem(
                                        value: 'primary',
                                        child: Text('Make Primary')),
                                  const PopupMenuItem(
                                      value: 'delete', child: Text('Delete')),
                                ]),
                      )),
                _DashedAddCard(
                    icon: Icons.add,
                    iconColor: AppColors.darkPrimary,
                    label: 'Add Vehicle',
                    labelColor: AppColors.darkPrimary,
                    onTap: () {
                      if (!_profile.saving) _editVehicle();
                    }),
                const SizedBox(height: 24),
                const _SectionLabel('EMERGENCY CONTACTS'),
                const Text(
                    'Saved contacts only. Emergency alerts are not enabled.',
                    style: TextStyle(color: AppColors.darkTextSecondary)),
                if (_contacts.isEmpty)
                  const Text('No contacts saved.',
                      style: TextStyle(color: AppColors.darkTextSecondary)),
                for (var i = 0; i < _contacts.length; i++)
                  Card(
                      color: AppColors.darkSurface,
                      child: ListTile(
                        onTap: _profile.saving ? null : () => _editContact(i),
                        leading: const Icon(Icons.emergency,
                            color: AppColors.darkError),
                        title: Text(_contacts[i]['name'] ?? '',
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(_contacts[i]['phone'] ?? '',
                            style: const TextStyle(
                                color: AppColors.darkTextSecondary)),
                        trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _profile.saving
                                ? null
                                : () => _removeContact(i)),
                      )),
                _DashedAddCard(
                    icon: Icons.add,
                    iconColor: AppColors.darkError,
                    label: 'Add Emergency Contact',
                    labelColor: AppColors.darkError,
                    onTap: () {
                      if (!_profile.saving) _editContact();
                    }),
              ],
              const SizedBox(height: 24),
              const _SectionLabel('SETTINGS'),
              const SizedBox(height: 8),
              ...[
                (Icons.notifications, 'Push notifications (deferred)'),
                (Icons.language, 'Language'),
                (Icons.help, 'Help & Support'),
                (Icons.info, 'About OnRaasta'),
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
                        Text(item.$2,
                            style: GoogleFonts.dmSans(
                                fontSize: 14, color: Colors.white)),
                        const Spacer(),
                        const Icon(Icons.chevron_right,
                            color: Color(0xFF94A3B8)),
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

class _DashedAddCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;
  const _DashedAddCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
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
          border: Border.all(
              color: const Color(0xFF1E3A5F), style: BorderStyle.solid),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Text(label,
              style: GoogleFonts.dmSans(fontSize: 14, color: labelColor)),
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
    return Text(text,
        style: GoogleFonts.dmSans(
            fontSize: 11, color: const Color(0xFF94A3B8), letterSpacing: 0.8));
  }
}
