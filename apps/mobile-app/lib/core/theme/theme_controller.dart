import 'package:flutter/material.dart';

// App-wide theme mode holder. Toggle it from the Profile screen.
final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

void toggleTheme() {
  themeModeNotifier.value =
      themeModeNotifier.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}
