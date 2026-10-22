import 'package:flutter/widgets.dart';

import '../data/services/key_service.dart';
import '../domain/models.dart';

/// A setting a plugin needs, such as an API key. Values are kept in the phone's secure storage under [key].
class PluginField {
  const PluginField(this.key, this.label, {this.secret = false, this.required = true});
  final String key;
  final String label;
  final bool secret;
  final bool required;
}

/// A row on the Add food screen that opens one of the plugin's pages.
class PluginLink {
  const PluginLink(this.icon, this.title, this.page);
  final IconData icon;
  final String title;
  final Widget Function(DateTime day, Meal meal) page;
}

/// One row in a plugin's search results. [id] is the plugin's own reference, passed back to [FoodSearch.load].
class SearchHit {
  const SearchHit(this.id, this.name, this.detail, this.calories, {this.photo});
  final String id;
  final String name;
  final String detail;
  final double? calories;
  final String? photo;
}

/// A titled group of hits, such as "Common" or "Branded".
class SearchGroup {
  const SearchGroup(this.title, this.hits, {this.preview = 10});
  final String title;
  final List<SearchHit> hits;

  /// How many rows to show while every group is on screen.
  final int preview;
}

/// A plugin that replaces USDA as the food search, with results as you type.
abstract class FoodSearch {
  /// The search bar's hint, e.g. "Search foods".
  String get hint;
  Future<List<SearchGroup>> search(String query);
  Future<FoodItem> load(SearchHit hit);
}

/// An optional food source or feature that you install from Settings, Plugins. Plugins are part of the app (iOS
/// doesn't allow downloading code), so installing one turns it on and asks for its settings. The core app only
/// uses USDA FoodData Central and Apple Health or Health Connect.
abstract class TrimPlugin {
  TrimPlugin(this.keys);

  final KeyService keys;

  /// Stored in `AppData.plugins`, so it must never change.
  String get id;
  String get title;
  IconData get icon;

  /// One line for the plugin list.
  String get summary;

  /// A paragraph for the plugin's page.
  String get about;

  List<PluginField> get fields => const [];

  /// Where to get the keys in [fields].
  ({String title, String url})? get signup => null;

  /// Whether every required field has a value. A plugin that isn't set up offers nothing yet.
  bool get configured => fields.where((f) => f.required).every((f) => keys.get(f.key) != null);

  // What a plugin can add. Each is only used while the plugin is installed and configured.

  List<PluginLink> get addFoodLinks => const [];

  FoodSearch? get foodSearch => null;

  /// Looks up a barcode, or returns null when this source doesn't know it.
  Future<FoodItem?> barcode(String code) async => null;

  /// A section near the top of the Today tab.
  Widget? todaySection(BuildContext context, DateTime day) => null;

  /// Extra rows on the plugin's page in Settings.
  List<Widget> settingsRows(BuildContext context) => const [];
}
