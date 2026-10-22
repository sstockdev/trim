import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../data/services/usda_service.dart';
import '../../domain/models.dart';
import '../plugin.dart';

/// Open Food Facts, a free crowd-sourced database of packaged foods from around the world. Barcodes only.
class OpenFoodFactsPlugin extends TrimPlugin {
  OpenFoodFactsPlugin(super.keys, {required this._client});

  final http.Client _client;

  @override
  String get id => 'open_food_facts';
  @override
  String get title => 'Open Food Facts';
  @override
  IconData get icon => Icons.qr_code_2;
  @override
  String get summary => 'More barcodes';
  @override
  String get about => 'Looks up barcodes USDA doesn\'t know. No key needed.';

  @override
  Future<FoodItem?> barcode(String code) async {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    // Scanners report UPC-A as 13-digit EAN with a leading 0.
    for (final v in {digits, if (digits.length == 13 && digits.startsWith('0')) digits.substring(1)}) {
      final resp = await send(
        _client.get(
          Uri.parse('https://world.openfoodfacts.org/api/v2/product/$v.json'),
          headers: {'User-Agent': 'Trim/1.0 (personal food log)'},
        ),
      );
      if (resp.statusCode == 404) continue;
      final r = jsonOf(resp);
      final p = r['product'];
      if (parseNum(r['status']) != 1 || p is! Map) continue;
      if (_item(p.cast<String, dynamic>(), v) case final item?) return item;
    }
    return null;
  }

  static FoodItem? _item(Map<String, dynamic> p, String code) {
    final n = p['nutriments'];
    if (n is! Map) return null;
    final e = parseNum(n['energy_100g']);
    final kcal = parseNum(n['energy-kcal_100g']) ?? (e == null ? null : e / 4.184);
    if (kcal == null) return null;
    final base = Nutrients(
      calories: kcal,
      protein: parseNum(n['proteins_100g']) ?? 0,
      carbs: parseNum(n['carbohydrates_100g']) ?? 0,
      fat: parseNum(n['fat_100g']) ?? 0,
      fiber: parseNum(n['fiber_100g']) ?? 0,
      sugar: parseNum(n['sugars_100g']) ?? 0,
      sodium: (parseNum(n['sodium_100g']) ?? 0) * 1000,
      saturatedFat: parseNum(n['saturated-fat_100g']) ?? 0,
    );
    final servings = <Serving>[];
    final g = parseNum(p['serving_quantity']);
    if (g != null && g > 0) {
      final size = p['serving_size'];
      final text = size is String && size.isNotEmpty ? size : '${g.toInt()} g';
      servings.add(Serving('serving ($text)', g / 100, grams: g));
    }
    servings.addAll(Serving.weightOptions(100));
    final pn = p['product_name'];
    final brands = p['brands'];
    return FoodItem(
      name: pn is String && pn.isNotEmpty ? pn : 'Product $code',
      brand: brands is String && brands.isNotEmpty ? brands.split(',').first.trim() : null,
      source: FoodSource.openFoodFacts,
      externalID: code,
      base: base,
      servings: servings,
    );
  }
}
