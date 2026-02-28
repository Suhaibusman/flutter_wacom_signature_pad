import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'wacom_signature_pad.dart';

class WacomSignaturePadController extends ChangeNotifier {
  WacomSignaturePadState? _state;

  void attach(WacomSignaturePadState state) {
    _state = state;
  }

  void detach(WacomSignaturePadState state) {
    if (_state == state) {
      _state = null;
    }
  }

  bool get isConnected => _state?.isConnected ?? false;
  bool get hasInk => _state?.hasInk ?? false;

  Future<void> connect() async {
    await _state?.connect();
  }

  Future<void> disconnect() async {
    await _state?.disconnect();
  }

  Future<bool> detectDevice() async {
    final state = _state;
    if (state != null) {
      return state.detectDevice();
    }
    return WacomSignaturePadNative().detectDevice();
  }

  Future<void> clear() async {
    await _state?.clearFromController();
  }

  Future<Uint8List> toPngBytes() async {
    final state = _state;
    if (state == null) {
      throw StateError('WacomSignaturePadController is not attached to a widget.');
    }
    return state.renderPngBytes();
  }

  Future<String> toBase64() async {
    final bytes = await toPngBytes();
    return base64Encode(bytes);
  }

  Future<File> saveToFile(String path) async {
    final bytes = await toPngBytes();
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
