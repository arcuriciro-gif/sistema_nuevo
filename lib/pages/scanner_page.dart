import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool _escaneado = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear código')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_escaneado) return;
          final barcode =
              capture.barcodes.isNotEmpty ? capture.barcodes.first : null;
          if (barcode?.rawValue != null) {
            _escaneado = true;
            Navigator.pop(context, barcode!.rawValue);
          }
        },
      ),
    );
  }
}
