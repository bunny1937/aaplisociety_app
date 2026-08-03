import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// App-wide theme mode holder.
//
// ---------------------------------------------------------------------------
// WHY THE SWITCH WAS INSANE
// ---------------------------------------------------------------------------
// The controller has THREE states (system / light / dark). The Profile screen
// renders a TWO-state Switch:
//
//     value: mode == ThemeMode.dark          <- member_profile_page.dart:180
//     onChanged: (_) => toggleTheme()        <- cycles light -> dark -> system
//
// A 3-state machine behind a 2-state control. Every symptom follows exactly:
//
//   Boot     mode=system, phone is dark -> app DARK, switch reads OFF
//            ("it came as dark but the toggle is off")
//   Tap 1    system -> light            -> app LIGHT, switch still OFF
//            ("tap again nothing happened" - the switch never moved)
//   Tap 2    light  -> dark             -> app DARK,  switch ON      (correct)
//   Tap 3    dark   -> system, phone dark -> app stays DARK, switch OFF
//            ("when I off it nothing happens")
//   Tap 4    system -> light            -> app LIGHT, switch OFF
//            ("when I on it, it changes to light but dark mode is on")
//
// Nothing was random. The switch reported `mode == dark` while the app was
// painting the RESOLVED brightness, and those two differ whenever mode is
// system.
//
// THE FIX: the switch is now genuinely binary. `isDarkNow(context)` answers
// "is the app dark ON SCREEN right now", resolving system against the real
// platform brightness, and setDark() writes an explicit light/dark. The
// three-way cycle stays reachable, but from its own row, not from a 2-state
// switch that cannot represent it.
//
// Worth knowing: the login screen, splash and the flat picker sheet are dark by
// DESIGN (AppColors.ink #0E1A44 and the #141C3A -> #0D1430 sheet gradient).
// They look dark in light mode too. That is not this notifier misbehaving.

const _kThemeKey = 'theme_mode';
const _storage = FlutterSecureStorage();

/// Default is `system` so a phone in dark mode gets a dark app on first launch.
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

/// The OS-level brightness, read WITHOUT needing a BuildContext so it also
/// works before the first frame.
bool get platformIsDark =>
    SchedulerBinding.instance.platformDispatcher.platformBrightness ==
    Brightness.dark;

/// **Is the app dark on screen right now?**
///
/// This - not `mode == ThemeMode.dark` - is what a binary "Dark mode" switch
/// must bind to. When mode is `system` the answer depends on the phone, and
/// binding to the enum instead of the resolved brightness is the entire bug.
///
/// Pass a context when you have one so the widget rebuilds on an OS theme
/// change; it falls back to the platform dispatcher when you do not.
bool isDarkNow([BuildContext? context]) {
  switch (themeModeNotifier.value) {
    case ThemeMode.dark:
      return true;
    case ThemeMode.light:
      return false;
    case ThemeMode.system:
      return context != null
          ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
          : platformIsDark;
  }
}

/// Explicit, unambiguous setter for the binary switch. No cycling, no surprise
/// third state: flipping the switch to ON always means dark, OFF always means
/// light, and both are pinned so the OS can no longer override the choice.
Future<void> setDark(bool dark) =>
    setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);

/// Hand control back to the OS.
Future<void> followSystem() => setThemeMode(ThemeMode.system);

/// Kept so any remaining call site still compiles. Cycles
/// light -> dark -> system -> light.
///
/// Do NOT wire this to a two-state Switch - that is what broke. Use
/// `setDark()` there and give `followSystem()` its own row.
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
