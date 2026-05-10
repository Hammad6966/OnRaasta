import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kThemeModeKey = 'theme_mode';

final _secureStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

class ThemeNotifier extends StateNotifier<ThemeMode> {
  final FlutterSecureStorage _storage;

  ThemeNotifier(this._storage, {ThemeMode initial = ThemeMode.dark})
      : super(initial);

  /// Call once at startup to hydrate persisted preference.
  static Future<ThemeNotifier> create(FlutterSecureStorage storage) async {
    final raw = await storage.read(key: _kThemeModeKey);
    final initial = switch (raw) {
      'light'  => ThemeMode.light,
      'system' => ThemeMode.system,
      _        => ThemeMode.dark,
    };
    return ThemeNotifier(storage, initial: initial);
  }

  Future<void> toggleTheme() async {
    await setTheme(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    await _storage.write(key: _kThemeModeKey, value: mode.name);
  }
}

/// Async initialiser — override in ProviderScope before runApp when you need
/// the persisted value on first frame.
final themeInitProvider = FutureProvider<ThemeNotifier>((ref) async {
  final storage = ref.watch(_secureStorageProvider);
  return ThemeNotifier.create(storage);
});

/// Sync provider used throughout the widget tree.
/// Seeded with ThemeMode.dark; overridden by main() after async init.
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier(ref.watch(_secureStorageProvider));
});
