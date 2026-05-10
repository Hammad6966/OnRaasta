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
import 'features/user/user_home_screen.dart';
import 'features/user/report_breakdown_screen.dart';
import 'features/user/mechanics_found_screen.dart';
import 'features/mechanic/mechanic_home_screen.dart';
import 'features/user/user_profile_screen.dart';
import 'features/mechanic/new_request_detail.dart';
import 'features/mechanic/submit_bid_screen.dart';
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

  // Allow runtime font fetching
  GoogleFonts.config.allowRuntimeFetching = true;

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
      builder: (_, __) => const UserHomeWrapper(),
    ),
    GoRoute(
      path: '/report-breakdown',
      builder: (_, __) => const ReportBreakdownScreen(),
    ),
    GoRoute(
      path: '/mechanics-found',
      builder: (_, state) {
        final job = state.extra as Map<String, dynamic>? ?? {};
        return MechanicsFoundScreen(job: job);
      },
    ),
    GoRoute(
      path: '/mechanic-profile',
      builder: (_, __) => Scaffold(
        backgroundColor: AppColors.darkBg,
        body: Center(
          child: Text(
            'Mechanic Profile - Coming Soon',
            style: GoogleFonts.dmSans(color: Colors.white),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/live-tracking',
      builder: (_, __) => Scaffold(
        backgroundColor: AppColors.darkBg,
        body: Center(
          child: Text(
            'Live Tracking - Coming Soon',
            style: GoogleFonts.dmSans(color: Colors.white),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/user-profile',
      builder: (_, __) => const UserProfileScreen(),
    ),
    GoRoute(
      path: '/mechanic-home',
      builder: (_, __) => const MechanicHomeScreen(),
    ),
    GoRoute(
      path: '/new-request-detail',
      builder: (_, state) {
        final job = state.extra as Map<String, dynamic>? ?? {};
        return NewRequestDetailScreen(job: job);
      },
    ),
    GoRoute(
      path: '/submit-bid',
      builder: (_, state) {
        final job = state.extra as Map<String, dynamic>? ?? {};
        return SubmitBidScreen(job: job);
      },
    ),
  ],
);

// ── User home wrapper (bottom nav shell) ─────────────────────────────────────

class UserHomeWrapper extends StatefulWidget {
  const UserHomeWrapper({super.key});

  @override
  State<UserHomeWrapper> createState() => _UserHomeWrapperState();
}

class _UserHomeWrapperState extends State<UserHomeWrapper> {
  int _currentIndex = 0;

  static const _pages = <Widget>[
    UserHomeScreen(),
    Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Center(
        child: Text(
          'History Coming Soon',
          style: TextStyle(color: Colors.white),
        ),
      ),
    ),
    UserProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: AppColors.darkSurface,
        selectedItemColor: AppColors.darkPrimary,
        unselectedItemColor: AppColors.darkTextSecondary,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded), label: 'History'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}

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
