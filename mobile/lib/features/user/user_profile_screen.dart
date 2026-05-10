import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

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
  String _userRole  = '';
  String _userId    = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final results = await Future.wait([
      _storage.read(key: 'user_id'),
      _storage.read(key: 'user_role'),
    ]);
    setState(() {
      _userId   = results[0] ?? '';
      _userRole = results[1] ?? '';
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Syne',
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 32),

              // Avatar + info
              Center(
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.darkPrimary,
                      child: Icon(Icons.person_rounded,
                          color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 16),
                    if (_userName.isNotEmpty)
                      Text(
                        _userName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'DM Sans',
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    if (_userRole.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _userRole.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.darkTextSecondary,
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_userId.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'ID: $_userId',
                        style: const TextStyle(
                          color: AppColors.darkTextSecondary,
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 48),

              OnRaastaButton(
                label: 'Sign Out',
                isPrimary: false,
                onPressed: _signOut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
