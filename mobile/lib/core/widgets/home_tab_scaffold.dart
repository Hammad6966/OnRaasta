import 'package:flutter/material.dart';

/// Retains each tab's state and retraces tab selections on system Back.
class HomeTabScaffold extends StatefulWidget {
  const HomeTabScaffold({
    super.key,
    required this.pages,
    required this.items,
    required this.backgroundColor,
    required this.navigationColor,
    required this.selectedColor,
    required this.unselectedColor,
  });

  final List<Widget> pages;
  final List<BottomNavigationBarItem> items;
  final Color backgroundColor;
  final Color navigationColor;
  final Color selectedColor;
  final Color unselectedColor;

  @override
  State<HomeTabScaffold> createState() => _HomeTabScaffoldState();
}

class _HomeTabScaffoldState extends State<HomeTabScaffold> {
  final _history = <int>[0];

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _history.length > 1) {
            setState(() => _history.removeLast());
          }
        },
        child: Scaffold(
          backgroundColor: widget.backgroundColor,
          body: IndexedStack(index: _history.last, children: widget.pages),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _history.last,
            onTap: (index) {
              if (index != _history.last) {
                setState(() => _history.add(index));
              }
            },
            backgroundColor: widget.navigationColor,
            selectedItemColor: widget.selectedColor,
            unselectedItemColor: widget.unselectedColor,
            items: widget.items,
          ),
        ),
      );
}
