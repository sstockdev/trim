import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models.dart';
import 'key_service.dart';

class FoodError implements Exception {
  final String message;
  const FoodError(this.message);

  static const limit = FoodError(
    'The daily search limit was reached. Try again later or add your own USDA key in Settings.',
  );
  static const rejectedKey = FoodError("USDA didn't accept your key. Check it in Settings, Food search.");
  static const notFound = FoodError('No match found.');
  static const offline = FoodError("Couldn't reach the food database. Check your connection.");
  static const unreadable = FoodError("Couldn't read the food database's reply.");
  static FoodError server(int code) => FoodError('The food database returned an error ($code).');

  @override
  String toString() => message;
}

/// USDA FoodData Central, the app's own food search. Plugins can add other sources. Stateless apart from the
/// injected HTTP client and keys.
class UsdaService {
  UsdaService({required this.client, required this._keys, this.retryDelay = const Duration(milliseconds: 250)});

  static const timeout = Duration(seconds: 15);
  static const signup = 'https://api.data.gov/signup/';

  final http.Client client;
  final KeyService _keys;
  final Duration retryDelay;

  /// USDA's shared demo key works but is rate-limited; a free personal key from api.data.gov lifts the limit.
  String get key => _keys.get(KeyService.usda) ?? 'DEMO_KEY';
  bool get hasKey => key != 'DEMO_KEY';

  /// Without a personal key, USDA's shared key allows only a few dozen searches an hour, so search on submit.
  bool get liveSearch => hasKey;

  /// USDA's servers answer a share of valid requests with a bare nginx 400 page (about 40 % in October 2026), so
  /// that and a 5xx are retried a few times before they count. A 400 from the API itself is JSON and isn't retried.
  static const attempts = 4;

  Future<http.Response> _get(Uri uri) async {
    for (var attempt = 1; ; attempt++) {
      final resp = await send(client.get(uri));
      final code = resp.statusCode;
      final stray = code >= 500 || (code == 400 && !resp.body.trimLeft().startsWith('{'));
      if (attempt == attempts || !stray) return resp;
      await Future<void>.delayed(retryDelay * attempt);
    }
  }

  /// Tries [key] with a one-result search. Throws a [FoodError] when USDA refuses it.
  Future<void> check(String key) async {
    final uri = Uri.https('api.nal.usda.gov', '/fdc/v1/foods/search', {
      'api_key': key,
      'query': 'apple',
      'pageSize': '1',
    });
    final resp = await _get(uri);
    if (resp.statusCode == 401 || resp.statusCode == 403) throw FoodError.rejectedKey;
    jsonOf(resp);
  }

  Future<List<FoodItem>> search(String query) async {
    // Uri encodes "(", ")" and "+" in query values, which USDA's server needs (it rejects a raw "Survey (FNDDS)").
    final uri = Uri.https('api.nal.usda.gov', '/fdc/v1/foods/search', {
      'api_key': key,
      'query': query,
      'pageSize': '30',
      'dataType': 'Foundation,SR Legacy,Survey (FNDDS),Branded',
    });
    final r = jsonOf(await _get(uri));
    return listOf(r['foods']).map(_usdaItem).whereType<FoodItem>().toList();
  }

  /// Branded foods carry their UPC in `gtinUpc`, so a search for the digits finds the product.
  Future<FoodItem?> barcode(String code) async {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    final uri = Uri.https('api.nal.usda.gov', '/fdc/v1/foods/search', {
      'api_key': key,
      'query': digits,
      'pageSize': '10',
      'dataType': 'Branded',
    });
    final r = jsonOf(await _get(uri));
    String bare(Object? v) => (v?.toString() ?? '').replaceFirst(RegExp('^0+'), '');
    for (final f in listOf(r['foods'])) {
      if (bare(f['gtinUpc']) != bare(digits)) continue;
      final item = _usdaItem(f);
      if (item != null) return item;
    }
    return null;
  }

  static FoodItem? _usdaItem(Map<String, dynamic> f) {
    final desc = f['description'];
    if (desc is! String) return null;
    final byNumber = <String, double>{};
    for (final n in listOf(f['foodNutrients'])) {
      final number = n['nutrientNumber'], v = parseNum(n['value']);
      if (number is! String || v == null) continue;
      if (number == '208' && (n['unitName'] as String?)?.toUpperCase() != 'KCAL') continue;
      byNumber[number] = v;
    }
    // Values are per 100 g.
    final base = Nutrients(
      calories: byNumber['208'] ?? byNumber['958'] ?? byNumber['957'] ?? 0,
      protein: byNumber['203'] ?? 0,
      carbs: byNumber['205'] ?? 0,
      fat: byNumber['204'] ?? 0,
      fiber: byNumber['291'] ?? 0,
      sugar: byNumber['269'] ?? 0,
      sodium: byNumber['307'] ?? 0,
      saturatedFat: byNumber['606'] ?? 0,
    );
    final servings = <Serving>[];
    final size = parseNum(f['servingSize']);
    final unit = (f['servingSizeUnit'] as String?)?.toLowerCase();
    if (size != null && size > 0 && const ['g', 'grm', 'ml', 'mlt'].contains(unit)) {
      final label = f['householdServingFullText'];
      servings.add(
        Serving(
          label is String && label.isNotEmpty ? 'serving ($label)' : 'serving (${size.toInt()} g)',
          size / 100,
          grams: size,
        ),
      );
    }
    for (final m in listOf(f['foodMeasures'])) {
      final text = m['disseminationText'], g = parseNum(m['gramWeight']);
      if (text is! String || g == null || g <= 0 || text.toLowerCase() == 'quantity not specified') continue;
      servings.add(Serving(text, g / 100, grams: g));
    }
    servings.addAll(Serving.weightOptions(100));
    return FoodItem(
      name: capitalizedFirstOnly(desc),
      brand: (f['brandName'] as String?) ?? (f['brandOwner'] as String?),
      source: FoodSource.usda,
      externalID: f['fdcId']?.toString(),
      base: base,
      servings: servings,
    );
  }
}

/// Waits for a request with the shared timeout, turning a network failure into [FoodError.offline].
Future<http.Response> send(Future<http.Response> request) async {
  try {
    return await request.timeout(UsdaService.timeout);
  } on TimeoutException {
    throw FoodError.offline;
  } on http.ClientException catch (e) {
    debugPrint('Trim: request failed: $e');
    throw FoodError.offline;
  }
}

/// Turns an HTTP reply into a JSON object, or throws a [FoodError] that says what went wrong.
Map<String, dynamic> jsonOf(http.Response resp) {
  final code = resp.statusCode;
  if (code == 404) throw FoodError.notFound;
  if (code == 429) throw FoodError.limit;
  if (code < 200 || code >= 300) throw FoodError.server(code);
  try {
    final obj = jsonDecode(utf8.decode(resp.bodyBytes));
    if (obj is Map<String, dynamic>) return obj;
  } catch (_) {}
  throw FoodError.unreadable;
}

List<Map<String, dynamic>> listOf(Object? v) => v is List<dynamic> ? v.whereType<Map<String, dynamic>>().toList() : [];

double? parseNum(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.'));
  return null;
}

String capitalizedFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// USDA names come in ALL CAPS for branded foods; tame them.
String capitalizedFirstOnly(String s) {
  final letters = s.replaceAll(RegExp(r'[^A-Za-z]'), '');
  final shouting = letters.isNotEmpty && letters == letters.toUpperCase();
  return shouting ? capitalizedFirst(s.toLowerCase()) : capitalizedFirst(s);
}
