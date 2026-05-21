import 'dart:io';

import 'package:flutter/services.dart';

class WeighmentAudio {
  static Future<void> playCapture() async {
    if (Platform.isMacOS) {
      Process.run('afplay', ['/System/Library/Sounds/Glass.aiff']);
    } else {
      SystemSound.play(SystemSoundType.click);
    }
  }

  static Future<void> playComplete() async {
    if (Platform.isMacOS) {
      Process.run('afplay', ['/System/Library/Sounds/Hero.aiff']);
    } else {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  static Future<void> playError() async {
    if (Platform.isMacOS) {
      Process.run('afplay', ['/System/Library/Sounds/Basso.aiff']);
    } else {
      SystemSound.play(SystemSoundType.alert);
    }
  }
}
