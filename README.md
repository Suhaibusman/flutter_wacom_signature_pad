# flutter_wacom_signature_pad

Windows-only Flutter plugin for Wacom STU-540 signature pads. It captures pen
strokes from the device, renders a PNG signature, and can return Base64 or save
to file.

## Publisher
- Developer: Muhammad Suhaib
- Concept: Mustafa Ali Bamboat

## Features
- Detect connected Wacom STU device
- Capture pen strokes and signature
- Return PNG bytes or Base64
- Clear signature
- Save signature to file
- Callback when signing is complete

## Requirements
- Windows desktop app (Flutter Windows)
- Wacom STU SDK installed (C++ and C components)

## SDK Setup
By default, the plugin uses:
- `C:/Program Files (x86)/Wacom STU SDK/cpp`
- `C:/Program Files (x86)/Wacom STU SDK/C`

You can override these with environment variables:
- `WACOM_STU_SDK_DIR` for the C++ SDK root
- `WACOM_STU_C_SDK_DIR` for the C SDK root

## Usage
```dart
import 'package:flutter/material.dart';
import 'package:flutter_wacom_signature_pad/flutter_wacom_signature_pad.dart';

class MySignaturePage extends StatelessWidget {
  MySignaturePage({super.key});

  final controller = WacomSignaturePadController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        WacomSignaturePad(
          width: 400,
          height: 200,
          controller: controller,
          onSigned: (Uint8List imageBytes) {
            // handle PNG bytes
          },
          onSignedBase64: (String base64) {
            // handle Base64
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton(
              onPressed: () => controller.clear(),
              child: const Text('Clear'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => controller.saveToFile('signature.png'),
              child: const Text('Save to File'),
            ),
          ],
        ),
      ],
    );
  }
}
```

## Detect Device
```dart
final controller = WacomSignaturePadController();
final isConnected = await controller.detectDevice();
```

## Notes
- The plugin is Windows-only and expects a Wacom STU device to be connected.
- The signature surface shown on the device can be customized via widget
  properties (`deviceTitle`, `deviceHint`, etc.).

