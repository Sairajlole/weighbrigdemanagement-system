#ifndef RUNNER_WEBCAM_PLUGIN_H_
#define RUNNER_WEBCAM_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mfobjects.h>

#include <memory>
#include <vector>
#include <mutex>

class WebcamPlugin {
 public:
  static void Register(flutter::BinaryMessenger* messenger);
  WebcamPlugin();
  ~WebcamPlugin();

 private:

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void StartCamera(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void CaptureFrame(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void StopCamera(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  IMFSourceReader* source_reader_ = nullptr;
  std::vector<uint8_t> latest_jpeg_;
  std::mutex frame_mutex_;
  bool camera_active_ = false;
};

#endif  // RUNNER_WEBCAM_PLUGIN_H_
