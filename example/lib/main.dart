import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_wacom_signature_pad/flutter_wacom_signature_pad.dart';

void main() {
  runApp(const WacomTestApp());
}

class WacomTestApp extends StatelessWidget {
  const WacomTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wacom Signature Pad',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const _AppHome(),
    );
  }
}

/// Landing page — choose between the PDF signing flow or the raw test harness.
class _AppHome extends StatelessWidget {
  const _AppHome();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Wacom Signature Pad'),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.draw, size: 72, color: theme.colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  'Wacom STU Signature Pad',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign PDF documents using your Wacom STU tablet.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 40),
                // Primary action
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PdfSignatureScreen()),
                    ),
                    icon: const Icon(Icons.picture_as_pdf, size: 20),
                    label: const Text('PDF Signature',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 12),
                // Secondary action
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TestHomePage()),
                    ),
                    icon: const Icon(Icons.science_outlined, size: 18),
                    label: const Text('Device Test Harness'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TestHomePage extends StatefulWidget {
  const TestHomePage({super.key});

  @override
  State<TestHomePage> createState() => _TestHomePageState();
}

enum _DeviceState { idle, connecting, connected, disconnecting, error }

class _TestHomePageState extends State<TestHomePage> {
  final WacomSignaturePadController _controller = WacomSignaturePadController();

  _DeviceState _deviceState = _DeviceState.idle;
  bool? _deviceDetected;
  Uint8List? _capturedSignature;
  String? _capturedBase64;
  String? _savedPath;
  String? _errorMessage;

  static const double _padWidth = 560;
  static const double _padHeight = 220;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _detectDevice() async {
    setState(() {
      _deviceDetected = null;
      _errorMessage = null;
    });
    try {
      final found = await _controller.detectDevice();
      setState(() => _deviceDetected = found);
    } on PlatformException catch (e) {
      setState(() => _errorMessage = 'Detect failed: ${e.message}');
    }
  }

  Future<void> _connect() async {
    setState(() {
      _deviceState = _DeviceState.connecting;
      _errorMessage = null;
    });
    try {
      await _controller.connect();
      setState(() => _deviceState = _DeviceState.connected);
    } on PlatformException catch (e) {
      setState(() {
        _deviceState = _DeviceState.error;
        _errorMessage = e.message ?? 'Unknown error';
      });
    } on UnsupportedError catch (e) {
      setState(() {
        _deviceState = _DeviceState.error;
        _errorMessage = e.message ?? 'Unsupported platform';
      });
    }
  }

  Future<void> _disconnect() async {
    setState(() => _deviceState = _DeviceState.disconnecting);
    await _controller.disconnect();
    setState(() {
      _deviceState = _DeviceState.idle;
      _errorMessage = null;
    });
  }

  void _onSigned(Uint8List bytes) {
    setState(() {
      _capturedSignature = bytes;
      _savedPath = null;
    });
  }

  void _onSignedBase64(String b64) {
    setState(() => _capturedBase64 = b64);
  }

  Future<void> _saveToFile() async {
    try {
      final file = await _controller.saveToFile('signature_test.png');
      setState(() => _savedPath = file.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved → ${file.path}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: ${e.message}')),
      );
    }
  }

  Future<void> _exportBase64() async {
    try {
      final b64 = await _controller.toBase64();
      setState(() => _capturedBase64 = b64);
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  void _clearSignature() {
    _controller.clear();
    setState(() {
      _capturedSignature = null;
      _capturedBase64 = null;
      _savedPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wacom STU-540 — Test Harness'),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section 1: Device control ───────────────────────────────
            _SectionCard(
              title: '1 · Device Control',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusRow(deviceState: _deviceState, detected: _deviceDetected),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _detectDevice,
                        icon: const Icon(Icons.search),
                        label: const Text('Detect Device'),
                      ),
                      FilledButton.icon(
                        onPressed: _deviceState == _DeviceState.idle ||
                                _deviceState == _DeviceState.error
                            ? _connect
                            : null,
                        icon: const Icon(Icons.usb),
                        label: _deviceState == _DeviceState.connecting
                            ? const Text('Connecting…')
                            : const Text('Connect'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _deviceState == _DeviceState.connected
                            ? _disconnect
                            : null,
                        icon: const Icon(Icons.usb_off),
                        label: _deviceState == _DeviceState.disconnecting
                            ? const Text('Disconnecting…')
                            : const Text('Disconnect'),
                      ),
                    ],
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    _ErrorBanner(message: _errorMessage!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Section 2: Signature pad ────────────────────────────────
            _SectionCard(
              title: '2 · Signature Pad',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _deviceState == _DeviceState.connected
                        ? 'Sign on the Wacom tablet or draw with the mouse below.'
                        : 'Connect a device first, or draw directly in the pad below.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  WacomSignaturePad(
                    width: _padWidth,
                    height: _padHeight,
                    controller: _controller,
                    autoConnect: false,
                    autoDisconnect: false,
                    showControls: false,
                    penColor: Colors.indigo,
                    strokeWidth: 2.5,
                    onSigned: _onSigned,
                    onSignedBase64: _onSignedBase64,
                    onClear: () => setState(() {
                      _capturedSignature = null;
                      _capturedBase64 = null;
                      _savedPath = null;
                    }),
                    deviceTitle: 'Sign Here',
                    deviceHint: 'Use the pen to sign',
                    deviceClearLabel: 'Clear',
                    deviceCancelLabel: 'Cancel',
                    deviceApplyLabel: 'Apply',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _clearSignature,
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear'),
                      ),
                      FilledButton.icon(
                        onPressed: _exportBase64,
                        icon: const Icon(Icons.check),
                        label: const Text('Apply / Export'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Section 3: Captured output ──────────────────────────────
            _SectionCard(
              title: '3 · Captured Output',
              child: _capturedSignature == null
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No signature captured yet.\nDraw in the pad above then tap Apply / Export.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Preview
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.white,
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Image.memory(
                            _capturedSignature!,
                            width: _padWidth,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Action buttons
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _saveToFile,
                              icon: const Icon(Icons.save_alt),
                              label: const Text('Save PNG to File'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: _capturedBase64 ?? ''),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Base64 copied to clipboard'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy Base64'),
                            ),
                          ],
                        ),
                        if (_savedPath != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Colors.green, size: 16),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Saved: $_savedPath',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.green),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_capturedBase64 != null) ...[
                          const SizedBox(height: 12),
                          _Base64Preview(base64: _capturedBase64!),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const Divider(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.deviceState, required this.detected});

  final _DeviceState deviceState;
  final bool? detected;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (deviceState) {
      _DeviceState.idle => ('Idle — not connected', Colors.grey, Icons.circle_outlined),
      _DeviceState.connecting => ('Connecting…', Colors.orange, Icons.pending),
      _DeviceState.connected => ('Connected', Colors.green, Icons.check_circle),
      _DeviceState.disconnecting => ('Disconnecting…', Colors.orange, Icons.pending),
      _DeviceState.error => ('Error', Colors.red, Icons.error),
    };

    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        if (detected != null) ...[
          const SizedBox(width: 16),
          Icon(
            detected! ? Icons.usb : Icons.usb_off,
            size: 16,
            color: detected! ? Colors.blue : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            detected! ? 'Device found' : 'No device found',
            style: TextStyle(
              fontSize: 12,
              color: detected! ? Colors.blue : Colors.grey,
            ),
          ),
        ],
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(message,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _Base64Preview extends StatefulWidget {
  const _Base64Preview({required this.base64});

  final String base64;

  @override
  State<_Base64Preview> createState() => _Base64PreviewState();
}

class _Base64PreviewState extends State<_Base64Preview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    const previewLen = 120;
    final preview = widget.base64.length > previewLen
        ? '${widget.base64.substring(0, previewLen)}…'
        : widget.base64;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Base64 PNG',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text('(${widget.base64.length} chars)',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? 'Collapse' : 'Expand'),
            ),
          ],
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: SelectableText(
            _expanded ? widget.base64 : preview,
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}
