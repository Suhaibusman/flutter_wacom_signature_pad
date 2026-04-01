import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'wacom_signature_pad.dart';
import 'wacom_signature_pad_controller.dart';

// ── PdfSignatureScreen ────────────────────────────────────────────────────────

/// A full-screen widget that loads a PDF from a URL, lets the user draw a
/// signature box on any page, captures ink from a Wacom STU device or the
/// mouse, overlays the signature in real-time, and saves a signed copy to the
/// Documents folder.
///
/// Required packages (add to your pubspec.yaml):
/// ```yaml
/// syncfusion_flutter_pdfviewer: ^28.2.0
/// syncfusion_flutter_pdf: ^28.2.0
/// http: ^1.2.0
/// path_provider: ^2.1.0
/// ```
class PdfSignatureScreen extends StatefulWidget {
  const PdfSignatureScreen({super.key});

  @override
  State<PdfSignatureScreen> createState() => _PdfSignatureScreenState();
}

enum _DeviceState { idle, connecting, connected, error }

class _PdfSignatureScreenState extends State<PdfSignatureScreen> {
  // Controllers
  final _urlController = TextEditingController();
  final _pdfViewerController = PdfViewerController();
  final _wacomController = WacomSignaturePadController();

  // PDF state
  Uint8List? _pdfBytes;
  bool _isLoadingPdf = false;
  String? _loadError;

  // Page sizes in PDF points (1-based page index)
  final Map<int, Size> _pageSizes = {};

  // Drawing mode state
  bool _isDrawingMode = false;
  Offset? _dragStart;
  Offset? _dragCurrent;

  // Saved in PDF coordinate space for embedding
  int _signaturePage = 1;
  Rect? _signatureBoxInPdf;

  // Signature bytes from the Wacom pad
  Uint8List? _signatureBytes;

  // Device & save state
  _DeviceState _deviceState = _DeviceState.idle;
  String? _savedPath;

  // Current viewer widget width — updated in LayoutBuilder each frame.
  // Used to compute the pixel-per-point scale accurately (SfPdfViewer
  // scales the page so its width fills the viewport at zoom=1.0).
  double _viewerWidth = 1.0;

  @override
  void initState() {
    super.initState();
    _autoDetectAndConnect();
  }

