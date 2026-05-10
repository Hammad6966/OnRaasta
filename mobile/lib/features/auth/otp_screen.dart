import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';
import '../../services/api_service.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  final String role;

  const OtpScreen({super.key, required this.phone, required this.role});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _storage = const FlutterSecureStorage();

  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(6, (_) => FocusNode());

  bool _isLoading     = false;
  int  _resendSeconds = 60;
  Timer? _timer;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes)   f.dispose();
    super.dispose();
  }

  // ── Timer ────────────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds <= 0) {
        t.cancel();
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  // ── OTP input logic ───────────────────────────────────────────────────────────

  void _onOtpChanged(String value, int index) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {}); // Refresh box border/fill
  }

  // ── Verify ────────────────────────────────────────────────────────────────────

  Future<void> _handleVerify() async {
    final otp = _controllers.map((c) => c.text).join();
    if (otp.length < 6) return;

    setState(() => _isLoading = true);
    try {
      final response = await apiDio.post(
        '/auth/verify-otp',
        data: {'phone': widget.phone, 'otp': otp},
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
      final message = e.response?.data?['message'] as String? ??
          'Invalid OTP. Please try again.';
      _showSnackBar(message, isError: true);
      for (final c in _controllers) c.clear();
      _focusNodes[0].requestFocus();
      setState(() {});
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Resend ───────────────────────────────────────────────────────────────────

  Future<void> _resendOtp() async {
    try {
      await apiDio.post('/auth/resend-otp', data: {'phone': widget.phone});
      _startTimer();
      if (!mounted) return;
      _showSnackBar('OTP resent successfully', isError: false);
    } on DioException catch (e) {
      if (!mounted) return;
      final message = e.response?.data?['message'] as String? ??
          'Failed to resend OTP.';
      _showSnackBar(message, isError: true);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.dmSans()),
        backgroundColor: isError ? AppColors.darkError : AppColors.darkSuccess,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String get _maskedPhone {
    if (widget.phone.length < 10) return '+92 ${widget.phone}';
    return '+92 ${widget.phone.substring(0, 3)} ****${widget.phone.substring(7)}';
  }

  // ── OTP box ──────────────────────────────────────────────────────────────────

  Widget _buildOtpBox(int index) {
    final isFilled = _controllers[index].text.isNotEmpty;
    return SizedBox(
      width: 52,
      height: 60,
      child: Container(
        decoration: BoxDecoration(
          color: isFilled
              ? AppColors.darkPrimary.withOpacity(0.1)
              : AppColors.darkSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFilled ? AppColors.darkPrimary : AppColors.darkBorder,
            width: 1.5,
          ),
        ),
        child: TextFormField(
          controller:       _controllers[index],
          focusNode:        _focusNodes[index],
          textAlign:        TextAlign.center,
          keyboardType:     TextInputType.number,
          maxLength:        1,
          inputFormatters:  [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.dmSans(
            fontSize:   24,
            fontWeight: FontWeight.w700,
            color:      Colors.white,
          ),
          decoration: const InputDecoration(
            counterText:    '',
            border:         InputBorder.none,
            enabledBorder:  InputBorder.none,
            focusedBorder:  InputBorder.none,
            filled:         false,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (v) => _onOtpChanged(v, index),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
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
                'Verify your number',
                style: GoogleFonts.syne(
                  fontSize:   26,
                  fontWeight: FontWeight.w700,
                  color:      AppColors.darkTextPrimary,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Enter the 6-digit code sent to',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color:    AppColors.darkTextSecondary,
                ),
              ),
              Text(
                _maskedPhone,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color:    AppColors.darkTextPrimary,
                ),
              ),

              const SizedBox(height: 40),

              // OTP boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) => Padding(
                  padding: EdgeInsets.only(right: i < 5 ? 8.0 : 0.0),
                  child: _buildOtpBox(i),
                )),
              ),

              const SizedBox(height: 40),

              OnRaastaButton(
                label:     'Verify OTP →',
                isLoading: _isLoading,
                onPressed: _handleVerify,
              ),

              const SizedBox(height: 24),

              // Resend row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Didn't receive code? ",
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      color:    AppColors.darkTextSecondary,
                    ),
                  ),
                  if (_resendSeconds > 0)
                    Text(
                      'Resend in ${_resendSeconds}s',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color:    AppColors.darkTextSecondary,
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: _resendOtp,
                      child: Text(
                        'Resend OTP',
                        style: GoogleFonts.dmSans(
                          fontSize:   14,
                          color:      AppColors.darkAccent,
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
    );
  }
}
