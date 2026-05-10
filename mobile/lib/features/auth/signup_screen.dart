import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';
import '../../core/widgets/onraasta_input.dart';
import '../../services/api_service.dart';

class SignupScreen extends StatefulWidget {
  final String role; // 'user' | 'mechanic'

  const SignupScreen({super.key, required this.role});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController     = TextEditingController();
  final _phoneController    = TextEditingController();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading       = false;
  int  _passwordLength  = 0;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Password strength ──────────────────────────────────────────────────────

  int get _strengthLevel {
    final len = _passwordLength;
    if (len == 0)  return 0;
    if (len <= 3)  return 1;
    if (len <= 6)  return 2;
    if (len <= 7)  return 3;
    return 4;
  }

  Color _segmentColor(int segmentIndex) {
    if (segmentIndex >= _strengthLevel) return AppColors.darkBorder;
    return switch (_strengthLevel) {
      1 => AppColors.darkError,
      2 => AppColors.darkWarning,
      3 => AppColors.darkPrimary,
      _ => AppColors.darkSuccess,
    };
  }

  // ── Register ───────────────────────────────────────────────────────────────

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await dio.post(
        '/auth/register',
        data: {
          'name':     _nameController.text.trim(),
          'phone':    _phoneController.text.trim(),
          'password': _passwordController.text,
          'role':     widget.role,
        },
      );

      if (!mounted) return;
      context.push(
        '/otp',
        extra: {
          'phone': _phoneController.text.trim(),
          'role':  widget.role,
        },
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final message = e.response?.data?['message'] as String? ??
          'Registration failed. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.darkError,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
                  'Create your account',
                  style: GoogleFonts.syne(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkTextPrimary,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Join OnRaasta as a ${widget.role}',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: AppColors.darkTextSecondary,
                  ),
                ),

                const SizedBox(height: 32),

                // ── Full Name ────────────────────────────────────────────────

                OnRaastaInput(
                  controller: _nameController,
                  label: 'FULL NAME',
                  hint: 'Ahmad Khan',
                  prefixIcon: const Icon(
                    Icons.person_outline,
                    color: AppColors.darkTextSecondary,
                    size: 20,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Name is required';
                    if (v.trim().length < 2) return 'Name must be at least 2 characters';
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // ── Phone ────────────────────────────────────────────────────

                _PhoneField(controller: _phoneController),

                const SizedBox(height: 16),

                // ── Email (optional) ─────────────────────────────────────────

                OnRaastaInput(
                  controller: _emailController,
                  label: 'EMAIL (OPTIONAL)',
                  hint: 'ahmad@email.com',
                  prefixIcon: const Icon(
                    Icons.email_outlined,
                    color: AppColors.darkTextSecondary,
                    size: 20,
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),

                const SizedBox(height: 16),

                // ── Password ─────────────────────────────────────────────────

                OnRaastaInput(
                  controller: _passwordController,
                  label: 'PASSWORD',
                  hint: 'Min 8 characters',
                  prefixIcon: const Icon(
                    Icons.lock_outline,
                    color: AppColors.darkTextSecondary,
                    size: 20,
                  ),
                  obscureText: _obscurePassword,
                  suffixIcon: GestureDetector(
                    onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                    child: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: AppColors.darkTextSecondary,
                      size: 20,
                    ),
                  ),
                  onChanged: (v) => setState(() => _passwordLength = v.length),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    if (v.length < 8) return 'Password must be at least 8 characters';
                    return null;
                  },
                ),

                const SizedBox(height: 8),

                // ── Password strength bar ────────────────────────────────────

                Row(
                  children: List.generate(4, (i) {
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                        height: 4,
                        decoration: BoxDecoration(
                          color: _segmentColor(i),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 24),

                OnRaastaButton(
                  label: 'Send OTP & Verify →',
                  isLoading: _isLoading,
                  onPressed: _handleRegister,
                ),

                const SizedBox(height: 24),

                // ── Sign in link ─────────────────────────────────────────────

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: AppColors.darkTextSecondary,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: Text(
                        'Sign In',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: AppColors.darkPrimary,
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

// ── Phone field (prefix +92 + expandable input) ────────────────────────────────

class _PhoneField extends StatelessWidget {
  final TextEditingController controller;

  const _PhoneField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PHONE NUMBER',
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.darkTextSecondary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Country code pill
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.darkBorder),
              ),
              alignment: Alignment.center,
              child: Text(
                '+92',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: AppColors.darkTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Number input
            Expanded(
              child: TextFormField(
                controller: controller,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.dmSans(
                  color: AppColors.darkTextPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: '3001234567',
                  hintStyle: GoogleFonts.dmSans(
                    color: const Color(0xFF4B6280),
                    fontSize: 14,
                  ),
                  counterText: '',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Phone is required';
                  if (v.length != 10) return 'Must be exactly 10 digits';
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
