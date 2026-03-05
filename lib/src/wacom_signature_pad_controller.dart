import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'wacom_signature_pad.dart';

/// Controller for [WacomSignaturePad] that exposes programmatic actions.
class WacomSignaturePadController extends ChangeNotifier {
  WacomSignaturePadState? _state;

  /// Attaches the controller to a widget state.
  void attach(WacomSignaturePadState state) {
    _state = state;
  }

  /// Detaches the controller from a widget state.
  void detach(WacomSignaturePadState state) {
    if (_state == state) {
      _state = null;
    }
  }

  /// Whether the device is currently connected.
  bool get isConnected => _state?.isConnected ?? false;

  /// Whether there is any ink currently captured.
  bool get hasInk => _state?.hasInk ?? false;

  /// Connects to the device.
  Future<void> connect() async {
    await _state?.connect();
  }

  /// Disconnects from the device.
  Future<void> disconnect() async {
    await _state?.disconnect();
  }

  /// Detects whether a compatible device is available.
  Future<bool> detectDevice() async {
    final state = _state;
    if (state != null) {
      return state.detectDevice();
    }
    return WacomSignaturePadNative().detectDevice();
  }

  /// Clears the signature.
  Future<void> clear() async {
    await _state?.clearFromController();
  }

  /// Exports the signature as PNG bytes.
  Future<Uint8List> toPngBytes() async {
    final state = _state;
    if (state == null) {
      throw StateError('WacomSignaturePadController is not attached to a widget.');
    }
    return state.renderPngBytes();
  }

  /// Exports the signature as Base64-encoded PNG data.
  Future<String> toBase64() async {
    final bytes = await toPngBytes();
    return base64Encode(bytes);
  }

  /// Saves the signature PNG to a file and returns the file.
  Future<File> saveToFile(String path) async {
    final bytes = await toPngBytes();
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