  Future<void> _autoDetectAndConnect() async {
    try {
      final found = await _wacomController.detectDevice();
      if (found && mounted) {
        await _connectDevice();
      }
    } catch (_) {
      // No device available — silent, user can connect manually.
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _pdfViewerController.dispose();
    _wacomController.dispose();
    super.dispose();
  }

  // ── PDF loading ─────────────────────────────────────────────────────────────

  Future<void> _loadPdf() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLoadingPdf = true;
      _loadError = null;
      _pdfBytes = null;
      _signatureBoxInPdf = null;
      _signatureBytes = null;
      _pageSizes.clear();
      _isDrawingMode = false;
      _savedPath = null;
    });

    try {
      final response = await http.get(Uri.parse(url));
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
          _loadError = 'HTTP ${response.statusCode}: ${response.reasonPhrase}';
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

  // ── Device ──────────────────────────────────────────────────────────────────

  Future<void> _connectDevice() async {
    setState(() => _deviceState = _DeviceState.connecting);
    try {
      await _wacomController.connect();
      setState(() => _deviceState = _DeviceState.connected);
    } on PlatformException catch (e) {
      setState(() => _deviceState = _DeviceState.error);
      _showSnack('Connect failed: ${e.message}');
    } on UnsupportedError catch (e) {
      setState(() => _deviceState = _DeviceState.error);
      _showSnack(e.message ?? 'Unsupported platform');
    }
  }

  Future<void> _disconnectDevice() async {
    await _wacomController.disconnect();
    setState(() => _deviceState = _DeviceState.idle);
  }

  // ── Coordinate mapping ──────────────────────────────────────────────────────
  //
  // SfPdfViewer scales the PDF so that the first page's width exactly fills
  // the viewport width at zoom=1.0.  Therefore the correct pixel-per-point
  // scale is:
  //
  //   scale = (viewerWidth / refPageWidth) * zoom
  //
  // scrollOffset from PdfViewerController is in rendered (zoomed) viewport
  // pixels, i.e. it grows with zoom.  Dividing document pixels by `scale`
  // gives PDF points directly.
  //
  // Inter-page gap in SfPdfViewer is a constant 4 logical pixels regardless
  // of zoom.  In PDF-point space that is  4 / scale  points per gap.

  double _pxPerPt() {
    final refW = _pageSizes[1]?.width ?? 595.0;
    final zoom = _pdfViewerController.zoomLevel;
    return (_viewerWidth / refW) * zoom;
  }

  void _savePdfCoords(Rect viewerRect) {
    if (_pageSizes.isEmpty) return;

    final scale = _pxPerPt();
    final scroll = _pdfViewerController.scrollOffset;
    const gapPx = 4.0;
    final gapPt = gapPx / scale;

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
    final lastP = _pageSizes.length;
    final lph   = _pageSizes[lastP]!.height;
    final lpw   = _pageSizes[lastP]!.width;
    _signaturePage = lastP;
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

  // ── Save PDF ────────────────────────────────────────────────────────────────

  Future<void> _savePdf() async {
    if (_pdfBytes == null || _signatureBytes == null || _signatureBoxInPdf == null) return;

    try {
      final doc = PdfDocument(inputBytes: _pdfBytes!);
      final page = doc.pages[_signaturePage - 1];
      final image = PdfBitmap(_signatureBytes!);
      page.graphics.drawImage(image, _signatureBoxInPdf!);

      final savedBytes = await doc.save();
      doc.dispose();

      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/signed_$ts.pdf');
      await file.writeAsBytes(savedBytes);

      setState(() => _savedPath = file.path);
      _showSnack('Saved: ${file.path}', duration: 6);
    } catch (e) {
      _showSnack('Save failed: $e');
    }
  }

  void _showSnack(String msg, {int duration = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: duration),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('PDF Signature'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          _UrlBar(
            controller: _urlController,
            isLoading: _isLoadingPdf,
            onLoad: _loadPdf,
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildPdfArea()),
                _buildRightPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfArea() {
    if (_isLoadingPdf) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text('Failed to load PDF\n$_loadError',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red)),
          ]),
        ),
      );
    }
    if (_pdfBytes == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.picture_as_pdf, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('Enter a PDF URL above and tap Load',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15)),
          const SizedBox(height: 8),
          Text('Then draw a signature box and sign on the device.',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        ]),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      _viewerWidth = constraints.maxWidth;
      return ListenableBuilder(
        listenable: _pdfViewerController,
        builder: (context, child) {
          final box = _viewerBox();
          final draggingBox = _dragStart != null && _dragCurrent != null
              ? Rect.fromPoints(_dragStart!, _dragCurrent!)
              : null;

          return Stack(children: [
            SfPdfViewer.memory(
              _pdfBytes!,
              controller: _pdfViewerController,
              onPageChanged: (_) => setState(() {}),
            ),
            if (_isDrawingMode)
              GestureDetector(
                onPanStart: (d) => setState(() {
                  _dragStart = d.localPosition;
                  _dragCurrent = d.localPosition;
                  _signatureBoxInPdf = null;
                  _signatureBytes = null;
                }),
                onPanUpdate: (d) =>
                    setState(() => _dragCurrent = d.localPosition),
                onPanEnd: (_) {
                  if (_dragStart != null && _dragCurrent != null) {
                    final r = Rect.fromPoints(_dragStart!, _dragCurrent!);
                    if (r.width > 12 && r.height > 12) _savePdfCoords(r);
                  }
                  setState(() {
                    _dragStart = null;
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
            if (box != null)
              IgnorePointer(
                child: CustomPaint(
                  painter: _BoxBorderPainter(rect: box),
                  size: Size.infinite,
                ),
              ),
            if (box != null && _signatureBytes != null)
              Positioned(
                left: box.left,
                top: box.top,
                width: box.width,
                height: box.height,
                child: IgnorePointer(
                  child: Image.memory(_signatureBytes!, fit: BoxFit.fill),
                ),
              ),
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
                        BoxShadow(color: Colors.black26, blurRadius: 6,
                            offset: Offset(0, 3))
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

  Widget _buildRightPanel() {
    final canSave = _pdfBytes != null &&
        _signatureBytes != null &&
        _signatureBoxInPdf != null;

    return Container(
      width: 285,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Colors.grey.shade300)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(-2, 0))
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _PanelSection(title: 'Wacom Device', icon: Icons.tablet_android,
              child: _buildDeviceSection()),
          const SizedBox(height: 12),
          _PanelSection(title: 'Draw Signature Box', icon: Icons.crop_free,
              child: _buildDrawBoxSection()),
          const SizedBox(height: 12),
          _PanelSection(title: 'Sign Here', icon: Icons.draw_outlined,
              child: _buildSignSection()),
          const SizedBox(height: 12),
          _PanelSection(title: 'Save Signed PDF', icon: Icons.save_alt,
              child: _buildSaveSection(canSave)),
        ],
      ),
    );
  }

  Widget _buildDeviceSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _DeviceStatusBadge(state: _deviceState),
      const SizedBox(height: 8),
      if (_deviceState == _DeviceState.idle ||
          _deviceState == _DeviceState.error)
        _PanelButton(label: 'Connect Device', icon: Icons.usb,
            onPressed: _connectDevice)
      else if (_deviceState == _DeviceState.connecting)
        const Center(child: SizedBox(width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2)))
      else
        _PanelButton(label: 'Disconnect', icon: Icons.usb_off,
            onPressed: _disconnectDevice, outlined: true),
    ]);
  }

  Widget _buildDrawBoxSection() {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        _signatureBoxInPdf == null
            ? 'Tap the button, then click and drag on the PDF to place your signature.'
            : 'Box placed on page $_signaturePage. Tap to reposition.',
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
      ),
      const SizedBox(height: 8),
      _isDrawingMode
          ? _PanelButton(
              label: 'Cancel Drawing', icon: Icons.cancel,
              onPressed: () => setState(() {
                _isDrawingMode = false;
                _dragStart = null;
                _dragCurrent = null;
              }),
              color: Colors.red.shade600)
          : _PanelButton(
              label: _signatureBoxInPdf != null
                  ? 'Redraw Signature Box' : 'Draw Signature Box',
              icon: Icons.draw,
              onPressed: _pdfBytes != null
                  ? () => setState(() {
                        _isDrawingMode = true;
                        _signatureBoxInPdf = null;
                        _dragStart = null;
                        _dragCurrent = null;
                      })
                  : null),
      if (_signatureBoxInPdf != null) ...[
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 14),
          const SizedBox(width: 5),
          Text('Box ready · Page $_signaturePage',
              style: const TextStyle(fontSize: 11, color: Colors.green,
                  fontWeight: FontWeight.w600)),
        ]),
      ],
    ]);
  }

  Widget _buildSignSection() {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        _deviceState == _DeviceState.connected
            ? 'Sign on the Wacom device or draw below, then tap Apply.'
            : 'Draw your signature below (or connect the Wacom device).',
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
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
            width: 255, height: 120,
            controller: _wacomController,
            autoConnect: false, autoDisconnect: false,
            showControls: false,
            penColor: Colors.black87, strokeWidth: 2.0,
            backgroundColor: Colors.transparent,
            onSigned: (bytes) => setState(() => _signatureBytes = bytes),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: SizedBox(height: 34,
          child: OutlinedButton.icon(
            onPressed: () {
              _wacomController.clear();
              setState(() => _signatureBytes = null);
            },
            icon: const Icon(Icons.clear, size: 14),
            label: const Text('Clear'),
          ))),
        const SizedBox(width: 8),
        Expanded(child: SizedBox(height: 34,
          child: FilledButton.icon(
            onPressed: () async {
              if (!_wacomController.hasInk) {
                _showSnack('Draw a signature first');
                return;
              }
              final bytes = await _wacomController.toPngBytes();
              setState(() => _signatureBytes = bytes);
            },
            icon: const Icon(Icons.check, size: 14),
            label: const Text('Apply'),
          ))),
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
    ]);
  }

  Widget _buildSaveSection(bool canSave) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!canSave) ...[
        Text(
          _pdfBytes == null
              ? 'Step 1 — Load a PDF using the URL bar.'
              : _signatureBoxInPdf == null
                  ? 'Step 2 — Draw a signature box on the PDF.'
                  : 'Step 3 — Apply your signature above.',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
      ],
      SizedBox(
        height: 42,
        child: FilledButton.icon(
          onPressed: canSave ? _savePdf : null,
          icon: const Icon(Icons.save, size: 18),
          label: const Text('Save Signed PDF',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          style: canSave
              ? FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32))
              : null,
        ),
      ),
      if (_savedPath != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(_savedPath!,
                  style: const TextStyle(fontSize: 10, color: Colors.green),
                  maxLines: 4, overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ],
    ]);
  }
}

