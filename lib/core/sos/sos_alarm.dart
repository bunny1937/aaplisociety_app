import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../logging/app_logger.dart';

/// Rings, vibrates and keeps doing both until a human acknowledges it.
///
/// Why this exists as its own service rather than "a push notification with a
/// sound": FCM cannot override silent mode. A notification's sound is played by
/// the OS through the NOTIFICATION audio stream, which is exactly the stream
/// that silent/DND mutes. The only way to be heard on a silenced phone is to
/// play audio ourselves on the ALARM stream (`AndroidAudioUsage.alarm`), which
/// is what an alarm clock app does and what the OS deliberately exempts from
/// silent mode. That is the whole trick, and it has to happen in Dart with a
/// real audio player - no server-side payload can do it.
///
/// Behaviour:
///   * loops the alarm asset at full volume on the alarm stream
///   * vibrates in a repeating pattern in parallel (for a phone in a pocket)
///   * shows an indefinite banner with a STOP action
///   * only [stop] silences it - it never times out on its own
///
/// Requires (see pubspec.yaml): `audioplayers`, `vibration`, and an asset at
/// `assets/audio/sos_alarm.mp3`. If the asset is missing the vibration and the
/// banner still fire, so a missing file degrades instead of failing silently.
class SosAlarm {
  SosAlarm._();
  static final SosAlarm instance = SosAlarm._();

  static const _asset = 'audio/sos_alarm.mp3';

  final AudioPlayer _player = AudioPlayer();
  bool _ringing = false;
  Timer? _vibrateTimer;

  bool get isRinging => _ringing;

  /// Starts the alarm. Safe to call repeatedly - a second SOS while one is
  /// already ringing updates nothing and does not stack a second sound.
  ///
  /// [messengerKey] is the app's ScaffoldMessenger key (see main.dart). It is
  /// passed in rather than imported so this service stays free of app-level
  /// dependencies and is testable.
  Future<void> ring({
    required GlobalKey<ScaffoldMessengerState> messengerKey,
    String? flatLabel,
    String? reason,
  }) async {
    if (_ringing) return;
    _ringing = true;

    // Vibrate first: it is the cheapest signal and needs no asset, so if audio
    // fails for any reason the phone is already buzzing.
    _startVibrating();

    try {
      // ReleaseMode.loop = keep going until stopped. AudioContext puts us on
      // the alarm stream so silent mode does not apply, and asks the OS for
      // exclusive focus so music/video ducks out of the way.
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gainTransientExclusive,
          ),
          // Not const: AudioContextIOS takes a Set of options and its
          // constructor is not a const constructor in audioplayers 6.x.
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.duckOthers},
          ),
        ),
      );
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource(_asset));
    } catch (e, st) {
      // Missing asset, no audio route, emulator without audio - the alert must
      // still be delivered, so we log and carry on with vibration + banner.
      AppLogger.error('[sos] alarm audio failed, falling back to vibration only',
          error: e, stackTrace: st);
    }

    final where = (flatLabel == null || flatLabel.isEmpty) ? '' : ' \u00b7 $flatLabel';
    final why = (reason == null || reason.isEmpty) ? '' : '\n$reason';
    messengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFE0392C),
          // Indefinite on purpose. An SOS that dismisses itself after 4 seconds
          // is not an SOS.
          duration: const Duration(days: 1),
          content: Text(
            'EMERGENCY$where$why',
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: Colors.white),
          ),
          action: SnackBarAction(
            label: 'STOP',
            textColor: Colors.white,
            onPressed: () => stop(messengerKey: messengerKey),
          ),
        ),
      );
  }

  /// Silences the alarm. This is the acknowledgement.
  Future<void> stop({
    GlobalKey<ScaffoldMessengerState>? messengerKey,
  }) async {
    _ringing = false;
    _vibrateTimer?.cancel();
    _vibrateTimer = null;
    try {
      await Vibration.cancel();
    } catch (_) {
      // Device has no vibrator; nothing to cancel.
    }
    try {
      await _player.stop();
    } catch (e) {
      AppLogger.warn('[sos] failed to stop alarm audio: $e');
    }
    messengerKey?.currentState?.clearSnackBars();
  }

  /// Repeating buzz. `Vibration.vibrate(repeat:)` is not supported everywhere,
  /// so the pattern is re-armed on a timer instead - that works on every device
  /// that has a vibrator at all.
  void _startVibrating() {
    _vibrateTimer?.cancel();
    Future<void> buzz() async {
      try {
        // vibration 2.x returns a non-nullable bool here (it was `bool?` in
        // 1.x), so no null fallback.
        if (await Vibration.hasVibrator()) {
          await Vibration.vibrate(
            pattern: const [0, 600, 250, 600, 250, 600],
            intensities: const [0, 255, 0, 255, 0, 255],
          );
        }
      } catch (e) {
        AppLogger.warn('[sos] vibration unavailable: $e');
      }
    }

    buzz();
    _vibrateTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _ringing ? buzz() : null);
  }
}
