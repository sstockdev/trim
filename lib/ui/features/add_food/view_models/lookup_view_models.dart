import '../../../../plugins/plugin_registry.dart';
import '../../../../domain/models.dart';
import '../../../core/view_model.dart';

/// A barcode lookup: each installed plugin that reads barcodes, then USDA's branded foods.
class ScanViewModel extends ViewModel {
  ScanViewModel({required this._plugins});

  final PluginRegistry _plugins;

  /// The code being looked up or last looked up; scanning pauses while it's set.
  String? code;
  bool loading = false;
  String? error;

  Future<FoodItem?> lookUp(String c) async {
    code = c;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final item = await _plugins.barcode(c);
      if (item == null) error = 'No nutrition found for $c. Try search or quick add.';
      return item;
    } on Exception {
      error = 'No nutrition found for $c. Try search or quick add.';
      return null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void reset() {
    code = null;
    error = null;
    notifyListeners();
  }
}
