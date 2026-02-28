import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_wacom_signature_pad/flutter_wacom_signature_pad.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final WacomSignaturePadController _controller =
      WacomSignaturePadController();

  Uint8List? _lastSignature;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Wacom Signature Pad Example')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              WacomSignaturePad(
                width: 500,
                height: 220,
                controller: _controller,
                onSigned: (bytes) {
                  setState(() => _lastSignature = bytes);
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () => _controller.clear(),
                    child: const Text('Clear'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final saved = await _controller.saveToFile(
                        'signature.png',
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Saved to ${saved.path}')),
                      );
                    },
                    child: const Text('Save to File'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_lastSignature != null)
                Expanded(
                  child: Center(
                    child: Image.memory(_lastSignature!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
