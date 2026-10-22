import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onraasta/core/navigation/app_back_button_dispatcher.dart';
import 'package:onraasta/core/widgets/home_tab_scaffold.dart';

void main() {
  late GoRouter router;
  late int exitCalls;

  setUp(() {
    exitCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exitCalls++;
      return null;
    });
    router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const HomeTabScaffold(
          pages: [
            Text('Home page'),
            Text('History page'),
            Text('Profile page')
          ],
          items: [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.history), label: 'History'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          ],
          backgroundColor: Colors.white,
          navigationColor: Colors.white,
          selectedColor: Colors.blue,
          unselectedColor: Colors.grey,
        ),
      ),
      GoRoute(
        path: '/detail',
        builder: (_, __) => const Scaffold(body: Text('Detail page')),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(body: Text('Login page')),
      ),
    ]);
  });

  tearDown(() {
    router.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(
      routerDelegate: router.routerDelegate,
      routeInformationParser: router.routeInformationParser,
      routeInformationProvider: router.routeInformationProvider,
      backButtonDispatcher: AppBackButtonDispatcher(router),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(exitCalls, 0);
    expect(tester.takeException(), isNull);
  }

  testWidgets('system Back retraces tabs and stays in the app at Home',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    // Selecting the current tab must not add another Back step.
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('History page'), findsOneWidget);
    await back(tester);
    expect(find.text('Home page'), findsOneWidget);
    await back(tester);
    expect(find.text('Home page'), findsOneWidget);
  });

  testWidgets('system Back pops detail before retracing underlying tabs',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    router.push('/detail');
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('Profile page'), findsOneWidget);
    expect(find.text('Detail page'), findsNothing);
    await back(tester);
    expect(find.text('Home page'), findsOneWidget);
  });

  testWidgets('system Back dismisses a dialog before changing tabs',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    showDialog<void>(
      context: router.routerDelegate.navigatorKey.currentContext!,
      builder: (_) => const AlertDialog(content: Text('Confirm action')),
    );
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('Confirm action'), findsNothing);
    expect(find.text('History page'), findsOneWidget);
    await back(tester);
    expect(find.text('Home page'), findsOneWidget);
  });

  testWidgets('a cleared session stack cannot return to home or exit the app',
      (tester) async {
    await open(tester);
    router.push('/detail');
    await tester.pumpAndSettle();
    router.go('/login');
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('Login page'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });
}
