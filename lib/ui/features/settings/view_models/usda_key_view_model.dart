import '../../../../data/services/key_service.dart';
import '../../../../data/services/usda_service.dart';
import '../../../core/view_model.dart';

/// Your USDA FoodData Central key: typed, checked against USDA, then saved.
class UsdaKeyViewModel extends ViewModel {
  UsdaKeyViewModel({required this._keys, required this._usda});

  final KeyService _keys;
  final UsdaService _usda;

  String get saved => _keys.get(KeyService.usda) ?? '';
  bool get hasKey => _usda.hasKey;

  bool checking = false;

  /// What the last check found: null before one, else a message and whether the key works.
  ({String message, bool ok})? result;

  /// Checks [key] with USDA and saves it if it works. An empty key goes back to the shared demo key.
  Future<void> save(String key) async {
    final k = key.trim();
    if (k.isEmpty) {
      await _keys.set(KeyService.usda, null);
      result = null;
      notifyListeners();
      return;
    }
    checking = true;
    result = null;
    notifyListeners();
    try {
      await _usda.check(k);
      await _keys.set(KeyService.usda, k);
      result = (message: 'Saved', ok: true);
    } on Exception catch (e) {
      result = (message: '$e', ok: false);
    } finally {
      checking = false;
      notifyListeners();
    }
  }
}
