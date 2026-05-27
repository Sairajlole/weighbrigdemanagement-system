import 'dart:io';

import 'package:flutter/services.dart';

class WeighmentAudio {
  static Future<void> playCapture() async {
    if (Platform.isMacOS) {
      Process.run('afplay', ['/System/Library/Sounds/Glass.aiff']);
    } else if (Platform.isWindows) {
      Process.run('powershell', ['-c', r'(New-Object Media.SoundPlayer "C:\Windows\Media\Windows Navigation Start.wav").PlaySync()']);
    } else {
      SystemSound.play(SystemSoundType.click);
    }
  }

  static Future<void> playComplete() async {
    if (Platform.isMacOS) {
      Process.run('afplay', ['/System/Library/Sounds/Hero.aiff']);
    } else if (Platform.isWindows) {
      Process.run('powershell', ['-c', r'(New-Object Media.SoundPlayer "C:\Windows\Media\Windows Print complete.wav").PlaySync()']);
    } else {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  static Future<void> playError() async {
    if (Platform.isMacOS) {
      Process.run('afplay', ['/System/Library/Sounds/Basso.aiff']);
    } else if (Platform.isWindows) {
      Process.run('powershell', ['-c', r'(New-Object Media.SoundPlayer "C:\Windows\Media\Windows Critical Stop.wav").PlaySync()']);
    } else {
      SystemSound.play(SystemSoundType.alert);
    }
  }
}
