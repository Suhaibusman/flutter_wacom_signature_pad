cmake_minimum_required(VERSION 3.14)
project(flutter_wacom_signature_pad LANGUAGES CXX)

if(DEFINED ENV{WACOM_STU_SDK_DIR})
  set(WACOM_SDK_DIR "$ENV{WACOM_STU_SDK_DIR}")
else()
  set(WACOM_SDK_DIR "C:/Program Files (x86)/Wacom STU SDK/cpp")
endif()

if(DEFINED ENV{WACOM_STU_C_SDK_DIR})
  set(WACOM_C_SDK_DIR "$ENV{WACOM_STU_C_SDK_DIR}")
else()
  set(WACOM_C_SDK_DIR "C:/Program Files (x86)/Wacom STU SDK/C")
endif()

add_library(flutter_wacom_signature_pad_plugin SHARED
  "flutter_wacom_signature_pad_plugin.cpp"
  "flutter_wacom_signature_pad_plugin_c_api.cpp"
)

apply_standard_settings(flutter_wacom_signature_pad_plugin)

target_compile_definitions(flutter_wacom_signature_pad_plugin PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(flutter_wacom_signature_pad_plugin PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${WACOM_SDK_DIR}/include"
)

# Add SDK source files
target_sources(flutter_wacom_signature_pad_plugin PRIVATE
  "${WACOM_SDK_DIR}/src/STU/cpp/Tablet.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/Protocol.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/ProtocolHelper.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/Interface.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/InterfaceImpl.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/InterfaceQueue.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/ReportHandler.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/getUsbDevices.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/Win32/UsbInterface.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/Win32/getUsbDevices_Win32.cpp"
  "${WACOM_SDK_DIR}/src/STU/cpp/Win32/ProtocolHelper_Win32_WIC.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/error_win32api.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/winusb.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/wstringConvert.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/error_NTSTATUS.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/error_HRESULT.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/error_CONFIGRET.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/getDevicePowerState.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/com.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/dliHook.cpp"
  "${WACOM_SDK_DIR}/src/Win32/cpp/msvc.cpp"
  "${WACOM_SDK_DIR}/src/utility/cpp/Win32/setThreadName.cpp"
  "${WACOM_SDK_DIR}/src/utility/cpp/Win32/enumUsbDevices.cpp"
  "${WACOM_SDK_DIR}/src/utility/cpp/Win32/enumDevices.cpp"
)

target_link_directories(flutter_wacom_signature_pad_plugin PRIVATE
  "${WACOM_C_SDK_DIR}/lib/x64"
)

target_link_libraries(flutter_wacom_signature_pad_plugin PRIVATE
  flutter
  flutter_wrapper_plugin
  setupapi
  winusb
  shlwapi
  windowscodecs
  ole32
  oleaut32
  user32
  gdi32
)

target_compile_options(flutter_wacom_signature_pad_plugin PRIVATE /wd4267 /wd4244 /wd4834)

set_target_properties(flutter_wacom_signature_pad_plugin PROPERTIES
  CXX_STANDARD 17
)

set(flutter_wacom_signature_pad_bundled_libraries
  ""
)
