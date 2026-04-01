## 0.1.5

* Add `PdfSignatureScreen` widget — load a PDF by URL, draw a signature box on
  any page, capture ink from the Wacom device or mouse, embed the signature
  transparently, and save the signed copy to disk.
* Add `WacomPdfSignature` FlutterFlow custom widget — same PDF signing flow
  parameterised by `mlrCode`, `pdfUrl`, `outputFileName`, and `apiUrl`; posts
  the signed PDF as a base64 JSON payload and surfaces a boolean result via
  `onSaveResult`.
* Fix signature-position accuracy: coordinate mapping now derives the
  pixel-per-point scale from the actual viewer widget width instead of a fixed
  96/72 DPI ratio.
* Fix signature embedded with white background — `backgroundColor` now defaults
  to `Colors.transparent` so the PDF content shows through the ink.
* Add auto-connect on startup: device is detected and connected automatically
  without requiring a manual button press.
* Update example app with a landing page that routes to either the PDF signing
  flow or the raw device test harness.

## 0.1.4

* Add updated PDF signing integration support for the package app example.
* Add Flutter 3.38.5 compatibility constraints.

## 0.1.3

* Bump version for pub.dev release.

## 0.1.2

* Refresh documentation and metadata for the package release.

## 0.1.1

* Add API documentation and publisher info.
* Clean up unused imports.

## 0.1.0

* Initial Windows-only release for Wacom STU-540 signature capture.
