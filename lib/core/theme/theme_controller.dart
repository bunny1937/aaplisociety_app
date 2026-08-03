import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// App-wide theme mode holder.
//
// WAS: `ValueNotifier<ThemeMode>(ThemeMode.light)` with a toggleTheme() that
// flipped it and persisted NOTHING, so the switch on the Profile screen silently
// reset to light on every cold start. It also never followed the OS, so a phone
// in system dark mode still got a light app.
//
// NOW: three real states - system / light / dark - restored from disk on boot.
//
// Worth knowing: the login screen, splash and the flat picker sheet are dark by
// DESIGN (AppColors.ink #0E1A44 and the #141C3A -> #0D1430 sheet gradient).
// They look dark in light mode too. That is not this notifier misbehaving.

const _kThemeKey = 'theme_mode';
const _storage = FlutterSecureStorage();

final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Call once from main() BEFORE runApp so the first frame is already correct.
/// Without this the app paints light for a frame and then snaps to dark.
Future<void> restoreThemeMode() async {
  try {
    final raw = await _storage.read(key: _kThemeKey);
    themeModeNotifier.value = _decode(raw);
  } catch (_) {
    // Secure storage can throw on a freshly wiped keystore. Falling back to
    // system is strictly better than crashing on boot.
    themeModeNotifier.value = ThemeMode.system;
  }
}

Future<void> setThemeMode(ThemeMode mode) async {
  themeModeNotifier.value = mode;
  try {
    await _storage.write(key: _kThemeKey, value: _encode(mode));
  } catch (_) {
    // A failed write must not undo the visible change the user just made.
  }
}

/// Kept for the existing call sites in member_profile_page.dart and
/// tenant_profile_page.dart. Cycles light -> dark -> system -> light so the
/// "follow my phone" option is reachable without a new settings screen.
Future<void> toggleTheme() async {
  switch (themeModeNotifier.value) {
    case ThemeMode.light:
      await setThemeMode(ThemeMode.dark);
    case ThemeMode.dark:
      await setThemeMode(ThemeMode.system);
    case ThemeMode.system:
      await setThemeMode(ThemeMode.light);
  }
}

String themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'Match phone',
    };

ThemeMode _decode(String? raw) => switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

String _encode(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
