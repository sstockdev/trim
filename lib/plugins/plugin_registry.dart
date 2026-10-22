import 'package:flutter/foundation.dart';

import '../data/repositories/app_repository.dart';
import '../data/services/usda_service.dart';
import '../domain/models.dart';
import 'plugin.dart';

/// Every plugin the app ships with, and which ones you've installed (`AppData.plugins`). Screens ask this for what
/// the active plugins add rather than knowing about any plugin.
class PluginRegistry extends ChangeNotifier {
  PluginRegistry({required this.all, required this._repository, required this._usda}) {
    if (_repository.data.plugins == null) _migrate();
  }

  final List<TrimPlugin> all;
  final AppRepository _repository;
  final UsdaService _usda;

  List<String> get _ids => _repository.data.plugins ?? const [];

  bool isInstalled(TrimPlugin p) => _ids.contains(p.id);

  List<TrimPlugin> get installed => all.where(isInstalled).toList();

  /// Installed and set up.
  List<TrimPlugin> get active => installed.where((p) => p.configured).toList();

  void install(TrimPlugin p) {
    if (isInstalled(p)) return;
    _repository.update((d) => d.plugins = [..._ids, p.id]);
    notifyListeners();
  }

  /// Removes the plugin and forgets its keys. Food it logged stays in your log.
  Future<void> uninstall(TrimPlugin p) async {
    _repository.update((d) => d.plugins = _ids.where((id) => id != p.id).toList());
    for (final f in p.fields) {
      await p.keys.set(f.key, null);
    }
    notifyListeners();
  }

  Future<void> setField(TrimPlugin p, PluginField f, String? value) async {
    await p.keys.set(f.key, value);
    notifyListeners();
  }

  /// The first active plugin that replaces USDA search, or null to search USDA.
  FoodSearch? get foodSearch => active.map((p) => p.foodSearch).nonNulls.firstOrNull;

  List<PluginLink> get addFoodLinks => [for (final p in active) ...p.addFoodLinks];

  /// Asks each active plugin in turn, then USDA's branded foods. Null when nobody knows the code.
  Future<FoodItem?> barcode(String code) async {
    for (final p in active) {
      try {
        if (await p.barcode(code) case final item?) return item;
      } on Exception {
        // One source failing shouldn't stop the next.
      }
    }
    return _usda.barcode(code);
  }

  /// Files from before plugins existed: keep what you were using. NDSU Dining if you've read a menu or logged
  /// from a hall, Nutritionix if its keys are set, and Open Food Facts, which used to look up every barcode.
  void _migrate() {
    final d = _repository.data;
    if (!d.onboarded) {
      d.plugins = [];
      return;
    }
    final dining =
        d.market.isNotEmpty || d.menus.isNotEmpty || d.saved.any((s) => DiningHall.ofSource(s.item.source) != null);
    d.plugins = [
      for (final p in all)
        if ((p.id == 'ndsu_dining' && dining) || p.id == 'open_food_facts' || (p.id == 'nutritionix' && p.configured))
          p.id,
    ];
    _repository.changed();
  }
}
