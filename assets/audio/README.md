# assets/audio/

This folder exists so `pubspec.yaml`'s `- assets/audio/` entry resolves. Flutter
warns about a declared asset directory that is not present on disk, and an empty
folder does not survive a git commit -- hence this file.

## sos_alarm.mp3 -- the one file you need to add

Drop a file named exactly `sos_alarm.mp3` next to this README.

- Any loud, harsh, looping-friendly alarm tone. 5-15 seconds is ideal; the player
  loops it (`ReleaseMode.loop`) until somebody presses STOP or acknowledges.
- Avoid a long fade-in or a quiet intro. The first second is the one that has to
  wake somebody up.
- Free sources: the `notification`/`alarm` category on Pixabay or Mixkit, both
  usable commercially without attribution.

**If you never add it, nothing breaks.** `SosAlarm.ring()` catches the missing
asset, logs it, and still vibrates and shows the full-width red banner. You lose
the audio, which is the part that works through a pocket -- so it is worth the
two minutes.