// ── Painters ───────────────────────────────────────────────────────────────────

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.rect});
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(rect, Paint()..color = Colors.blue.withValues(alpha: 0.08));
    final paint = Paint()
      ..color = Colors.blue.shade600
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const dash = 8.0, gap = 4.0;
    for (final m in (Path()..addRect(rect)).computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, (d + dash).clamp(0, m.length)), paint);
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
    canvas.drawRect(rect,
        Paint()
          ..color = Colors.blue.shade500
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke);
    final hp = Paint()..color = Colors.blue.shade600..style = PaintingStyle.fill;
    for (final c in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
      canvas.drawRect(Rect.fromCenter(center: c, width: 6, height: 6), hp);
    }
    (TextPainter(
      text: TextSpan(
        text: '  Signature  ',
        style: TextStyle(color: Colors.blue.shade800, fontSize: 10,
            fontWeight: FontWeight.w600,
            backgroundColor: Colors.white.withValues(alpha: 0.85)),
      ),
      textDirection: TextDirection.ltr,
    )..layout()).paint(canvas, Offset(rect.left + 4, rect.top + 3));
  }

  @override
  bool shouldRepaint(_BoxBorderPainter o) => o.rect != rect;
}

// ── Shared panel widgets ───────────────────────────────────────────────────────

