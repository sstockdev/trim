import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/app_repository.dart';
import '../../domain/format.dart';
import '../../domain/models.dart';
import '../../ui/core/theme.dart';
import '../../ui/core/view_model.dart';
import '../../ui/core/widgets.dart';
import '../../ui/features/add_food/views/food_detail_page.dart';
import 'nutritionix_plugin.dart';

/// Nutritionix's natural-language logging: type what you ate, get each food, pick which to log.
class DescribeMealViewModel extends ViewModel {
  DescribeMealViewModel({required this._plugin, required this._repository});

  final NutritionixPlugin _plugin;
  final AppRepository _repository;

  List<FoodItem> items = const [];
  Set<int> included = {};
  bool loading = false;
  String? error;

  bool get available => _plugin.configured;

  double get total => included.fold(0.0, (s, i) => s + items[i].base.calories);

  Future<void> lookUp(String text) async {
    loading = true;
    notifyListeners();
    try {
      items = await _plugin.natural(text);
      included = {for (var i = 0; i < items.length; i++) i};
      error = null;
    } on Exception catch (e) {
      error = '$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void toggle(int i) {
    if (!included.remove(i)) included.add(i);
    notifyListeners();
  }

  void logIncluded({required Meal meal, required DateTime day}) {
    for (final i in included.toList()..sort()) {
      _repository.log(items[i], serving: 0, amount: items[i].servings[0].defaultAmount, meal: meal, day: day);
    }
  }
}

/// Nutritionix's natural-language logging: type what you ate, get each food.
class DescribeMealPage extends StatelessWidget {
  const DescribeMealPage({super.key, required this.plugin, required this.day, required this.meal});
  final NutritionixPlugin plugin;
  final DateTime day;
  final Meal meal;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => DescribeMealViewModel(plugin: plugin, repository: c.read<AppRepository>()),
    child: _DescribeMealView(day: day, meal: meal),
  );
}

class _DescribeMealView extends StatefulWidget {
  const _DescribeMealView({required this.day, required this.meal});
  final DateTime day;
  final Meal meal;
  @override
  State<_DescribeMealView> createState() => _DescribeMealViewState();
}

class _DescribeMealViewState extends State<_DescribeMealView> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DescribeMealViewModel>();
    final canLook = _text.text.trim().isNotEmpty && !vm.loading && vm.available;
    return Scaffold(
      appBar: AppBar(title: const Text('Describe a meal')),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          Section(
            footerText: vm.available ? null : 'Add your Nutritionix keys in Settings, Plugins.',
            children: [
              TextField(
                controller: _text,
                minLines: 3,
                maxLines: 6,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'e.g. 2 scrambled eggs, wheat toast with butter, large latte',
                  border: InputBorder.none,
                ),
              ),
              RowButton(
                onTap: canLook ? () => vm.lookUp(_text.text) : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Look up', style: TextStyle(color: context.colors.primary)),
                    ),
                    if (vm.loading) const Busy(),
                  ],
                ),
              ),
            ],
          ),
          if (vm.error case final error?)
            Section(
              children: [Text(error, style: const TextStyle(color: TrimColors.orange))],
            ),
          if (vm.items.isNotEmpty) ...[
            Section(
              children: [
                for (var i = 0; i < vm.items.length; i++)
                  RowButton(
                    onTap: () => vm.toggle(i),
                    child: Row(
                      children: [
                        Icon(
                          vm.included.contains(i) ? Icons.check_circle : Icons.circle_outlined,
                          color: context.colors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(vm.items[i].name),
                              Text(
                                '${Fmt.amount(vm.items[i].servings[0].defaultAmount)} ${vm.items[i].servings[0].name}',
                                style: TextStyle(fontSize: 12, color: context.secondaryText),
                              ),
                            ],
                          ),
                        ),
                        Text(Fmt.kcal(vm.items[i].base.calories), style: TextStyle(color: context.secondaryText)),
                      ],
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton(
                onPressed: vm.included.isEmpty
                    ? null
                    : () {
                        vm.logIncluded(meal: widget.meal, day: widget.day);
                        closeToRoot(context);
                      },
                child: Text('Log ${vm.included.length} foods · ${Fmt.kcal(vm.total)} kcal'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
