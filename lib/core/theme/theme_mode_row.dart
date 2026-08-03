import 'package:flutter/material.dart';
import '../../features/member/pulse/pulse.dart';
import 'haptics.dart';
import 'theme_controller.dart';

/// **Appearance rows for the Profile screen.**
///
/// Drop-in replacement for the broken `ValueListenableBuilder` block that lived
/// inline in member_profile_page.dart (lines 170-195) and tenant_profile_page.
///
/// The old block bound a two-state `Switch` to `mode == ThemeMode.dark` while
/// the app painted the RESOLVED brightness, and called `toggleTheme()`, which
/// cycles through three states. So the switch and the screen disagreed on every
/// other tap. Full explanation in theme_controller.dart.
///
/// Now:
///   * The switch reflects what is actually on screen (`isDarkNow(context)`).
///   * Flipping it writes an explicit light/dark - no third state, no cycling.
///   * "Match my phone" gets its own row, so the system option is reachable
///     without a 2-state control pretending to hold 3 values.
///   * MediaQuery.platformBrightnessOf(context) is read inside build, so if the
///     OS flips to dark while this screen is open the row updates with it.
class ThemeModeRows extends StatelessWidget {
  const ThemeModeRows({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        // Resolved, not the raw enum. This is the whole fix.
        final dark = isDarkNow(context);
        final following = mode == ThemeMode.system;

        return PulseGroup(
          children: [
            PulseRow(
              icon: dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              label: 'Dark mode',
              // Tells the user WHY the switch is where it is when the OS is
              // driving. Previously this state was invisible and looked broken.
              subtitle: following
                  ? (dark
                      ? 'On, following your phone'
                      : 'Off, following your phone')
                  : (dark ? 'Always dark' : 'Always light'),
              trailing: Switch(
                value: dark,
                onChanged: (want) {
                  Haptics.select();
                  // Explicit. ON is always dark, OFF is always light, and both
                  // pin the choice so the OS can no longer override it.
                  setDark(want);
                },
              ),
              onTap: () {
                Haptics.select();
                setDark(!dark);
              },
            ),
            PulseRow(
              icon: Icons.brightness_auto_rounded,
              label: 'Match my phone',
              subtitle: following
                  ? 'Following your system setting'
                  : 'Using your own choice',
              trailing: Switch(
                value: following,
                onChanged: (want) {
                  Haptics.select();
                  // Turning this OFF must not silently change what is on
                  // screen, so it pins the CURRENT resolved brightness.
                  if (want) {
                    followSystem();
                  } else {
                    setDark(dark);
                  }
                },
              ),
              onTap: () {
                Haptics.select();
                if (following) {
                  setDark(dark);
                } else {
                  followSystem();
                }
              },
            ),
          ],
        );
      },
    );
  }
}
