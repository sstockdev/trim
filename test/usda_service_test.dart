import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trim/data/services/key_service.dart';
import 'package:trim/data/services/usda_service.dart';

const _found =
    '{"foods":[{"fdcId":1,"description":"APPLE","foodNutrients":[{"nutrientNumber":"208","unitName":"KCAL","value":52}]}]}';
const _nginx = '<html><head><title>400 Bad Request</title></head></html>';

/// Answers each request with the next reply in [replies], recording the URLs in [seen].
UsdaService _usda(List<(int, String)> replies, List<Uri> seen) {
  final client = MockClient((req) async {
    seen.add(req.url);
    final (code, body) = replies.removeAt(0);
    return http.Response(body, code);
  });
  return UsdaService(client: client, keys: KeyService(), retryDelay: Duration.zero);
}

void main() {
  test('search retries the stray nginx 400s USDA sends for valid requests', () async {
    final seen = <Uri>[];
    final foods = await _usda([(400, _nginx), (400, _nginx), (200, _found)], seen).search('apple');
    expect(seen, hasLength(3));
    expect(foods.single.name, 'Apple');
    expect(foods.single.base.calories, 52);
  });

  test('search retries a 5xx', () async {
    final seen = <Uri>[];
    final foods = await _usda([(502, ''), (200, _found)], seen).search('apple');
    expect(seen, hasLength(2));
    expect(foods, hasLength(1));
  });

  test('search gives up after the last attempt', () async {
    final seen = <Uri>[];
    final usda = _usda([for (var i = 0; i < UsdaService.attempts; i++) (400, _nginx)], seen);
    await expectLater(usda.search('apple'), throwsA(isA<FoodError>()));
    expect(seen, hasLength(UsdaService.attempts));
  });

  test("a 400 from the API itself isn't retried", () async {
    final seen = <Uri>[];
    final usda = _usda([(400, '{"error":"bad query"}')], seen);
    await expectLater(usda.search('apple'), throwsA(isA<FoodError>()));
    expect(seen, hasLength(1));
  });

  test("the rate limit isn't retried", () async {
    final seen = <Uri>[];
    await expectLater(_usda([(429, '')], seen).search('apple'), throwsA(FoodError.limit));
    expect(seen, hasLength(1));
  });

  test("a rejected key isn't retried", () async {
    final seen = <Uri>[];
    await expectLater(_usda([(403, '')], seen).check('bad'), throwsA(FoodError.rejectedKey));
    expect(seen, hasLength(1));
  });
}
