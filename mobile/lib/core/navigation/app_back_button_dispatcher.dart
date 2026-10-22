import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Keeps system Back inside the app, including when only a root page remains.
class AppBackButtonDispatcher extends RootBackButtonDispatcher {
  AppBackButtonDispatcher(this.router);

  final GoRouter router;

  @override
  Future<bool> didPopRoute() async {
    if (router.canPop()) {
      await super.didPopRoute();
    } else {
      // go_router 13 skips maybePop on its last page. Calling it here lets
      // that page's PopScope handle tab history before consuming root Back.
      await router.routerDelegate.navigatorKey.currentState?.maybePop();
    }
    return true;
  }
}
