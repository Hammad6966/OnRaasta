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
import 'features/user/bidding_routes.dart';
import 'features/mechanic/mechanic_home_screen.dart' show MechanicHomeWrapper;
import 'features/user/user_profile_screen.dart';
import 'features/user/job_history_screen.dart';
import 'features/mechanic/mechanic_profile_edit.dart';
import 'features/mechanic/mechanic_earnings_screen.dart';
import 'features/mechanic/document_upload_screen.dart';
import 'features/mechanic/mechanic_ratings_screen.dart';
import 'providers/theme_provider.dart';
import 'services/auth_service.dart';

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

  AuthService.instance.bindSocket();

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
  refreshListenable: AuthService.instance,
  redirect: (context, state) {
    const publicPaths = [
      '/splash',
      '/login',
      '/signup',
      '/otp',
      '/role-selection'
    ];
    if (AuthService.instance.status == SessionStatus.signedOut &&
        !publicPaths.contains(state.uri.path)) return '/login';
    return null;
  },
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
          role: extra['role'] as String? ?? 'user',
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
      builder: (_, state) => mechanicsFoundPage(state.extra),
    ),
    GoRoute(
      path: '/mechanic-profile',
      builder: (_, state) => mechanicProfilePage(state.extra),
    ),
    GoRoute(
      path: '/live-tracking',
      builder: (_, state) => liveTrackingPage(state.extra),
    ),
    GoRoute(
      path: '/user-profile',
      builder: (_, __) => const UserProfileScreen(),
    ),
    GoRoute(
      path: '/mechanic-home',
      builder: (_, __) => const MechanicHomeWrapper(),
    ),
    GoRoute(
      path: '/new-request-detail',
      builder: (_, state) {
        return opportunityPage(state.extra);
      },
    ),
    GoRoute(
      path: '/submit-bid',
      builder: (_, state) {
        return opportunityPage(state.extra, submit: true);
      },
    ),
    GoRoute(
      path: '/job-in-progress',
      builder: (context, state) => jobInProgressPage(state.extra),
    ),
    GoRoute(
      path: '/active-job',
      builder: (_, state) {
        return activeJobPage(state.extra);
      },
    ),
    GoRoute(
      path: '/rate-review',
      builder: (_, state) {
        return rateReviewPage(state.extra);
      },
    ),
    GoRoute(
      path: '/job-history',
      builder: (_, __) => const JobHistoryScreen(),
    ),
    GoRoute(
      path: '/mechanic-profile-edit',
      builder: (_, __) => const MechanicProfileEditScreen(),
    ),
    GoRoute(
      path: '/mechanic-history',
      builder: (_, __) => const JobHistoryScreen(mechanic: true),
    ),
    GoRoute(
      path: '/mechanic-earnings',
      builder: (_, __) => const MechanicEarningsScreen(),
    ),
    GoRoute(
      path: '/document-upload',
      builder: (_, __) => const DocumentUploadScreen(),
    ),
    GoRoute(
      path: '/mechanic-ratings',
      builder: (_, __) => const MechanicRatingsScreen(),
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
    JobHistoryScreen(),
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
