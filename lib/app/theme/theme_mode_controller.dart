import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'fitnep_theme_mode';
  static const _storage = FlutterSecureStorage();
  bool _selected = false;
  @override
  ThemeMode build() {
    unawaited(_restore());
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    try {
      final value = await _storage.read(key: _key);
      if (!ref.mounted || _selected) return;
      state = switch (value) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      };
    } on Exception {
      /* System appearance works even without local storage. */
    }
  }

  void select(ThemeMode mode) {
    _selected = true;
    state = mode;
    unawaited(
      _storage.write(key: _key, value: mode.name).catchError((Object _) {}),
    );
  }
}

class ThemeModeButton extends ConsumerWidget {
  const ThemeModeButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      key: const Key('theme_mode_button'),
      tooltip: dark ? 'Use light theme' : 'Use dark theme',
      icon: Icon(
        dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: 22,
      ),
      onPressed: () => ref
          .read(themeModeProvider.notifier)
          .select(dark ? ThemeMode.light : ThemeMode.dark),
    );
  }
}
