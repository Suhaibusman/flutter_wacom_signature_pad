// ─────────────────────────────────────────────────────────────────────────────
// FlutterFlow Custom Widget — WacomPdfSignature
//
// Paste EVERYTHING below the "Begin custom widget code" marker into FlutterFlow.
//
// Dependencies to add in FlutterFlow → Settings → pubspec.yaml:
//   syncfusion_flutter_pdfviewer: ^28.2.0
//   syncfusion_flutter_pdf: ^28.2.0
//   http: ^1.2.0
//   flutter_wacom_signature_pad: ^0.1.4
//
// Widget parameters (define in FlutterFlow widget editor):
//   mlrCode        → String   (required)
//   pdfUrl         → String   (required)
//   outputFileName → String   (required)
//   apiUrl         → String   (required)
//
// Action callbacks (define in FlutterFlow widget editor):
//   onSaveResult   → receives bool (true = API accepted, false = failed)
//
// ─────────────────────────────────────────────────────────────────────────────

// Automatic FlutterFlow imports
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/custom_code/widgets/index.dart';
import '/flutter_flow/custom_functions.dart';
import 'package:flutter/material.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_wacom_signature_pad/flutter_wacom_signature_pad.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

// ── Widget ────────────────────────────────────────────────────────────────────

class WacomPdfSignature extends StatefulWidget {
  const WacomPdfSignature({
    super.key,
    this.width,
    this.height,
    required this.mlrCode,
    required this.pdfUrl,
    required this.outputFileName,
    required this.apiUrl,
    this.onSaveResult,
  });

  final double? width;
  final double? height;

  /// Identifier included in the JSON payload (e.g. a document / batch code).
  final String mlrCode;

  /// Public URL of the PDF to display and sign.
  final String pdfUrl;

  /// Filename sent to the API alongside the signed PDF bytes.
  final String outputFileName;

  /// HTTP POST endpoint.  Receives JSON:
  ///   { "mlrCode": "...", "outputFileName": "...", "fileContent": "[base64 PDF bytes]" }
  /// Must return HTTP 2xx for success.
  final String apiUrl;

  /// Called after the API responds.  `true` = accepted, `false` = failed.
  final Future Function(bool success)? onSaveResult;

  @override
  State<WacomPdfSignature> createState() => _WacomPdfSignatureState();
}

// ── State ─────────────────────────────────────────────────────────────────────

enum _DeviceState { idle, connecting, connected, error }

class _WacomPdfSignatureState extends State<WacomPdfSignature> {
  // Controllers
  final _pdfViewerController = PdfViewerController();
  final _wacomController = WacomSignaturePadController();

  // PDF
  Uint8List? _pdfBytes;
  bool _isLoadingPdf = true;
  String? _loadError;
  final Map<int, Size> _pageSizes = {};

  // Box drawing
  bool _isDrawingMode = false;
  Offset? _dragStart;
  Offset? _dragCurrent;

  // Stored in PDF-point space
  int _signaturePage = 1;
  Rect? _signatureBoxInPdf;

  // Signature capture
  Uint8List? _signatureBytes;

  // Device
  _DeviceState _deviceState = _DeviceState.idle;

  // Save/post state
  bool _isSaving = false;
  bool? _lastResult; // null = not yet saved, true = ok, false = failed

