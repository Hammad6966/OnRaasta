import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();

  // One controller per animation layer
  late final AnimationController _logoController;
  late final AnimationController _textController;
  late final AnimationController _taglineController;
  late final AnimationController _buttonsController;

  late final Animation<double> _logoScale;
  late final Animation<double> _textOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _buttonsOpacity;
  late final Animation<Offset> _buttonsSlide;

  @override
  void initState() {
    super.initState();
    _buildAnimations();
    _checkAuthAndAnimate();
  }

  void _buildAnimations() {
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _taglineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _buttonsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _logoScale = CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOutBack,
    );
    _textOpacity = CurvedAnimation(
      parent: _textController,
      curve: Curves.easeIn,
    );
    _taglineOpacity = CurvedAnimation(
      parent: _taglineController,
      curve: Curves.easeIn,
    );
    _buttonsOpacity = CurvedAnimation(
      parent: _buttonsController,
      curve: Curves.easeOut,
    );
    _buttonsSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _buttonsController,
      curve: Curves.easeOut,
    ));
  }

  Future<void> _checkAuthAndAnimate() async {
    // Let widget tree settle before reading storage or navigating
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final token = await _storage.read(key: 'access_token');
    final role  = await _storage.read(key: 'user_role');

    if (token != null && token.isNotEmpty) {
      if (!mounted) return;
      if (role == 'mechanic') {
        context.go('/mechanic-home');
      } else {
        context.go('/user-home');
      }
      return;
    }

    // No valid token → run staggered entrance animations
    _logoController.forward();

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _textController.forward();

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _taglineController.forward();

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _buttonsController.forward();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _taglineController.dispose();
    _buttonsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Stack(
        children: [
          // ── Radial glow — blue, top-left ──────────────────────────────────
          Positioned(
            top: -50,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-1.2, -1.2),
                  radius: 1.0,
                  colors: [
                    AppColors.darkPrimary.withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Radial glow — orange, bottom-right ────────────────────────────
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1.2, 1.2),
                  radius: 1.0,
                  colors: [
                    AppColors.darkAccent.withOpacity(0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Main content ──────────────────────────────────────────────────
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo ring — scale 0→1, easeOutBack, 800ms
                  ScaleTransition(
                    scale: _logoScale,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.darkPrimary,
                            Color(0xFF1e40af),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.darkPrimary.withOpacity(0.4),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.directions_car,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // App name — fadeIn after 400ms
                  FadeTransition(
                    opacity: _textOpacity,
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'On',
                            style: GoogleFonts.syne(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: AppColors.darkTextPrimary,
                            ),
                          ),
                          TextSpan(
                            text: 'Raasta',
                            style: GoogleFonts.syne(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: AppColors.darkAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Tagline — fadeIn after 600ms
                  FadeTransition(
                    opacity: _taglineOpacity,
                    child: Text(
                      'Pakistan ka roadside hero',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: AppColors.darkTextSecondary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Buttons — slideUp + fadeIn after 800ms
                  SlideTransition(
                    position: _buttonsSlide,
                    child: FadeTransition(
                      opacity: _buttonsOpacity,
                      child: Column(
                        children: [
                          OnRaastaButton(
                            label: 'Get Started →',
                            onPressed: () => context.push('/role-selection'),
                          ),
                          const SizedBox(height: 12),
                          OnRaastaButton(
                            label: 'I already have an account',
                            isPrimary: false,
                            onPressed: () => context.push('/login'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Footer — pinned to bottom ─────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'By continuing you agree to our Terms & Privacy Policy',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppColors.darkTextSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