class _PanelSection extends StatelessWidget {
  const _PanelSection({required this.title, required this.icon, required this.child});
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          child: Row(children: [
            Icon(icon, size: 15, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(title, style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
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
      Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({required this.label, required this.icon,
      required this.onPressed, this.outlined = false, this.color});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool outlined;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return SizedBox(height: 36,
        child: OutlinedButton.icon(onPressed: onPressed,
            icon: Icon(icon, size: 15),
            label: Text(label, style: const TextStyle(fontSize: 13))));
    }
    return SizedBox(height: 36,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: color != null ? FilledButton.styleFrom(backgroundColor: color) : null,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 13))));
  }
}

class _UrlBar extends StatelessWidget {
  const _UrlBar({required this.controller, required this.isLoading, required this.onLoad});
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(children: [
        const Icon(Icons.picture_as_pdf, color: Colors.red, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Enter PDF URL  (https://example.com/document.pdf)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
            onSubmitted: (_) => onLoad(),
          ),
        ),
        const SizedBox(width: 10),
        isLoading
            ? const SizedBox(width: 36, height: 36,
                child: Padding(padding: EdgeInsets.all(7),
                    child: CircularProgressIndicator(strokeWidth: 2.5)))
            : SizedBox(height: 38,
                child: FilledButton.icon(onPressed: onLoad,
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: const Text('Load PDF'))),
      ]),
    );
  }
}
