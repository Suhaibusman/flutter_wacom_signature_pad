import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'wacom_signature_pad_controller.dart';

/// Signature capture widget for Wacom STU tablets on Windows.
class WacomSignaturePad extends StatefulWidget {
  /// Creates a Wacom signature pad widget.
  const WacomSignaturePad({
    super.key,
    required this.width,
    required this.height,
    this.controller,
    this.onSigned,
    this.onSignedBase64,
    this.onCancel,
    this.onClear,
    this.penColor = Colors.black,
    this.strokeWidth = 2.0,
    this.backgroundColor = Colors.transparent,
    this.showControls = true,
    this.autoConnect = true,
    this.autoDisconnect = true,
    this.showDeviceIdleScreen = true,
    this.deviceIdleTitle = 'Device Ready',
    this.deviceIdleSubtitle = 'Please wait',
    this.deviceTitle = 'Sign here',
    this.deviceHint = 'Please sign in the box',
    this.deviceClearLabel = 'Clear',
    this.deviceCancelLabel = 'Cancel',
    this.deviceApplyLabel = 'Apply',
  });

  /// Width of the on-screen signature area.
  final double width;

  /// Height of the on-screen signature area.
  final double height;

  /// Optional controller for programmatic control.
  final WacomSignaturePadController? controller;

  /// Called with PNG bytes when the user applies the signature.
  final ValueChanged<Uint8List>? onSigned;

  /// Called with Base64 PNG data when the user applies the signature.
  final ValueChanged<String>? onSignedBase64;

  /// Called when the user cancels on the device or UI.
  final VoidCallback? onCancel;

  /// Called when the pad is cleared.
  final VoidCallback? onClear;

  /// Ink color for the on-screen preview.
  final Color penColor;

  /// Stroke width for the on-screen preview.
  final double strokeWidth;

  /// Background color for the on-screen preview.
  final Color backgroundColor;

  /// Shows the Clear/Cancel/Apply controls under the preview.
  final bool showControls;

  /// Automatically connect to the device when the widget is created.
  final bool autoConnect;

  /// Automatically disconnect from the device when the widget is disposed.
  final bool autoDisconnect;

  /// Shows an idle screen on the device between sessions.
  final bool showDeviceIdleScreen;

  /// Title text shown on the device idle screen.
  final String deviceIdleTitle;

  /// Subtitle text shown on the device idle screen.
  final String deviceIdleSubtitle;

  /// Title text shown on the device signature screen.
  final String deviceTitle;

  /// Hint text shown inside the device signature box.
  final String deviceHint;

  /// Label for the device clear button.
  final String deviceClearLabel;

  /// Label for the device cancel button.
  final String deviceCancelLabel;

  /// Label for the device apply button.
  final String deviceApplyLabel;

  @override
  State<WacomSignaturePad> createState() => WacomSignaturePadState();
}

/// State for [WacomSignaturePad], exposed for controller access.
class WacomSignaturePadState extends State<WacomSignaturePad> {
  final WacomSignaturePadNative _native = WacomSignaturePadNative();
  final List<List<Offset>> _strokes = [];
  final List<Offset> _currentStroke = [];

  StreamSubscription<WacomPenEvent>? _penSubscription;
  WacomDeviceCapabilities? _caps;
  bool _isConnected = false;
  bool _deviceUiReady = false;
  bool _isCompleting = false;
  bool _isCancelling = false;

  /// Whether the pad currently has any ink.
  bool get hasInk => _strokes.isNotEmpty || _currentStroke.isNotEmpty;

  /// Whether the device is currently connected.
  bool get isConnected => _isConnected;

