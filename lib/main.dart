import 'dart:io';

import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'data/repositories/app_repository.dart';
import 'data/services/data_file_service.dart';
import 'data/services/health_service.dart';
import 'data/services/key_service.dart';
import 'data/services/usda_service.dart';
import 'plugins/ndsu_dining/ndsu_dining_plugin.dart';
import 'plugins/nutritionix/nutritionix_plugin.dart';
import 'plugins/open_food_facts/open_food_facts_plugin.dart';
import 'plugins/plugin_registry.dart';
import 'ui/core/theme.dart';
import 'ui/core/widgets.dart';
import 'ui/features/home/views/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final files = DataFileService();
  final health = HealthService();
  final keys = KeyService();
  // On iOS, requests go through NSURLSession like the dining web view does. Dart's own sockets failed to look up
  // hosts on the iPhone.
  final client = Platform.isIOS ? CupertinoClient.defaultSessionConfiguration() : http.Client();
  final plugins = [
    NdsuDiningPlugin(keys),
    NutritionixPlugin(keys, client: client),
    OpenFoodFactsPlugin(keys, client: client),
  ];
  final (loaded, _) = await (files.load(), keys.load([for (final p in plugins) ...p.fields.map((f) => f.key)])).wait;
  final repository = AppRepository(files: files, health: health, loaded: loaded);
  final usda = UsdaService(client: client, keys: keys);
  final registry = PluginRegistry(all: plugins, repository: repository, usda: usda);

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: keys),
        Provider.value(value: usda),
        ChangeNotifierProvider.value(value: repository),
        ChangeNotifierProvider.value(value: registry),
      ],
      child: const TrimApp(),
    ),
  );
}

class TrimApp extends StatelessWidget {
  const TrimApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: appName,
    theme: TrimTheme.light,
    darkTheme: TrimTheme.dark,
    debugShowCheckedModeBanner: false,
    home: const HomePage(),
  );
}
