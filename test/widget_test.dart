import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:trim/data/repositories/app_repository.dart';
import 'package:trim/data/services/data_file_service.dart';
import 'package:trim/data/services/health_service.dart';
import 'package:http/http.dart' as http;
import 'package:trim/data/services/key_service.dart';
import 'package:trim/data/services/usda_service.dart';
import 'package:trim/domain/models.dart';
import 'package:trim/plugins/ndsu_dining/ndsu_dining_plugin.dart';
import 'package:trim/plugins/nutritionix/nutritionix_plugin.dart';
import 'package:trim/plugins/open_food_facts/open_food_facts_plugin.dart';
import 'package:trim/plugins/plugin_registry.dart';
import 'package:trim/ui/features/home/views/home_page.dart';

PluginRegistry _registry(AppRepository repository, KeyService keys) {
  final client = http.Client();
  return PluginRegistry(
    all: [
      NdsuDiningPlugin(keys),
      NutritionixPlugin(keys, client: client),
      OpenFoodFactsPlugin(keys, client: client),
    ],
    repository: repository,
    usda: UsdaService(client: client, keys: keys),
  );
}

Widget _app(AppRepository repository) {
  final keys = KeyService();
  final registry = _registry(repository, keys);
  return MultiProvider(
    providers: [
      Provider.value(value: keys),
      Provider(
        create: (_) => UsdaService(client: http.Client(), keys: keys),
      ),
      ChangeNotifierProvider.value(value: repository),
      ChangeNotifierProvider.value(value: registry),
    ],
    child: const MaterialApp(home: HomePage()),
  );
}

AppRepository _repository(AppData data) =>
    AppRepository(files: DataFileService(), health: HealthService(), loaded: LoadedData(data));

void main() {
  testWidgets('onboarding starts at the welcome step and moves on', (tester) async {
    await tester.pumpWidget(_app(_repository(AppData())));
    expect(find.text('Welcome'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('About you'), findsOneWidget);
  });

  testWidgets('Today shows the day\'s food against the target', (tester) async {
    final now = DateTime.now();
    final data = AppData(onboarded: true, plugins: [])
      ..profile.planStart = now
      ..entries.add(
        FoodEntry(
          date: now,
          meal: Meal.lunch,
          item: FoodItem(
            name: 'Grilled Chicken',
            source: FoodSource.custom,
            base: const Nutrients(calories: 300, protein: 40),
          ),
          serving: 0,
          amount: 1,
        ),
      );
    await tester.pumpWidget(_app(_repository(data)));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsWidgets);
    expect(find.textContaining('300 of'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Grilled Chicken'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Grilled Chicken'), findsOneWidget);
  });

  test('plugins: files from before plugins keep what they used', () {
    final dining = AppData(onboarded: true)
      ..market['grilled chicken'] = MarketItem(
        name: 'Grilled Chicken',
        hall: DiningHall.unionMarket,
        station: 'Grill',
        nutrients: Nutrients(calories: 200),
        portion: '',
      );
    final repository = _repository(dining);
    final registry = _registry(repository, KeyService());
    expect(repository.data.plugins, ['ndsu_dining', 'open_food_facts']);
    expect(registry.addFoodLinks.single.title, 'NDSU Dining menus');
    // Nutritionix isn't set up, so it doesn't replace USDA search.
    expect(registry.foodSearch, isNull);

    final fresh = _repository(AppData());
    final none = _registry(fresh, KeyService());
    expect(fresh.data.plugins, isEmpty);
    none.install(none.all.firstWhere((p) => p.id == 'open_food_facts'));
    expect(fresh.data.plugins, ['open_food_facts']);
    final json = AppData.fromJson(fresh.data.toJson());
    expect(json.plugins, ['open_food_facts']);
  });
}
