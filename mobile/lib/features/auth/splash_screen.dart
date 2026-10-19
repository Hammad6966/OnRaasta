import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/api_constants.dart';
import '../../services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_button.dart';

class SplashScreen extends StatefulWidget {
  final AuthService? auth;
  const SplashScreen({super.key, this.auth});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  bool _checking = true;
  String? _recoveryError;
  AuthService get _auth => widget.auth ?? AuthService.instance;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuthAndAnimate());
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

  Future<void> _loadSavedIp() async {
    if (ApiConstants.hasConfiguredServer) return;
    final savedIp = await _storage.read(key: 'server_ip');
    if (savedIp != null && ApiConstants.validServerHost(savedIp)) {
      ApiConstants.serverIp = savedIp;
    } else {
      await _showIpDialog();
    }
  }

  Future<void> _showIpDialog() async {
    final controller = TextEditingController(text: ApiConstants.serverIp);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F2040),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Server IP Address',
          style: GoogleFonts.syne(
              fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the IP address of the server on your local network.',
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: const Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.dmSans(fontSize: 14, color: Colors.white),
              decoration: InputDecoration(
                hintText: '192.168.x.x',
                hintStyle: GoogleFonts.dmSans(
                    fontSize: 14, color: const Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFF050A14),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.darkPrimary),
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OnRaastaButton(
            label: 'Connect',
            onPressed: () async {
              final ip = controller.text.trim();
              if (!ApiConstants.validServerHost(ip)) return;
              ApiConstants.serverIp = ip;
              await _storage.write(key: 'server_ip', value: ip);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _checkAuthAndAnimate() async {
    if (!mounted) return;
    setState(() {
      _checking = true;
      _recoveryError = null;
    });
    _logoController.forward();
    _textController.forward();
    _taglineController.forward();
    await _loadSavedIp();
    if (!mounted) return;
    final state = await _auth.recover();
    if (!mounted) return;
    if (state == SessionStatus.authenticated) {
      context.go(_auth.role == 'mechanic' ? '/mechanic-home' : '/user-home');
      return;
    }
    setState(() {
      _checking = false;
      if (state == SessionStatus.offline) {
        _recoveryError =
            'Unable to validate your saved session. Check your connection and retry.';
      }
    });
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
                  if (_checking) const CircularProgressIndicator(),
                  if (_recoveryError != null) ...[
                    Text(_recoveryError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.darkTextSecondary)),
                    TextButton(
                        onPressed: _checkAuthAndAnimate,
                        child: const Text('Retry session recovery')),
                    TextButton(
                        onPressed: () async {
                          await _auth.clearTokens();
                          if (context.mounted) context.go('/login');
                        },
                        child: const Text('Sign in instead')),
                  ],
                  if (!_checking && _recoveryError == null)
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
