#include "include/flutter_wacom_signature_pad/flutter_wacom_signature_pad_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_wacom_signature_pad_plugin.h"

void FlutterWacomSignaturePadPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  FlutterWacomSignaturePadPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
