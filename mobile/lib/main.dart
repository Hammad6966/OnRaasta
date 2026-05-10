import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/theme/dark_theme.dart';
import 'core/theme/light_theme.dart';
import 'features/auth/splash_screen.dart';
import 'features/auth/role_selection_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/otp_screen.dart';
import 'core/theme/app_colors.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Transparent status bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Load .env
  await dotenv.load(fileName: '.env');

  // Allow bundled Google Fonts only (no runtime fetching)
  GoogleFonts.config.allowRuntimeFetching = false;

  // Hydrate persisted theme before first frame
  const storage = FlutterSecureStorage();
  final themeNotifier = await ThemeNotifier.create(storage);

  runApp(
    ProviderScope(
      overrides: [
        themeProvider.overrideWith((_) => themeNotifier),
      ],
      child: const OnRaastaApp(),
    ),
  );
}

// ── Router ───────────────────────────────────────────────────────────────────

final _router = GoRouter(
  initialLocation: '/splash',
  debugLogDiagnostics: false,
  routes: [
    GoRoute(
      path: '/splash',
      builder: (_, __) => const SplashScreen(),
    ),
    GoRoute(
      path: '/role-selection',
      builder: (_, __) => const RoleSelectionScreen(),
    ),
    GoRoute(
      path: '/signup',
      builder: (_, state) {
        final role = (state.extra as String?) ?? 'user';
        return SignupScreen(role: role);
      },
    ),
    GoRoute(
      path: '/login',
      builder: (_, __) => const LoginScreen(),
    ),
    GoRoute(
      path: '/otp',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return OtpScreen(
          phone: extra['phone'] as String? ?? '',
          role:  extra['role']  as String? ?? 'user',
        );
      },
    ),
    GoRoute(
      path: '/user-home',
      builder: (_, __) => Scaffold(
        backgroundColor: AppColors.darkBg,
        body: Center(
          child: Text(
            'User Home - Coming Soon',
            style: GoogleFonts.dmSans(color: Colors.white),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/mechanic-home',
      builder: (_, __) => Scaffold(
        backgroundColor: AppColors.darkBg,
        body: Center(
          child: Text(
            'Mechanic Home - Coming Soon',
            style: GoogleFonts.dmSans(color: Colors.white),
          ),
        ),
      ),
    ),
  ],
);

// ── App root ─────────────────────────────────────────────────────────────────

class OnRaastaApp extends ConsumerWidget {
  const OnRaastaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'OnRaasta',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}
