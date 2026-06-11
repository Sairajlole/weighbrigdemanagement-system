import 'package:weighbridgemanagement/shared/services/platform_service.dart';

class WeighmentAudio {
  static Future<void> playCapture() async {
    // Weight-lock / capture sound intentionally disabled (no sound on locking).
  }

  static Future<void> playComplete() async {
    await PlatformService.playSound(SoundType.complete);
  }

  static Future<void> playError() async {
    await PlatformService.playSound(SoundType.error);
  }
}
