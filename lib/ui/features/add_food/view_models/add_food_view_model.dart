import 'dart:async';

import '../../../../data/repositories/app_repository.dart';
import '../../../../data/services/usda_service.dart';
import '../../../../domain/models.dart';
import '../../../../plugins/plugin.dart';
import '../../../../plugins/plugin_registry.dart';
import '../../../core/view_model.dart';

/// Search shows foods you've logged before, then results from USDA FoodData Central, or from a plugin that
/// replaces it (Nutritionix, in titled groups that update as you type).
class AddFoodViewModel extends ViewModel {
  AddFoodViewModel({
    required this._usda,
    required PluginRegistry plugins,
    required this._repository,
    required this._meal,
  }) : _search = plugins.foodSearch;

  final UsdaService _usda;
  final AppRepository _repository;
  final FoodSearch? _search;

  Meal _meal;
  Meal get meal => _meal;
  set meal(Meal m) {
    _meal = m;
    notifyListeners();
  }

  String _query = '';
  String get query => _query;

  /// The group shown on its own, or null for all of them.
  String? _group;
  String? get group => _group;
  set group(String? g) {
    _group = g;
    notifyListeners();
  }

  List<SearchGroup> groups = const [];
  List<FoodItem> usda = const [];
  bool searching = false;
  String? error;
  Timer? _debounce;

  /// The plugin's search hint, or USDA's.
  String get hint => _search?.hint ?? 'Search USDA foods';
  bool get usesPlugin => _search != null;
  bool get liveSearch => _search != null || _usda.liveSearch;
  bool get hasUsdaKey => _usda.hasKey;

  List<SavedFood> get yourFoods => _repository.savedMatching(_query);

  void setQuery(String text) {
    _query = text.trim();
    notifyListeners();
    if (!liveSearch) return;
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: usesPlugin ? 250 : 500), () => search());
  }

  /// Runs the search for the current text. With the shared USDA key the view calls this on submit.
  Future<void> search() async {
    final q = _query;
    if (q.length < 2) {
      groups = const [];
      usda = const [];
      error = null;
      notifyListeners();
      return;
    }
    searching = true;
    notifyListeners();
    try {
      if (_search case final s?) {
        final r = await s.search(q);
        if (q != _query) return;
        groups = r;
      } else {
        final r = await _usda.search(q);
        if (q != _query) return;
        usda = r;
      }
      error = null;
    } on Exception catch (e) {
      if (q == _query) error = '$e';
    } finally {
      searching = false;
      notifyListeners();
    }
  }

  Future<FoodItem> load(SearchHit hit) => _search!.load(hit);

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
