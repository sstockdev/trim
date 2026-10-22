import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../data/services/usda_service.dart';
import '../../domain/format.dart';
import '../../domain/models.dart';
import '../plugin.dart';
import 'describe_meal_page.dart';

/// Nutritionix, through its v2 API at trackapi.nutritionix.com: search as you type, natural-language
/// logging and barcodes. It needs your own app ID and key, since the free API is gone.
class NutritionixPlugin extends TrimPlugin implements FoodSearch {
  NutritionixPlugin(super.keys, {required this._client});

  static const appID = 'nutritionix.appID';
  static const appKey = 'nutritionix.appKey';
  static const _base = 'https://trackapi.nutritionix.com/v2/';
  static const noKeys = FoodError('Add your Nutritionix keys in Settings, Plugins.');
  static const rejectedKeys = FoodError("Nutritionix didn't accept your keys. Check them in Settings, Plugins.");

  final http.Client _client;

  @override
  String get id => 'nutritionix';
  @override
  String get title => 'Nutritionix';
  @override
  IconData get icon => Icons.restaurant_menu;
  @override
  String get summary => 'Restaurant and branded foods';
  @override
  String get about => 'Searches Nutritionix instead of USDA and adds Describe a meal. Needs your own app ID and key.';
  @override
  List<PluginField> get fields => const [
    PluginField(appID, 'App ID'),
    PluginField(appKey, 'App key', secret: true),
  ];
  @override
  ({String title, String url}) get signup =>
      (title: 'Get Nutritionix keys', url: 'https://developer.nutritionix.com/signup');

  @override
  FoodSearch get foodSearch => this;

  @override
  List<PluginLink> get addFoodLinks => [
    PluginLink(
      Icons.chat_bubble_outline,
      'Describe a meal',
      (day, meal) => DescribeMealPage(plugin: this, day: day, meal: meal),
    ),
  ];

  // FoodSearch

  @override
  String get hint => 'Search foods';

  /// `GET search/instant`: generic foods ("common") and packaged or restaurant foods ("branded"), with common foods
  /// deduplicated by tag_id.
  @override
  Future<List<SearchGroup>> search(String query) async {
    final r = await _nix('search/instant', query: {'query': query, 'detailed': 'true'});
    final seen = <String>{};
    final common = <SearchHit>[];
    for (final f in listOf(r['common'])) {
      final name = f['food_name'];
      if (name is! String) continue;
      final tag = f['tag_id']?.toString() ?? name;
      if (!seen.add(tag)) continue;
      final qty = parseNum(f['serving_qty']) ?? 1;
      final unit = f['serving_unit'] as String? ?? 'serving';
      common.add(
        SearchHit(
          'c|$name',
          capitalizedFirst(name),
          '${Fmt.amount(qty)} $unit',
          _fullNutrient(f, 208),
          photo: _photo(f),
        ),
      );
    }
    final branded = <SearchHit>[];
    for (final f in listOf(r['branded'])) {
      final name = f['food_name'], id = f['nix_item_id'];
      if (name is! String || id is! String) continue;
      final qty = parseNum(f['serving_qty']) ?? 1;
      final unit = f['serving_unit'] as String? ?? 'serving';
      final brand = f['brand_name'] as String? ?? '';
      branded.add(
        SearchHit('b|$id', name, '$brand · ${Fmt.amount(qty)} $unit', parseNum(f['nf_calories']), photo: _photo(f)),
      );
    }
    return [SearchGroup('Common', common, preview: 8), SearchGroup('Branded', branded, preview: 12)];
  }

  /// Common hits need `POST natural/nutrients` for their details, branded ones `GET search/item`.
  @override
  Future<FoodItem> load(SearchHit hit) async {
    final ref = hit.id.substring(2);
    if (hit.id.startsWith('c|')) return (await natural(ref)).first;
    final foods = listOf((await _nix('search/item', query: {'nix_item_id': ref}))['foods']);
    if (foods.isEmpty) throw FoodError.notFound;
    return _item(foods.first);
  }

