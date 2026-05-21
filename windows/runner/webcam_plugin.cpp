#include "webcam_plugin.h"

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <wmcodecdsp.h>
#include <shlwapi.h>

#include <vector>
#include <mutex>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mf.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "shlwapi.lib")

template <class T>
void SafeRelease(T** ppT) {
    if (*ppT) {
        (*ppT)->Release();
        *ppT = nullptr;
    }
}

WebcamPlugin::WebcamPlugin() {}

WebcamPlugin::~WebcamPlugin() {
    SafeRelease(&source_reader_);
    if (camera_active_) {
        MFShutdown();
        camera_active_ = false;
    }
}

void WebcamPlugin::Register(flutter::FlutterEngine* engine) {
    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        engine->messenger(), "com.weighbridge/webcam",
        &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<WebcamPlugin>();
    auto* plugin_ptr = plugin.get();

    channel->SetMethodCallHandler(
        [plugin_ptr](const flutter::MethodCall<flutter::EncodableValue>& call,
                     std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            plugin_ptr->HandleMethodCall(call, std::move(result));
        });

    // prevent channel/plugin from being destroyed
    // leak intentionally — lives for app lifetime
    channel.release();
    plugin.release();
}

void WebcamPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() == "startCamera") {
        StartCamera(std::move(result));
    } else if (call.method_name() == "captureFrame") {
        CaptureFrame(std::move(result));
    } else if (call.method_name() == "stopCamera") {
        StopCamera(std::move(result));
    } else {
        result->NotImplemented();
    }
}

void WebcamPlugin::StartCamera(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    if (camera_active_) {
        result->Success(flutter::EncodableValue(true));
        return;
    }

    HRESULT hr = MFStartup(MF_VERSION);
    if (FAILED(hr)) {
        result->Error("INIT_ERROR", "Failed to initialize Media Foundation");
        return;
    }

    IMFAttributes* attributes = nullptr;
    hr = MFCreateAttributes(&attributes, 1);
    if (FAILED(hr)) {
        MFShutdown();
        result->Error("INIT_ERROR", "Failed to create attributes");
        return;
    }

    hr = attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                             MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);

    IMFActivate** devices = nullptr;
    UINT32 count = 0;
    hr = MFEnumDeviceSources(attributes, &devices, &count);
    SafeRelease(&attributes);

    if (FAILED(hr) || count == 0) {
        if (devices) CoTaskMemFree(devices);
        MFShutdown();
        result->Error("NO_CAMERA", "No camera found");
        return;
    }

    IMFMediaSource* source = nullptr;
    hr = devices[0]->ActivateObject(IID_PPV_ARGS(&source));
    for (UINT32 i = 0; i < count; i++) devices[i]->Release();
    CoTaskMemFree(devices);

    if (FAILED(hr)) {
        MFShutdown();
        result->Error("INIT_ERROR", "Failed to activate camera");
        return;
    }

    IMFAttributes* readerAttrs = nullptr;
    MFCreateAttributes(&readerAttrs, 1);

    hr = MFCreateSourceReaderFromMediaSource(source, readerAttrs, &source_reader_);
    SafeRelease(&readerAttrs);
    SafeRelease(&source);

    if (FAILED(hr)) {
        MFShutdown();
        result->Error("INIT_ERROR", "Failed to create source reader");
        return;
    }

    // Configure output to RGB32
    IMFMediaType* mediaType = nullptr;
    MFCreateMediaType(&mediaType);
    mediaType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    mediaType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    source_reader_->SetCurrentMediaType(
        (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, mediaType);
    SafeRelease(&mediaType);

    camera_active_ = true;
    result->Success(flutter::EncodableValue(true));
}

void WebcamPlugin::CaptureFrame(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    if (!camera_active_ || !source_reader_) {
        result->Error("NO_FRAME", "Camera not active");
        return;
    }

    DWORD streamIndex, flags;
    LONGLONG timestamp;
    IMFSample* sample = nullptr;

    HRESULT hr = source_reader_->ReadSample(
        (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,
        0, &streamIndex, &flags, &timestamp, &sample);

    if (FAILED(hr) || !sample) {
        if (sample) sample->Release();
        result->Error("NO_FRAME", "Failed to read frame");
        return;
    }

    IMFMediaBuffer* buffer = nullptr;
    hr = sample->ConvertToContiguousBuffer(&buffer);
    if (FAILED(hr)) {
        SafeRelease(&buffer);
        sample->Release();
        result->Error("ENCODE_ERROR", "Failed to get buffer");
        return;
    }

    BYTE* rawData = nullptr;
    DWORD maxLen = 0, curLen = 0;
    hr = buffer->Lock(&rawData, &maxLen, &curLen);
    if (FAILED(hr)) {
        SafeRelease(&buffer);
        sample->Release();
        result->Error("ENCODE_ERROR", "Failed to lock buffer");
        return;
    }

    // Get frame dimensions from media type
    IMFMediaType* currentType = nullptr;
    source_reader_->GetCurrentMediaType(
        (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, &currentType);

    UINT32 width = 0, height = 0;
    MFGetAttributeSize(currentType, MF_MT_FRAME_SIZE, &width, &height);
    SafeRelease(&currentType);

    // Create BMP in memory and convert to simple format
    // For simplicity, encode as BMP (Flutter's Image.memory handles BMP)
    const int rowSize = width * 4;
    const int imageSize = rowSize * height;
    const int headerSize = 54;
    const int fileSize = headerSize + imageSize;

    std::vector<uint8_t> bmp(fileSize);
    // BMP header
    bmp[0] = 'B'; bmp[1] = 'M';
    *reinterpret_cast<uint32_t*>(&bmp[2]) = fileSize;
    *reinterpret_cast<uint32_t*>(&bmp[10]) = headerSize;
    // DIB header
    *reinterpret_cast<uint32_t*>(&bmp[14]) = 40;
    *reinterpret_cast<int32_t*>(&bmp[18]) = width;
    *reinterpret_cast<int32_t*>(&bmp[22]) = -(int32_t)height; // top-down
    *reinterpret_cast<uint16_t*>(&bmp[26]) = 1;
    *reinterpret_cast<uint16_t*>(&bmp[28]) = 32;
    *reinterpret_cast<uint32_t*>(&bmp[34]) = imageSize;

    memcpy(&bmp[headerSize], rawData, min((DWORD)imageSize, curLen));

    buffer->Unlock();
    SafeRelease(&buffer);
    sample->Release();

    result->Success(flutter::EncodableValue(bmp));
}

void WebcamPlugin::StopCamera(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    SafeRelease(&source_reader_);
    if (camera_active_) {
        MFShutdown();
        camera_active_ = false;
    }
    {
        std::lock_guard<std::mutex> lock(frame_mutex_);
        latest_jpeg_.clear();
    }
    result->Success(flutter::EncodableValue(true));
}