  // Viewer layout width (updated in LayoutBuilder)
  double _viewerWidth = 1.0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadPdf();
    _autoConnect();
  }

  @override
  void dispose() {
    _pdfViewerController.dispose();
    _wacomController.dispose();
    super.dispose();
  }

  // ── PDF loading ────────────────────────────────────────────────────────────

  Future<void> _loadPdf() async {
    setState(() {
      _isLoadingPdf = true;
      _loadError = null;
      _pdfBytes = null;
      _pageSizes.clear();
      _signatureBoxInPdf = null;
      _signatureBytes = null;
    });

    try {
      final response = await http.get(Uri.parse(widget.pdfUrl));
      if (response.statusCode == 200) {
        final doc = PdfDocument(inputBytes: response.bodyBytes);
        for (int i = 0; i < doc.pages.count; i++) {
          _pageSizes[i + 1] = doc.pages[i].size;
        }
        doc.dispose();
        setState(() {
          _pdfBytes = response.bodyBytes;
          _isLoadingPdf = false;
        });
      } else {
        setState(() {
          _loadError = 'HTTP ${response.statusCode}';
          _isLoadingPdf = false;
        });
      }
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _isLoadingPdf = false;
      });
    }
  }

  // ── Device ─────────────────────────────────────────────────────────────────

  Future<void> _autoConnect() async {
    try {
      final found = await _wacomController.detectDevice();
      if (found && mounted) await _connectDevice();
    } catch (_) {
      // No device present — user can sign with mouse on the pad widget.
    }
  }

  Future<void> _connectDevice() async {
    setState(() => _deviceState = _DeviceState.connecting);
    try {
      await _wacomController.connect();
      setState(() => _deviceState = _DeviceState.connected);
    } on PlatformException catch (e) {
      setState(() => _deviceState = _DeviceState.error);
      _snack('Connect failed: ${e.message}');
    } on UnsupportedError catch (e) {
      setState(() => _deviceState = _DeviceState.error);
      _snack(e.message ?? 'Unsupported platform');
    }
  }

  Future<void> _disconnectDevice() async {
    await _wacomController.disconnect();
    setState(() => _deviceState = _DeviceState.idle);
  }

  // ── Coordinate mapping ─────────────────────────────────────────────────────
  //
  // SfPdfViewer at zoom=1.0 scales the first page to fill the viewport width.
  // Therefore:  scale (px/pt) = viewerWidth / refPageWidth * zoom
  //
  // scrollOffset from PdfViewerController is in rendered (zoomed) viewport
  // pixels.  Dividing by scale converts to PDF points directly.
  //
  // Inter-page gap in SfPdfViewer is a constant 4 logical pixels (unchanged by
  // zoom), which equals 4/scale PDF points in document space.

  double _pxPerPt() {
    final refW = _pageSizes[1]?.width ?? 595.0;
    return (_viewerWidth / refW) * _pdfViewerController.zoomLevel;
  }

  void _savePdfCoords(Rect viewerRect) {
    if (_pageSizes.isEmpty) return;
    final scale  = _pxPerPt();
    final scroll = _pdfViewerController.scrollOffset;
    const gapPx  = 4.0;
    final gapPt  = gapPx / scale;

    final docLeft = (viewerRect.left + scroll.dx) / scale;
    final docTop  = (viewerRect.top  + scroll.dy) / scale;
    final docW    = viewerRect.width  / scale;
    final docH    = viewerRect.height / scale;

    double pageAccum = 0;
    for (int p = 1; p <= _pageSizes.length; p++) {
      final ph = _pageSizes[p]!.height;
      if (docTop < pageAccum + ph) {
        _signaturePage = p;
        final pw = _pageSizes[p]!.width;
        _signatureBoxInPdf = Rect.fromLTWH(
          docLeft.clamp(0.0, pw),
          (docTop - pageAccum).clamp(0.0, ph),
          docW.clamp(1.0, pw),
          docH.clamp(1.0, ph),
        );
        return;
      }
      pageAccum += ph + gapPt;
    }
    // Past last page — pin to last page bottom area.
    final lp  = _pageSizes.length;
    final lph = _pageSizes[lp]!.height;
    final lpw = _pageSizes[lp]!.width;
    _signaturePage = lp;
    _signatureBoxInPdf = Rect.fromLTWH(
      docLeft.clamp(0.0, lpw),
      (lph - docH).clamp(0.0, lph),
      docW.clamp(1.0, lpw),
      docH.clamp(1.0, lph),
    );
  }

  Rect? _viewerBox() {
    if (_signatureBoxInPdf == null || _pageSizes.isEmpty) return null;
    final scale  = _pxPerPt();
    final scroll = _pdfViewerController.scrollOffset;
    const gapPx  = 4.0;
    final gapPt  = gapPx / scale;

    double pageTopPt = 0;
    for (int p = 1; p < _signaturePage; p++) {
      pageTopPt += (_pageSizes[p]?.height ?? 0) + gapPt;
    }

    return Rect.fromLTWH(
      _signatureBoxInPdf!.left * scale - scroll.dx,
      (pageTopPt + _signatureBoxInPdf!.top) * scale - scroll.dy,
      _signatureBoxInPdf!.width  * scale,
      _signatureBoxInPdf!.height * scale,
    );
  }

  // ── Build signed PDF & POST to API ─────────────────────────────────────────

  Future<Uint8List> _buildSignedPdf() async {
    final doc   = PdfDocument(inputBytes: _pdfBytes!);
    final page  = doc.pages[_signaturePage - 1];
    final image = PdfBitmap(_signatureBytes!);
    page.graphics.drawImage(image, _signatureBoxInPdf!);
    final bytes = Uint8List.fromList(await doc.save());
    doc.dispose();
    return bytes;
  }

  Future<bool> _postToApi(Uint8List signedPdfBytes) async {
    final payload = jsonEncode({
      'mlrCode':        widget.mlrCode,
      'outputFileName': widget.outputFileName,
      'fileContent':    base64Encode(signedPdfBytes),
    });

    final response = await http.post(
      Uri.parse(widget.apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Accept':       'application/json',
      },
      body: payload,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Parse body for an explicit success flag if present.
      try {
        final json = jsonDecode(response.body);
        if (json is Map) {
          final flag = json['success'] ?? json['ok'] ?? json['status'];
          if (flag is bool)   return flag;
          if (flag == 'ok' || flag == 'success' || flag == 'true') return true;
          if (flag == 'error' || flag == 'false') return false;
        }
      } catch (_) {}
      return true; // 2xx with no parseable body → accept as success.
    }
    return false;
  }

  Future<void> _saveDocument() async {
    if (_pdfBytes == null ||
        _signatureBytes == null ||
        _signatureBoxInPdf == null) {
      return;
    }

    setState(() {
      _isSaving    = true;
      _lastResult  = null;
    });

    bool success = false;
    try {
      final signed = await _buildSignedPdf();
      success = await _postToApi(signed);
    } catch (e) {
      _snack('Error: $e');
    }

    setState(() {
      _isSaving   = false;
      _lastResult = success;
    });

    await widget.onSaveResult?.call(success);

    _snack(
      success ? 'Document saved successfully.' : 'Failed to save document.',
      duration: 4,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _snack(String msg, {int duration = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: duration),
    ));
  }

  bool get _canSave =>
      _pdfBytes != null &&
      _signatureBytes != null &&
      _signatureBoxInPdf != null &&
      !_isSaving;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width:  widget.width,
      height: widget.height,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildPdfArea()),
                _buildRightPanel(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── PDF viewer area ────────────────────────────────────────────────────────

  Widget _buildPdfArea() {
    if (_isLoadingPdf) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text('Could not load PDF\n$_loadError',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadPdf,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ]),
        ),
      );
    }
    if (_pdfBytes == null) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      _viewerWidth = constraints.maxWidth;
      return ListenableBuilder(
        listenable: _pdfViewerController,
        builder: (context, _) {
          final box         = _viewerBox();
          final draggingBox = _dragStart != null && _dragCurrent != null
              ? Rect.fromPoints(_dragStart!, _dragCurrent!)
              : null;

          return Stack(children: [
            // PDF viewer
            SfPdfViewer.memory(
              _pdfBytes!,
              controller: _pdfViewerController,
              onPageChanged: (_) => setState(() {}),
            ),

            // Gesture layer for drawing the signature box
            if (_isDrawingMode)
              GestureDetector(
                onPanStart:  (d) => setState(() {
                  _dragStart   = d.localPosition;
                  _dragCurrent = d.localPosition;
                  _signatureBoxInPdf = null;
                  _signatureBytes    = null;
                }),
                onPanUpdate: (d) => setState(() => _dragCurrent = d.localPosition),
                onPanEnd:    (_) {
                  if (_dragStart != null && _dragCurrent != null) {
                    final r = Rect.fromPoints(_dragStart!, _dragCurrent!);
                    if (r.width > 12 && r.height > 12) _savePdfCoords(r);
                  }
                  setState(() {
                    _dragStart   = null;
                    _dragCurrent = null;
                    _isDrawingMode = false;
                  });
                },
                child: Container(
                  color: Colors.blue.withValues(alpha: 0.04),
                  child: draggingBox != null
                      ? CustomPaint(
                          painter: _DashedRectPainter(rect: draggingBox),
                          size: Size.infinite)
                      : null,
                ),
              ),

            // Placed box border
            if (box != null)
              IgnorePointer(
                child: CustomPaint(
                  painter: _BoxBorderPainter(rect: box),
                  size: Size.infinite,
                ),
              ),

            // Signature image overlay
            if (box != null && _signatureBytes != null)
              Positioned(
                left:   box.left,
                top:    box.top,
                width:  box.width,
                height: box.height,
                child: IgnorePointer(
                  child: Image.memory(_signatureBytes!, fit: BoxFit.fill),
                ),
              ),

            // Draw-mode instruction banner
            if (_isDrawingMode)
              Positioned(
                top: 10, left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade700,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26,
                            blurRadius: 6, offset: Offset(0, 3))
                      ],
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.mouse, color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Text('Click and drag to draw the signature box',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ),
              ),
          ]);
        },
      );
    });
  }

  // ── Right control panel ────────────────────────────────────────────────────

  Widget _buildRightPanel(BuildContext context) {
    return Container(
      width: 285,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: Colors.grey.shade300),
        ),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 6, offset: Offset(-2, 0))
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // ① Device
          _PanelSection(
            title: 'Wacom Device',
            icon: Icons.tablet_android,
            child: _buildDeviceSection(),
          ),
          const SizedBox(height: 12),

          // ② Draw box
          _PanelSection(
            title: 'Draw Signature Box',
            icon: Icons.crop_free,
            child: _buildDrawBoxSection(context),
          ),
          const SizedBox(height: 12),

          // ③ Sign
          _PanelSection(
            title: 'Sign Here',
            icon: Icons.draw_outlined,
            child: _buildSignSection(context),
          ),
          const SizedBox(height: 12),

          // ④ Save
          _PanelSection(
            title: 'Save Document',
            icon: Icons.save_alt,
            child: _buildSaveSection(context),
          ),
        ],
      ),
    );
  }

  // ── Panel section builders ─────────────────────────────────────────────────

  Widget _buildDeviceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DeviceStatusBadge(state: _deviceState),
        const SizedBox(height: 8),
        if (_deviceState == _DeviceState.idle ||
            _deviceState == _DeviceState.error)
          _PanelButton(
              label: 'Connect Device',
              icon: Icons.usb,
              onPressed: _connectDevice)
        else if (_deviceState == _DeviceState.connecting)
          const Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)))
        else
          _PanelButton(
              label: 'Disconnect',
              icon: Icons.usb_off,
              onPressed: _disconnectDevice,
              outlined: true),
      ],
    );
  }

  Widget _buildDrawBoxSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _signatureBoxInPdf == null
              ? 'Tap the button, then drag on the PDF to place your signature.'
              : 'Box placed on page $_signaturePage. Tap to reposition.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        _isDrawingMode
            ? _PanelButton(
                label: 'Cancel',
                icon: Icons.cancel,
                onPressed: () => setState(() {
                  _isDrawingMode = false;
                  _dragStart = null;
                  _dragCurrent = null;
                }),
                color: Colors.red.shade600)
            : _PanelButton(
                label: _signatureBoxInPdf != null
                    ? 'Redraw Box'
                    : 'Draw Signature Box',
                icon: Icons.draw,
                onPressed: _pdfBytes != null
                    ? () => setState(() {
                          _isDrawingMode    = true;
                          _signatureBoxInPdf = null;
                          _dragStart        = null;
                          _dragCurrent      = null;
                        })
                    : null),
        if (_signatureBoxInPdf != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 14),
            const SizedBox(width: 5),
            Text('Box ready · Page $_signaturePage',
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.green,
                    fontWeight: FontWeight.w600)),
          ]),
        ],
      ],
    );
  }

  Widget _buildSignSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _deviceState == _DeviceState.connected
              ? 'Sign on the Wacom device or draw below, then tap Apply.'
              : 'Draw your signature below (or connect the Wacom device).',
          style:
              theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: WacomSignaturePad(
              width: 255,
              height: 120,
              controller: _wacomController,
              autoConnect: false,
              autoDisconnect: false,
              showControls: false,
              penColor: Colors.black87,
              strokeWidth: 2.0,
              backgroundColor: Colors.transparent,
              onSigned: (bytes) => setState(() => _signatureBytes = bytes),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: OutlinedButton.icon(
                onPressed: () {
                  _wacomController.clear();
                  setState(() => _signatureBytes = null);
                },
                icon: const Icon(Icons.clear, size: 14),
                label: const Text('Clear'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 34,
              child: FilledButton.icon(
                onPressed: () async {
                  if (!_wacomController.hasInk) {
                    _snack('Draw a signature first');
                    return;
                  }
                  final bytes = await _wacomController.toPngBytes();
                  setState(() => _signatureBytes = bytes);
                },
                icon: const Icon(Icons.check, size: 14),
                label: const Text('Apply'),
              ),
            ),
          ),
        ]),
        if (_signatureBytes != null) ...[
          const SizedBox(height: 8),
          Container(
            height: 54,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.green.shade300),
              borderRadius: BorderRadius.circular(4),
              color: Colors.green.shade50,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(_signatureBytes!, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 4),
          const Row(children: [
            Icon(Icons.check_circle, color: Colors.green, size: 12),
            SizedBox(width: 4),
            Text('Signature ready',
                style: TextStyle(fontSize: 11, color: Colors.green)),
          ]),
        ],
      ],
    );
  }

  Widget _buildSaveSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status hint when not ready
        if (!_canSave && !_isSaving) ...[
          Text(
            _pdfBytes == null
                ? 'Waiting for PDF to load…'
                : _signatureBoxInPdf == null
                    ? 'Step 2 — Draw a signature box on the PDF.'
                    : 'Step 3 — Apply your signature above.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
        ],

        // MLR code & filename display
        if (_pdfBytes != null) ...[
          _InfoRow(label: 'MLR Code', value: widget.mlrCode),
          const SizedBox(height: 4),
          _InfoRow(label: 'Output file', value: widget.outputFileName),
          const SizedBox(height: 10),
        ],

        // Save button
        SizedBox(
          height: 44,
          child: _isSaving
              ? const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('Saving…',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey)),
                    ],
                  ),
                )
              : FilledButton.icon(
                  onPressed: _canSave ? _saveDocument : null,
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Save Document',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  style: _canSave
                      ? FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32))
                      : null,
                ),
        ),

        // Result badge
        if (_lastResult != null) ...[
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _lastResult!
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _lastResult!
                    ? Colors.green.shade300
                    : Colors.red.shade300,
              ),
            ),
            child: Row(children: [
              Icon(
                _lastResult!
                    ? Icons.check_circle
                    : Icons.error_outline,
                color: _lastResult! ? Colors.green : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _lastResult!
                      ? 'Document sent successfully.'
                      : 'Failed to send document. Please retry.',
                  style: TextStyle(
                    fontSize: 12,
                    color: _lastResult! ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ]),
          ),
        ],
      ],
    );
  }
}

