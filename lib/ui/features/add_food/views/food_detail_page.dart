import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/app_repository.dart';
import '../../../../domain/format.dart';
import '../../../../domain/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../view_models/food_detail_view_model.dart';

/// Back to the tabs, closing the add-food screens on top.
void closeToRoot(BuildContext context) => Navigator.of(context).popUntil((r) => r.isFirst);

/// Pick an amount and log a food, or edit a logged entry.
class FoodDetailPage extends StatelessWidget {
  const FoodDetailPage._(this._create);

  /// A food that's ready to log.
  factory FoodDetailPage.item(
    FoodItem item, {
    required DateTime day,
    required Meal meal,
    int? serving,
    double? amount,
  }) => FoodDetailPage._(
    (r) => FoodDetailViewModel.item(r, item, day: day, meal: meal, serving: serving, amount: amount),
  );

  /// A food whose details need a request first.
  factory FoodDetailPage.load(Future<FoodItem> Function() loader, {required DateTime day, required Meal meal}) =>
      FoodDetailPage._((r) => FoodDetailViewModel.load(r, loader, day: day, meal: meal));

  /// Editing a logged entry.
  factory FoodDetailPage.entry(FoodEntry entry) => FoodDetailPage._((r) => FoodDetailViewModel.entry(r, entry));

  final FoodDetailViewModel Function(AppRepository) _create;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => _create(c.read<AppRepository>()),
    child: const _FoodDetailView(),
  );
}

class _FoodDetailView extends StatelessWidget {
  const _FoodDetailView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FoodDetailViewModel>();
    final item = vm.item;
    final error = vm.error;
    return Scaffold(
      appBar: AppBar(title: Text(vm.isEditing ? 'Edit' : 'Add food')),
      body: switch ((item, error)) {
        (final FoodItem item, _) => _form(context, vm, item),
        (null, final String error) => _Failure(error),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  static String _g(double v) => '${v.toStringAsFixed(v < 10 ? 1 : 0)} g';

  Widget _form(BuildContext context, FoodDetailViewModel vm, FoodItem item) {
    final n = vm.nutrients;
    final grams = item.servings[vm.serving].grams;
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      children: [
        Section(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.photoURL != null) ...[FoodThumb(item.photoURL, size: 56), const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                      Text(
                        [item.brand, item.source.title].whereType<String>().join(' · '),
                        style: TextStyle(fontSize: 12, color: context.secondaryText),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: vm.isFavorite ? 'Remove from favorites' : 'Add to favorites',
                  icon: Icon(vm.isFavorite ? Icons.star : Icons.star_border, color: TrimColors.yellow),
                  onPressed: vm.toggleFavorite,
                ),
              ],
            ),
          ],
        ),
        Section(
          children: [
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    title: 'Amount',
                    value: vm.amount,
                    style: const TextStyle(fontSize: 20),
                    onChanged: vm.setAmount,
                  ),
                ),
                IconButton(tooltip: 'Less', icon: const Icon(Icons.remove), onPressed: () => vm.stepAmount(-1)),
                IconButton(tooltip: 'More', icon: const Icon(Icons.add), onPressed: () => vm.stepAmount(1)),
              ],
            ),
            PickerRow<int>(
              label: 'Measure',
              value: vm.serving,
              values: [for (var i = 0; i < item.servings.length; i++) i],
              title: (i) => item.servings[i].name,
              onChanged: vm.setServing,
            ),
            PickerRow<Meal>(
              label: 'Meal',
              value: vm.meal,
              values: Meal.values,
              title: (m) => m.title,
              onChanged: (m) => vm.meal = m,
            ),
          ],
        ),
        Section(
          title: 'Nutrition',
          children: [
            KeyValue('Calories', Fmt.kcal(n.calories), bold: true),
            KeyValue('Protein', _g(n.protein)),
            KeyValue('Carbs', _g(n.carbs)),
            KeyValue('    Fibre', _g(n.fiber)),
            KeyValue('    Sugar', _g(n.sugar)),
            KeyValue('Fat', _g(n.fat)),
            KeyValue('    Saturated', _g(n.saturatedFat)),
            KeyValue('Sodium', '${n.sodium.round()} mg'),
            if (grams != null) KeyValue('Weight', '${(grams * (vm.amount ?? 0)).round()} g'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton(
            onPressed: (vm.amount ?? 0) > 0
                ? () {
                    if (vm.save()) closeToRoot(context);
                  }
                : null,
            child: Text(vm.isEditing ? 'Save' : 'Log ${Fmt.kcal(n.calories)} kcal'),
          ),
        ),
        if (vm.isEditing)
          TextButton(
            onPressed: () {
              vm.delete();
              closeToRoot(context);
            },
            child: const Text('Delete', style: TextStyle(color: TrimColors.red)),
          ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure(this.error);
  final String error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber, size: 40),
          const SizedBox(height: 8),
          const Text("Couldn't load this food", style: TextStyle(fontWeight: FontWeight.w600)),
          Text(error, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
