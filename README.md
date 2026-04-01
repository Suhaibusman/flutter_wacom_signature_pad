# flutter_wacom_signature_pad

Windows-only Flutter plugin for Wacom STU-540 signature pads.  
Captures pen strokes from the device, renders a transparent-background PNG
signature, and ships two higher-level widgets for full PDF signing workflows.

**Publisher:** Muhammad Suhaib — **Concept:** Mustafa Ali Bamboat

---

## Contents

1. [Requirements](#requirements)
2. [SDK Setup](#sdk-setup)
3. [Installation](#installation)
4. [WacomSignaturePad widget](#wacomsignaturepad-widget)
5. [WacomSignaturePadController](#wacomsignaturepadcontroller)
6. [PdfSignatureScreen widget](#pdfsignaturescreen-widget)
7. [WacomPdfSignature — FlutterFlow custom widget](#wacompdfsignature--flutterflow-custom-widget)
8. [Example app](#example-app)

---

## Requirements

| Requirement | Detail |
|---|---|
| Platform | Windows desktop only |
| Flutter | ≥ 3.27.0 (tested on 3.38.5) |
| Dart | ≥ 3.10.0 |
| Wacom STU SDK | Installed at default path (see below) |
| Device | Wacom STU-540 (or compatible STU series) |

---

## SDK Setup

The plugin links against the Wacom STU SDK at build time.  
Default search paths:

```
C:/Program Files (x86)/Wacom STU SDK/cpp
C:/Program Files (x86)/Wacom STU SDK/C
```

Override with environment variables before building:

```
WACOM_STU_SDK_DIR      → C++ SDK root
WACOM_STU_C_SDK_DIR    → C SDK root
```

---

## Installation

```yaml
# pubspec.yaml
dependencies:
  flutter_wacom_signature_pad: ^0.1.5
```

For the PDF signing widgets, also add:

```yaml
  syncfusion_flutter_pdfviewer: ^28.2.0
  syncfusion_flutter_pdf: ^28.2.0
  http: ^1.2.0
  path_provider: ^2.1.0   # only for PdfSignatureScreen (saves to disk)
```

---

## WacomSignaturePad widget

The core capture widget.  Renders a live preview on screen and simultaneously
drives the Wacom device display.

```dart
import 'package:flutter_wacom_signature_pad/flutter_wacom_signature_pad.dart';

final controller = WacomSignaturePadController();

WacomSignaturePad(
  width: 560,
  height: 220,
  controller: controller,
  onSigned: (Uint8List pngBytes) {
    // PNG bytes with transparent background
  },
  onSignedBase64: (String b64) {
    // base64-encoded PNG
  },
  onClear: () { /* pad was cleared */ },
  onCancel: () { /* user cancelled on device */ },
)
```

### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `width` | `double` | **required** | Width of the on-screen drawing area in logical pixels |
| `height` | `double` | **required** | Height of the on-screen drawing area in logical pixels |
| `controller` | `WacomSignaturePadController?` | `null` | Attach a controller for programmatic control |
| `onSigned` | `ValueChanged<Uint8List>?` | `null` | Called with PNG bytes when signature is applied |
| `onSignedBase64` | `ValueChanged<String>?` | `null` | Called with base64 PNG string when signature is applied |
| `onCancel` | `VoidCallback?` | `null` | Called when the user cancels on the device or UI |
| `onClear` | `VoidCallback?` | `null` | Called when the pad is cleared |
| `penColor` | `Color` | `Colors.black` | Ink colour for the on-screen preview |
| `strokeWidth` | `double` | `2.0` | Stroke width for the on-screen preview |
| `backgroundColor` | `Color` | `Colors.transparent` | Background of the drawing area; transparent = no fill in PNG |
| `showControls` | `bool` | `true` | Show Clear / Cancel / Apply buttons beneath the preview |
| `autoConnect` | `bool` | `true` | Connect to the device automatically on widget creation |
| `autoDisconnect` | `bool` | `true` | Disconnect automatically when the widget is disposed |
| `showDeviceIdleScreen` | `bool` | `true` | Show an idle screen on the device between signing sessions |
| `deviceIdleTitle` | `String` | `'Device Ready'` | Title text on the device idle screen |
| `deviceIdleSubtitle` | `String` | `'Please wait'` | Subtitle text on the device idle screen |
| `deviceTitle` | `String` | `'Sign here'` | Title text on the device signature screen |
| `deviceHint` | `String` | `'Please sign in the box'` | Hint inside the device signature box |
| `deviceClearLabel` | `String` | `'Clear'` | Label for the device Clear button |
| `deviceCancelLabel` | `String` | `'Cancel'` | Label for the device Cancel button |
| `deviceApplyLabel` | `String` | `'Apply'` | Label for the device Apply button |

---

## WacomSignaturePadController

`ChangeNotifier`-based controller for driving the widget programmatically.

```dart
final controller = WacomSignaturePadController();

// Attach to a WacomSignaturePad via the controller: parameter, then:

await controller.connect();          // connect to device
await controller.disconnect();       // disconnect from device
await controller.detectDevice();     // → bool, non-destructive check
await controller.clear();            // clear ink
final bytes  = await controller.toPngBytes();       // → Uint8List (PNG)
final b64    = await controller.toBase64();          // → String
final file   = await controller.saveToFile('sig.png'); // → File

bool connected = controller.isConnected;
bool hasInk    = controller.hasInk;
```

### Methods

| Method | Returns | Description |
|---|---|---|
| `connect()` | `Future<void>` | Connect to the Wacom device |
| `disconnect()` | `Future<void>` | Disconnect and show device idle screen |
| `detectDevice()` | `Future<bool>` | Detect a compatible device without connecting |
| `clear()` | `Future<void>` | Clear all ink and refresh the device screen |
| `toPngBytes()` | `Future<Uint8List>` | Render current strokes to a PNG (transparent background) |
| `toBase64()` | `Future<String>` | Render and base64-encode the PNG |
| `saveToFile(path)` | `Future<File>` | Render and write PNG to the given file path |

### Properties

| Property | Type | Description |
|---|---|---|
| `isConnected` | `bool` | Whether the device is currently connected |
| `hasInk` | `bool` | Whether the pad contains any strokes |

---

## PdfSignatureScreen widget

A full-screen widget that loads a PDF from a URL, lets the user draw a
signature box anywhere on the document, captures ink from the Wacom device
or mouse, overlays the signature in real-time, and saves a signed copy to the
Documents folder.

```dart
import 'package:flutter_wacom_signature_pad/flutter_wacom_signature_pad.dart';
// PDF dependencies must also be in pubspec.yaml (see Installation)

Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const PdfSignatureScreen()),
);
```

### Usage flow

1. Enter a PDF URL in the top bar and tap **Load PDF**.
2. The right panel auto-detects and connects the Wacom device on startup.
3. Tap **Draw Signature Box** then click-drag on the PDF to place the box.
4. Sign on the Wacom device (or draw with the mouse in the **Sign Here** pad).
5. Tap **Apply** to capture the ink.
6. Tap **Save Signed PDF** — the signed copy is written to the Documents
   folder as `signed_<timestamp>.pdf` and the path is shown in the panel.

### How coordinate mapping works

`SfPdfViewer` scales the first page to fill the viewport width at zoom=1.  
The widget derives the pixel-per-point scale as:

```
scale = (viewerWidth / page1WidthPt) × zoomLevel
```

`PdfViewerController.scrollOffset` is in rendered (zoomed) viewport pixels,
so the conversion to PDF points is:

```
pdfX = (viewerX + scroll.dx) / scale
pdfY = (viewerY + scroll.dy) / scale  −  accumulated page heights
```

The overlay box is recomputed on every scroll/zoom change via
`ListenableBuilder` so it stays pinned to the document.

### Signature transparency

`backgroundColor: Colors.transparent` is set on the `WacomSignaturePad`
capture widget, so the exported PNG has a transparent background.  
`PdfGraphics.drawImage` respects the PNG alpha channel, meaning only the ink
strokes appear in the saved PDF.

---

## WacomPdfSignature — FlutterFlow custom widget

A parameterised variant of the PDF signing flow designed to be dropped into a
FlutterFlow project as a custom widget.

### Extra dependencies (add in FlutterFlow → Settings → Pubspec)

```yaml
syncfusion_flutter_pdfviewer: ^28.2.0
syncfusion_flutter_pdf: ^28.2.0
http: ^1.2.0
flutter_wacom_signature_pad: ^0.1.5
```

### Widget parameters

| Parameter | FF Type | Required | Description |
|---|---|---|---|
| `width` | `double` | auto | Widget width (managed by FlutterFlow layout) |
| `height` | `double` | auto | Widget height (managed by FlutterFlow layout) |
| `mlrCode` | `String` | ✅ | Document / batch identifier sent to the API |
| `pdfUrl` | `String` | ✅ | Public HTTPS URL of the PDF to display |
| `outputFileName` | `String` | ✅ | Filename included in the API JSON payload |
| `apiUrl` | `String` | ✅ | HTTP POST endpoint that receives the signed PDF |

### Action callback

| Callback | Signature | Description |
|---|---|---|
| `onSaveResult` | `Future Function(bool success)` | Fired after the API responds; `true` = accepted, `false` = failed or error |

### API contract

The widget POSTs the following JSON to `apiUrl`:

```json
{
  "mlrCode":        "your-code",
  "outputFileName": "signed_document.pdf",
  "fileContent":    "JVBERi0xLjQ..."
}
```

`fileContent` is the signed PDF bytes encoded as **base64**.  
The widget reads the response as follows:

| Condition | Result |
|---|---|
| HTTP 2xx with no parseable body | `true` |
| HTTP 2xx + `{ "success": true }` | `true` |
| HTTP 2xx + `{ "ok": true }` | `true` |
| HTTP 2xx + `{ "success": false }` | `false` |
| HTTP 4xx / 5xx | `false` |
| Network error / timeout | `false` |

### Signing flow (same for both widgets)

```
① PDF loads automatically from pdfUrl on widget init
② Device auto-detected and connected on startup (no button press needed)
③ User taps [Draw Signature Box] → drags to place box on the PDF
④ User signs on Wacom device or draws on the on-screen pad
⑤ User taps [Apply] to capture ink as transparent PNG
⑥ User taps [Save Document] → widget builds signed PDF, POSTs to apiUrl,
   calls onSaveResult(true/false), and shows an inline result badge
```

### FlutterFlow setup steps

1. **Add dependencies** in FlutterFlow → Settings → Pubspec Dependencies  
   (see the four packages listed above).

2. **Create custom widget** — FlutterFlow → Custom Code → Custom Widgets →
   `+ Add Widget`.  Name it `WacomPdfSignature`.

3. **Paste the widget code** from
   `example/lib/wacom_pdf_signature_widget.dart` (the entire file content
   starting from `// Automatic FlutterFlow imports`).

4. **Add parameters** in the widget editor:

   | Name | Type | Required |
   |---|---|---|
   | `mlrCode` | String | ✅ |
   | `pdfUrl` | String | ✅ |
   | `outputFileName` | String | ✅ |
   | `apiUrl` | String | ✅ |

5. **Add action callback** `onSaveResult` with type `Future Function(bool)`.

6. **Drop the widget** onto any page, bind the four parameters to your
   FlutterFlow variables or app state values, and wire `onSaveResult` to
   whatever action you want (e.g. navigate to a success page, update a
   Firestore document, show a toast).

---

## Example app

The included example demonstrates both a standalone device test and the full
PDF signing flow.

### Run it

```bash
cd example
flutter run -d windows
```

### Landing page

The app opens on a home screen with two routes:

| Button | Screen | Purpose |
|---|---|---|
| **PDF Signature** | `PdfSignatureScreen` | Full PDF load → draw box → sign → save flow |
| **Device Test Harness** | `TestHomePage` | Low-level device control, raw PNG/Base64 export |

### PDF Signature screen walkthrough

```
1. Paste a PDF URL into the URL bar → tap [Load PDF]
   e.g. https://www.w3.org/WAI/WCAG21/wcag21.pdf

2. Right panel auto-connects the Wacom device (status turns green).
   If no device is present the status stays "Not connected" — you can
   still sign using the mouse on the on-screen pad.

3. Tap [Draw Signature Box] — cursor area turns blue-tinted.
   Click and drag on the PDF to draw the signature rectangle.
   A dashed border appears while dragging; a solid bordered box with
   corner handles appears after release.

4. Draw your signature in the [Sign Here] pad (or on the Wacom device).
   Tap [Apply] — a preview thumbnail appears below the pad.

5. Tap [Save Signed PDF] (green button, enabled only when all three
   steps above are complete).
   The signed PDF is saved to your Documents folder:
     Documents/signed_<timestamp>.pdf
   The full path is shown in the panel.
```

### Device Test Harness walkthrough

```
1. Tap [Detect Device] to check USB presence without connecting.
2. Tap [Connect] to establish the device session.
3. Draw in the signature pad (or on the device) and tap [Apply / Export].
4. Use [Save PNG to File] or [Copy Base64] for the captured signature.
5. Tap [Disconnect] when done.
```

---

## Notes

- The plugin is **Windows-only**. It throws `UnsupportedError` on other
  platforms at the point of connection.
- Signature PNG output has a **transparent background** when
  `backgroundColor: Colors.transparent` (the default). Set a solid colour
  if you need a filled background.
- The Wacom STU SDK must be installed before building — the C++ plugin links
  against its DLLs at compile time.
- For multi-page PDFs the inter-page gap in `SfPdfViewer` is treated as
  4 logical pixels; the first page's width is used as the scale reference.
  Both assumptions hold for standard A4/Letter documents.
