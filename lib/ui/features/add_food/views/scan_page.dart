import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../../plugins/plugin_registry.dart';
import '../../../../domain/models.dart';
import '../../../core/theme.dart';
import '../view_models/lookup_view_models.dart';
import 'food_detail_page.dart';

/// Scan a barcode, look it up (installed plugins, then USDA), then pick an amount.
class ScanPage extends StatelessWidget {
  const ScanPage({super.key, required this.day, required this.meal});
  final DateTime day;
  final Meal meal;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => ScanViewModel(plugins: c.read<PluginRegistry>()),
    child: _ScanView(day: day, meal: meal),
  );
}

class _ScanView extends StatefulWidget {
  const _ScanView({required this.day, required this.meal});
  final DateTime day;
  final Meal meal;
  @override
  State<_ScanView> createState() => _ScanViewState();
}

class _ScanViewState extends State<_ScanView> {
  final _scanner = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.itf14,
    ],
  );
  final _manual = TextEditingController();

  @override
  void dispose() {
    _scanner.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _look(String code) async {
    final item = await context.read<ScanViewModel>().lookUp(code);
    if (item == null || !mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => FoodDetailPage.item(item, day: widget.day, meal: widget.meal),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ScanViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _scanner,
                  onDetect: (capture) {
                    if (vm.code != null) return;
                    final value = capture.barcodes
                        .map((b) => b.rawValue)
                        .whereType<String>()
                        .where((v) => v.isNotEmpty)
                        .firstOrNull;
                    if (value == null) return;
                    HapticFeedback.mediumImpact();
                    _look(value);
                  },
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.qr_code_scanner, size: 40),
                          const SizedBox(height: 8),
                          const Text("Camera scanning isn't available", style: TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            'Allow camera access in Settings, or type the number below.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.secondaryText),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (vm.loading) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (vm.error case final error?) ...[
                    Text(error, style: const TextStyle(color: TrimColors.orange)),
                    TextButton(onPressed: vm.reset, child: const Text('Scan again')),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manual,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Or type the barcode number',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: _manual.text.length < 8 || vm.loading ? null : () => _look(_manual.text),
                        child: const Text('Look up'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