  /// Describe a meal in words ("2 eggs, toast with butter and a coffee") and get each food back.
  Future<List<FoodItem>> natural(String text) async {
    final r = await _nix('natural/nutrients', body: {'query': text, 'line_delimited': false, 'use_raw_foods': false});
    final foods = listOf(r['foods']).map(_item).toList();
    if (foods.isEmpty) throw FoodError.notFound;
    return foods;
  }

  @override
  Future<FoodItem?> barcode(String code) async {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    // Scanners report UPC-A as 13-digit EAN with a leading 0.
    for (final v in {digits, if (digits.length == 13 && digits.startsWith('0')) digits.substring(1)}) {
      try {
        final foods = listOf((await _nix('search/item', query: {'upc': v}))['foods']);
        if (foods.isNotEmpty) return _item(foods.first)..externalID ??= v;
      } on FoodError catch (e) {
        if (e != FoodError.notFound) rethrow;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _nix(String path, {Map<String, String>? query, Object? body}) async {
    final id = keys.get(appID), key = keys.get(appKey);
    if (id == null || key == null) throw noKeys;
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final headers = {'x-app-id': id, 'x-app-key': key, 'x-remote-user-id': '0'};
    final request = body != null
        ? _client.post(uri, headers: {...headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        : _client.get(uri, headers: headers);
    final resp = await send(request);
    if (resp.statusCode == 401 || resp.statusCode == 403) throw rejectedKeys;
    return jsonOf(resp);
  }

  static FoodItem _item(Map<String, dynamic> f) {
    final qty = (parseNum(f['serving_qty']) ?? 1).clamp(0.0001, double.infinity).toDouble();
    final rawUnit = f['serving_unit'];
    final unit = rawUnit is String && rawUnit.isNotEmpty ? rawUnit : 'serving';
    final g = parseNum(f['serving_weight_grams']);
    final grams = g != null && g > 0 ? g : null;
    final base = Nutrients(
      calories: parseNum(f['nf_calories']) ?? _fullNutrient(f, 208) ?? 0,
      protein: parseNum(f['nf_protein']) ?? 0,
      carbs: parseNum(f['nf_total_carbohydrate']) ?? 0,
      fat: parseNum(f['nf_total_fat']) ?? 0,
      fiber: parseNum(f['nf_dietary_fiber']) ?? 0,
      sugar: parseNum(f['nf_sugars']) ?? 0,
      sodium: parseNum(f['nf_sodium']) ?? 0,
      saturatedFat: parseNum(f['nf_saturated_fat']) ?? 0,
    );
    final servings = [Serving(unit, 1 / qty, defaultAmount: qty, grams: grams == null ? null : grams / qty)];
    final names = {unit.toLowerCase()};
    if (grams != null) {
      for (final m in listOf(f['alt_measures'])) {
        final measure = m['measure'], w = parseNum(m['serving_weight']);
        if (measure is! String || w == null || w <= 0) continue;
        final mq = (parseNum(m['qty']) ?? 1).clamp(0.0001, double.infinity).toDouble();
        final lower = measure.toLowerCase();
        if (!names.add(lower) || const ['g', 'grams', 'oz'].contains(lower)) continue;
        servings.add(Serving(measure, (w / mq) / grams, defaultAmount: mq, grams: w / mq));
      }
      servings.addAll(Serving.weightOptions(grams));
    }
    return FoodItem(
      name: capitalizedFirst(f['food_name'] as String? ?? 'Food'),
      brand: f['brand_name'] as String?,
      source: FoodSource.nutritionix,
      externalID: f['nix_item_id'] as String?,
      base: base,
      servings: servings,
      photoURL: _photo(f),
    );
  }

  static double? _fullNutrient(Map<String, dynamic> f, int attr) {
    for (final n in listOf(f['full_nutrients'])) {
      if (parseNum(n['attr_id']) == attr) return parseNum(n['value']);
    }
    return null;
  }

  static String? _photo(Map<String, dynamic> f) {
    final p = f['photo'];
    return p is Map ? p['thumb'] as String? : null;
  }
}
