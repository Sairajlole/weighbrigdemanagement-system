import 'package:weighbridgemanagement/shared/services/platform_service.dart';

class WeighmentAudio {
  static Future<void> playCapture() async {
    await PlatformService.playSound(SoundType.capture);
  }

  static Future<void> playComplete() async {
    await PlatformService.playSound(SoundType.complete);
  }

  static Future<void> playError() async {
    await PlatformService.playSound(SoundType.error);
  }
}