// ── Painters ───────────────────────────────────────────────────────────────────

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.rect});
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(rect,
        Paint()..color = Colors.blue.withValues(alpha: 0.08));
    final paint = Paint()
      ..color     = Colors.blue.shade600
      ..strokeWidth = 2
      ..style     = PaintingStyle.stroke;
    const dash = 8.0, gap = 4.0;
    for (final m in (Path()..addRect(rect)).computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(
            m.extractPath(d, (d + dash).clamp(0, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter o) => o.rect != rect;
}

class _BoxBorderPainter extends CustomPainter {
  const _BoxBorderPainter({required this.rect});
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(rect.inflate(3),
        Paint()..color = Colors.blue.withValues(alpha: 0.12));
    canvas.drawRect(
        rect,
        Paint()
          ..color       = Colors.blue.shade500
          ..strokeWidth = 1.5
          ..style       = PaintingStyle.stroke);
    // Corner handles
    final hp = Paint()
      ..color = Colors.blue.shade600
      ..style = PaintingStyle.fill;
    for (final c in [
      rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight
    ]) {
      canvas.drawRect(Rect.fromCenter(center: c, width: 6, height: 6), hp);
    }
    // Label
    (TextPainter(
      text: TextSpan(
        text: '  Signature  ',
        style: TextStyle(
            color: Colors.blue.shade800,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            backgroundColor: Colors.white.withValues(alpha: 0.85)),
      ),
      textDirection: TextDirection.ltr,
    )..layout())
        .paint(canvas, Offset(rect.left + 4, rect.top + 3));
  }

  @override
  bool shouldRepaint(_BoxBorderPainter o) => o.rect != rect;
}

// ── Shared panel widgets ────────────────────────────────────────────────────────

class _PanelSection extends StatelessWidget {
  const _PanelSection(
      {required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer
                .withValues(alpha: 0.45),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          child: Row(children: [
            Icon(icon, size: 15, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(title,
                style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary)),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(12), child: child),
      ]),
    );
  }
}

class _DeviceStatusBadge extends StatelessWidget {
  const _DeviceStatusBadge({required this.state});
  final _DeviceState state;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      _DeviceState.idle       => ('Not connected', Colors.grey, Icons.circle_outlined),
      _DeviceState.connecting => ('Connecting…', Colors.orange, Icons.pending_outlined),
      _DeviceState.connected  => ('Device connected', Colors.green, Icons.check_circle),
      _DeviceState.error      => ('Connection failed', Colors.red, Icons.error_outline),
    };
    return Row(children: [
      Icon(icon, color: color, size: 15),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.outlined = false,
    this.color,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool outlined;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return SizedBox(
        height: 36,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 15),
          label: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      );
    }
    return SizedBox(
      height: 36,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: color != null
            ? FilledButton.styleFrom(backgroundColor: color)
            : null,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 10, color: Colors.black87),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