  /// Checks if a compatible device is available without connecting.
  Future<bool> detectDevice() async {
    return _native.detectDevice();
  }

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(this);
    if (widget.autoConnect) {
      unawaited(connect());
    }
  }

  @override
  void didUpdateWidget(covariant WacomSignaturePad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach(this);
      widget.controller?.attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach(this);
    if (widget.autoDisconnect) {
      unawaited(disconnect());
    } else {
      unawaited(_penSubscription?.cancel());
    }
    super.dispose();
  }

  /// Connects to the device and configures the signature screen.
  Future<void> connect() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('flutter_wacom_signature_pad supports Windows only.');
    }
    if (_isConnected) {
      return;
    }
    final caps = await _native.connect();
    _caps = caps;
    _isConnected = true;

    await _penSubscription?.cancel();
    _penSubscription = _native.penEvents.listen(_handlePenEvent);

    if (widget.showDeviceIdleScreen) {
      await _showDeviceIdleScreen();
    }
    await _showDeviceSignatureScreen();
    if (mounted) {
      setState(() {});
    }
  }

  /// Disconnects from the device and clears device UI state.
  Future<void> disconnect() async {
    await _penSubscription?.cancel();
    _penSubscription = null;
    if (_isConnected) {
      if (widget.showDeviceIdleScreen) {
        await _showDeviceIdleScreen();
      }
      await _native.disconnect();
    }
    _isConnected = false;
    _deviceUiReady = false;
    if (mounted) {
      setState(() {});
    }
  }

  void _handlePenEvent(WacomPenEvent event) {
    if (!_deviceUiReady || _caps == null) {
      return;
    }
    final caps = _caps!;
    final maxX = caps.maxX;
    final maxY = caps.maxY;
    final screenW = caps.screenWidth;
    final screenH = caps.screenHeight;

    final mappedX = (event.x / maxX) * screenW;
    final mappedY = (event.y / maxY) * screenH;

    final buttonHeight = screenH * 0.2;
    final buttonTop = screenH - buttonHeight;

    if (mappedY > buttonTop && event.pressure > 0) {
      final buttonWidth = screenW / 3;
      if (mappedX < buttonWidth) {
        _clear();
      } else if (mappedX < buttonWidth * 2) {
        _cancel();
      } else {
        _apply();
      }
      return;
    }

    final double screenX = (event.x / maxX) * widget.width;
    final double screenY = (event.y / maxY) * widget.height;

    setState(() {
      if (event.pressure > 0 || event.sw != 0) {
        _currentStroke.add(Offset(screenX, screenY));
      } else {
        if (_currentStroke.isNotEmpty) {
          _strokes.add(List.from(_currentStroke));
          _currentStroke.clear();
        }
      }
    });
  }

  Future<void> _showDeviceSignatureScreen() async {
    if (_caps == null) return;
    _deviceUiReady = true;
    final caps = _caps!;
    final width = caps.screenWidth.toInt();
    final height = caps.screenHeight.toInt();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFFF8FAFC),
    );

    final titlePainter = TextPainter(
      text: TextSpan(
        text: widget.deviceTitle,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    titlePainter.layout();
    titlePainter.paint(canvas, Offset((width - titlePainter.width) / 2, 36));

    final fieldRect = Rect.fromLTWH(
      width * 0.08,
      height * 0.22,
      width * 0.84,
      height * 0.42,
    );
    canvas.drawRect(fieldRect, Paint()..color = Colors.white);
    canvas.drawRect(
      fieldRect,
      Paint()
        ..color = const Color(0xFFE2E8F0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final hintPainter = TextPainter(
      text: TextSpan(
        text: widget.deviceHint,
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 20),
      ),
      textDirection: TextDirection.ltr,
    );
    hintPainter.layout();
    hintPainter.paint(
      canvas,
      Offset(
        (width - hintPainter.width) / 2,
        fieldRect.center.dy - (hintPainter.height / 2),
      ),
    );

    final buttonHeight = height * 0.2;
    final buttonTop = height - buttonHeight;
    final buttonWidth = width / 3;

    _drawDeviceButton(
      canvas,
      widget.deviceClearLabel,
      const Color(0xFFE2E8F0),
      const Color(0xFF0F172A),
      Rect.fromLTWH(0, buttonTop, buttonWidth, buttonHeight),
    );
    _drawDeviceButton(
      canvas,
      widget.deviceCancelLabel,
      const Color(0xFFF1F5F9),
      const Color(0xFF0F172A),
      Rect.fromLTWH(buttonWidth, buttonTop, buttonWidth, buttonHeight),
    );
    _drawDeviceButton(
      canvas,
      widget.deviceApplyLabel,
      const Color(0xFF059669),
      Colors.white,
      Rect.fromLTWH(buttonWidth * 2, buttonTop, buttonWidth, buttonHeight),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData != null) {
      final rgbaBytes = byteData.buffer.asUint8List();
      final int pixelCount = width * height;
      final Uint8List rgbBytes = Uint8List(pixelCount * 3);
      for (int i = 0; i < pixelCount; i++) {
        final int rgbaIndex = i * 4;
        final int rgbIndex = i * 3;
        rgbBytes[rgbIndex] = rgbaBytes[rgbaIndex + 2];
        rgbBytes[rgbIndex + 1] = rgbaBytes[rgbaIndex + 1];
        rgbBytes[rgbIndex + 2] = rgbaBytes[rgbaIndex];
      }
      await _native.setSignatureScreen(rgbBytes, 4);
    }
  }

  void _drawDeviceButton(
    Canvas canvas,
    String text,
    Color color,
    Color textColor,
    Rect rect,
  ) {
    canvas.drawRect(rect, Paint()..color = color);
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        rect.left + (rect.width - textPainter.width) / 2,
        rect.top + (rect.height - textPainter.height) / 2,
      ),
    );
  }

  /// Clears the signature when invoked from the controller.
  Future<void> clearFromController() async {
    _clear();
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _currentStroke.clear();
    });
    widget.onClear?.call();
    unawaited(_showDeviceSignatureScreen());
  }

  void _cancel() {
    if (_isCancelling) return;
    _isCancelling = true;
    try {
      widget.onCancel?.call();
      if (widget.showDeviceIdleScreen) {
        unawaited(_showDeviceIdleScreen());
      }
    } finally {
      _isCancelling = false;
    }
  }

  Future<void> _apply() async {
    if (_isCompleting) return;
    _isCompleting = true;
    try {
      final pngBytes = await renderPngBytes();
      widget.onSigned?.call(pngBytes);
      if (widget.onSignedBase64 != null) {
        widget.onSignedBase64!(base64Encode(pngBytes));
      }
      if (widget.showDeviceIdleScreen) {
        unawaited(_showDeviceIdleScreen());
      }
    } finally {
      _isCompleting = false;
    }
  }

  Future<void> _showDeviceIdleScreen() async {
    if (_caps == null) return;
    _deviceUiReady = false;
    final caps = _caps!;
    final width = caps.screenWidth.toInt();
    final height = caps.screenHeight.toInt();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.white,
    );

    final titlePainter = TextPainter(
      text: TextSpan(
        text: widget.deviceIdleTitle,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 30,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    titlePainter.layout();

    final subtitlePainter = TextPainter(
      text: TextSpan(
        text: widget.deviceIdleSubtitle,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    subtitlePainter.layout();

    final double centerY = height / 2;
    titlePainter.paint(
      canvas,
      Offset((width - titlePainter.width) / 2, centerY - titlePainter.height),
    );
    subtitlePainter.paint(
      canvas,
      Offset((width - subtitlePainter.width) / 2, centerY + 8),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData != null) {
      final rgbaBytes = byteData.buffer.asUint8List();
      final int pixelCount = width * height;
      final Uint8List rgbBytes = Uint8List(pixelCount * 3);
      for (int i = 0; i < pixelCount; i++) {
        final int rgbaIndex = i * 4;
        final int rgbIndex = i * 3;
        rgbBytes[rgbIndex] = rgbaBytes[rgbaIndex + 2];
        rgbBytes[rgbIndex + 1] = rgbaBytes[rgbaIndex + 1];
        rgbBytes[rgbIndex + 2] = rgbaBytes[rgbaIndex];
      }
      await _native.setSignatureScreen(rgbBytes, 4);
    }
  }

  /// Renders the current signature to PNG bytes.
  Future<Uint8List> renderPngBytes() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, widget.width, widget.height),
    );

    if (widget.backgroundColor != Colors.transparent) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, widget.width, widget.height),
        Paint()..color = widget.backgroundColor,
      );
    }

    final paint = Paint()
      ..color = widget.penColor
      ..strokeWidth = widget.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final stroke in _strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    if (_currentStroke.isNotEmpty) {
      final path = Path()..moveTo(_currentStroke.first.dx, _currentStroke.first.dy);
      for (var i = 1; i < _currentStroke.length; i++) {
        path.lineTo(_currentStroke[i].dx, _currentStroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      widget.width.toInt(),
      widget.height.toInt(),
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Failed to render signature to PNG.');
    }
    return byteData.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final hasInk = this.hasInk;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
            borderRadius: BorderRadius.circular(10),
            color: widget.backgroundColor == Colors.transparent
                ? Colors.white
                : widget.backgroundColor,
          ),
          child: Stack(
            children: [
              if (!hasInk)
                const Center(
                  child: Text(
                    'Sign here',
                    style: TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      setState(() {
                        _currentStroke
                          ..clear()
                          ..add(details.localPosition);
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        _currentStroke.add(details.localPosition);
                      });
                    },
                    onPanEnd: (_) {
                      if (_currentStroke.isNotEmpty) {
                        setState(() {
                          _strokes.add(List.from(_currentStroke));
                          _currentStroke.clear();
                        });
                      }
                    },
                    child: CustomPaint(
                      painter: _SignaturePainter(
                        _strokes,
                        _currentStroke,
                        widget.penColor,
                        widget.strokeWidth,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.showControls) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: _clear,
                child: const Text('Clear'),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _cancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _apply,
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes, this.currentStroke, this.color, this.strokeWidth);

  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    if (currentStroke.isNotEmpty) {
      final path = Path()..moveTo(currentStroke.first.dx, currentStroke.first.dy);
      for (var i = 1; i < currentStroke.length; i++) {
        path.lineTo(currentStroke[i].dx, currentStroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Device coordinate and screen dimensions reported by the tablet.
class WacomDeviceCapabilities {
  /// Creates a set of device capabilities.
  WacomDeviceCapabilities({
    required this.maxX,
    required this.maxY,
    required this.screenWidth,
    required this.screenHeight,
  });

  /// Maximum X coordinate reported by the tablet.
  final double maxX;

  /// Maximum Y coordinate reported by the tablet.
  final double maxY;

  /// Device screen width in pixels.
  final double screenWidth;

  /// Device screen height in pixels.
  final double screenHeight;
}

/// A pen event emitted by the device.
class WacomPenEvent {
  /// Creates a pen event.
  WacomPenEvent({
    required this.x,
    required this.y,
    required this.pressure,
    required this.sw,
  });

  /// Raw X coordinate reported by the device.
  final double x;

  /// Raw Y coordinate reported by the device.
  final double y;

  /// Pen pressure value reported by the device.
  final double pressure;

  /// Switch state (buttons/eraser) reported by the device.
  final int sw;
}

/// Low-level bridge to the Windows platform channels.
class WacomSignaturePadNative {
  static const MethodChannel _methodChannel =
      MethodChannel('flutter_wacom_signature_pad/methods');
  static const EventChannel _eventChannel =
      EventChannel('flutter_wacom_signature_pad/events');

  Stream<WacomPenEvent> get penEvents {
    return _eventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return WacomPenEvent(
          x: (event['x'] as int).toDouble(),
          y: (event['y'] as int).toDouble(),
          pressure: (event['pressure'] as int).toDouble(),
          sw: (event['sw'] as int),
        );
      }
      throw StateError('Invalid pen event format: $event');
    });
  }

  Future<WacomDeviceCapabilities> connect() async {
    final result = await _methodChannel.invokeMethod('connect');
    if (result is Map) {
      return WacomDeviceCapabilities(
        maxX: (result['maxX'] as int).toDouble(),
        maxY: (result['maxY'] as int).toDouble(),
        screenWidth: (result['screenWidth'] as int).toDouble(),
        screenHeight: (result['screenHeight'] as int).toDouble(),
      );
    }
    throw StateError('Unexpected connect result: $result');
  }

  Future<void> disconnect() async {
    await _methodChannel.invokeMethod('disconnect');
  }

  Future<bool> detectDevice() async {
    final result = await _methodChannel.invokeMethod('detectDevice');
    return result == true;
  }

  Future<void> clearScreen() async {
    await _methodChannel.invokeMethod('clearScreen');
  }

  Future<void> setSignatureScreen(Uint8List rgbBytes, int mode) async {
    await _methodChannel.invokeMethod('setSignatureScreen', {
      'data': rgbBytes,
      'mode': mode,
    });
  }
}
