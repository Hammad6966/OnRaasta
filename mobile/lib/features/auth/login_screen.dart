import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';
import '../../core/widgets/onraasta_input.dart';
import '../../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey             = GlobalKey<FormState>();
  final _storage             = const FlutterSecureStorage();
  final _phoneController     = TextEditingController();
  final _passwordController  = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading       = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Login ─────────────────────────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final response = await ApiService.instance.dio.post(
        '/auth/login',
        data: {
          'phone':    _phoneController.text.trim(),
          'password': _passwordController.text,
        },
      );
      final data = response.data as Map<String, dynamic>;

      await Future.wait([
        _storage.write(key: 'access_token',  value: data['accessToken']        as String),
        _storage.write(key: 'refresh_token', value: data['refreshToken']       as String),
        _storage.write(key: 'user_role',     value: data['user']['role']       as String),
        _storage.write(key: 'user_id',       value: data['user']['id'].toString()),
      ]);

      if (!mounted) return;
      final role = data['user']['role'] as String;
      context.go(role == 'mechanic' ? '/mechanic-home' : '/user-home');
    } on DioException catch (e) {
      if (!mounted) return;
      final statusCode = e.response?.statusCode;
      final String message;

      if (statusCode == 423 || statusCode == 429) {
        message = 'Account locked. Try again in 30 minutes.';
      } else {
        message = e.response?.data?['message'] as String? ??
            'Sign in failed. Please try again.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:         Text(message, style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.darkError,
          behavior:        SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
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
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  ),
                ),

                const SizedBox(height: 32),

                Text(
                  'Welcome back 👋',
                  style: GoogleFonts.syne(
                    fontSize:   26,
                    fontWeight: FontWeight.w700,
                    color:      AppColors.darkTextPrimary,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Sign in to continue',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color:    AppColors.darkTextSecondary,
                  ),
                ),

                const SizedBox(height: 32),

                // ── Phone ──────────────────────────────────────────────────────

                _LoginPhoneField(controller: _phoneController),

                const SizedBox(height: 16),

                // ── Password ───────────────────────────────────────────────────

                OnRaastaInput(
                  controller:   _passwordController,
                  label:        'PASSWORD',
                  hint:         '••••••••',
                  prefixIcon:   const Icon(
                    Icons.lock_outline,
                    color: AppColors.darkTextSecondary,
                    size: 20,
                  ),
                  obscureText:  _obscurePassword,
                  suffixIcon:   GestureDetector(
                    onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                    child: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.darkTextSecondary,
                      size: 20,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    return null;
                  },
                ),

                const SizedBox(height: 8),

                // Forgot password
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () {}, // TODO: forgot password flow
                    child: Text(
                      'Forgot password?',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color:    AppColors.darkPrimary,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                OnRaastaButton(
                  label:     'Sign In →',
                  isLoading: _isLoading,
                  onPressed: _handleLogin,
                ),

                const SizedBox(height: 24),

                // Sign up link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color:    AppColors.darkTextSecondary,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/role-selection'),
                      child: Text(
                        'Sign Up',
                        style: GoogleFonts.dmSans(
                          fontSize:   14,
                          color:      AppColors.darkPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Phone field widget (prefix +92 + digit-only input) ─────────────────────────

class _LoginPhoneField extends StatelessWidget {
  final TextEditingController controller;

  const _LoginPhoneField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PHONE NUMBER',
          style: GoogleFonts.dmSans(
            fontSize:    11,
            fontWeight:  FontWeight.w600,
            color:       AppColors.darkTextSecondary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // +92 prefix
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color:        AppColors.darkSurface,
                borderRadius: BorderRadius.circular(14),
                border:       Border.all(color: AppColors.darkBorder),
              ),
              alignment: Alignment.center,
              child: Text(
                '+92',
                style: GoogleFonts.dmSans(
                  fontSize:   14,
                  color:      AppColors.darkTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Number input
            Expanded(
              child: TextFormField(
                controller:      controller,
                keyboardType:    TextInputType.phone,
                maxLength:       10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.dmSans(
                  color:    AppColors.darkTextPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText:    '3001234567',
                  hintStyle:   GoogleFonts.dmSans(
                    color:    const Color(0xFF4B6280),
                    fontSize: 14,
                  ),
                  counterText: '',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Phone is required';
                  if (v.length != 10)         return 'Must be exactly 10 digits';
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
