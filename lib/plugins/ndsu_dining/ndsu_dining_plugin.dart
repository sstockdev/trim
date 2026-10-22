import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/app_repository.dart';
import '../../ui/core/theme.dart';
import '../../ui/core/widgets.dart';
import '../plugin.dart';
import 'data/jamix_service.dart';
import 'views/dining_menu_page.dart';
import 'views/dining_usuals.dart';

/// NDSU Dining: the menus and nutrition labels of Union Market, the Residence and West Dining Centers and Twisted
/// Taco, read from usa.jamix.cloud in a hidden web view.
class NdsuDiningPlugin extends TrimPlugin {
  NdsuDiningPlugin(super.keys);

  /// One web view for the whole app, so only one hall page is ever loaded.
  final jamix = JamixService();

  @override
  String get id => 'ndsu_dining';
  @override
  String get title => 'NDSU Dining';
  @override
  IconData get icon => Icons.account_balance;
  @override
  String get summary => 'Dining hall menus';
  @override
  String get about => 'Menus and nutrition labels for Union Market, Residence, West and Twisted Taco. No key needed.';

  @override
  List<PluginLink> get addFoodLinks => [
    PluginLink(icon, 'NDSU Dining menus', (day, meal) => DiningMenuPage(jamix: jamix, day: day, meal: meal)),
  ];

  @override
  Widget todaySection(BuildContext context, DateTime day) => DiningUsuals(jamix: jamix, day: day);

  @override
  List<Widget> settingsRows(BuildContext context) {
    final repository = context.watch<AppRepository>();
    final labels = repository.data.market.length;
    return [
      KeyValue('Cached labels', '$labels'),
      RowButton(
        onTap: labels == 0 && repository.data.menus.isEmpty
            ? null
            : () => repository.update((d) {
                d.market.clear();
                d.menus.clear();
              }),
        child: Text('Clear cached menus and labels', style: TextStyle(color: context.colors.primary)),
      ),
    ];
  }
}
