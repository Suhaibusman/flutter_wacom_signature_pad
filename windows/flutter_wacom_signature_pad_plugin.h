#pragma once

#ifndef NOCRYPT
#define NOCRYPT
#endif

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <memory>

// Forward declarations
namespace WacomGSS {
  namespace STU {
    class Tablet;
    class UsbInterface;
  }
}

namespace wgssSTU = WacomGSS::STU;

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <thread>
#include <atomic>
#include <mutex>
#include <queue>
#include <optional>
#include <windows.h>

class FlutterWacomSignaturePadPlugin : public flutter::Plugin, public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  FlutterWacomSignaturePadPlugin();
  virtual ~FlutterWacomSignaturePadPlugin();

  // StreamHandler implementation
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnListenInternal(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) override;

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancelInternal(
      const flutter::EncodableValue* arguments) override;

 private:
  void StartReportThread();
  void StopReportThread();
  void ClearScreen();

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<WacomGSS::STU::Tablet> tablet;
  std::unique_ptr<WacomGSS::STU::UsbInterface> usbInterface;
  
  // Threading
  std::thread reportThread;
  std::atomic<bool> keepRunning;
  
  // Event Sink
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> eventSink;
  std::mutex sinkMutex;

  // Thread-safe event queue
  std::queue<flutter::EncodableValue> eventQueue;
  std::mutex queueMutex;
  
  // Windows message handling
  HWND hwnd = nullptr;
  int windowId = -1;
  std::optional<LRESULT> HandleWindowProc(
      HWND windowArg,
      UINT message,
      WPARAM wparam,
      LPARAM lparam);
};
