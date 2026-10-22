import 'dart:async';

import '../../../../data/repositories/app_repository.dart';
import '../../../../domain/models.dart';
import '../../../core/view_model.dart';

/// Picking an amount for a food and logging it, or editing a logged entry.
class FoodDetailViewModel extends ViewModel {
  /// A food that's ready, optionally with how to log it.
  FoodDetailViewModel.item(
    this._repository,
    FoodItem item, {
    required this._day,
    required this._meal,
    int? serving,
    double? amount,
  }) : entry = null {
    _setItem(item, serving, amount);
  }

  /// A food whose full details need a request first.
  FoodDetailViewModel.load(
    this._repository,
    Future<FoodItem> Function() loader, {
    required this._day,
    required this._meal,
  }) : entry = null {
    unawaited(
      loader().then(
        (i) => _setItem(i, null, null),
        onError: (Object e) {
          error = '$e';
          notifyListeners();
        },
      ),
    );
  }

  /// Editing a logged entry.
  FoodDetailViewModel.entry(this._repository, FoodEntry e) : entry = e, _day = e.date, _meal = e.meal {
    _setItem(e.item, e.serving, e.amount);
  }

  final AppRepository _repository;
  final FoodEntry? entry;
  final DateTime _day;

  FoodItem? item;
  int serving = 0;
  double? amount = 1;
  String? error;

  Meal _meal;
  Meal get meal => _meal;
  set meal(Meal m) {
    _meal = m;
    notifyListeners();
  }

  bool get isEditing => entry != null;

  Nutrients get nutrients => item?.nutrients(serving, amount ?? 0) ?? const Nutrients();

  bool get isFavorite => item != null && _repository.isFavorite(item!);

  void _setItem(FoodItem i, int? s, double? a) {
    // Start from how you logged it last time, when you have.
    final saved = _repository.data.saved.where((x) => x.item.key == i.key).firstOrNull;
    final idx = s ?? saved?.serving ?? 0;
    serving = idx >= 0 && idx < i.servings.length ? idx : 0;
    amount = a ?? saved?.amount ?? i.servings[serving].defaultAmount;
    item = i;
    notifyListeners();
  }

  void setAmount(double? v) {
    amount = v;
    notifyListeners();
  }

  /// How much the − and + buttons change the amount.
  double get step {
    final name = item?.servings[serving].name;
    if (name == 'g') return 10;
    if (name == 'oz') return 0.5;
    return (amount ?? 1) < 2 ? 0.25 : 0.5;
  }

  void stepAmount(int direction) {
    final next = (amount ?? 0) + direction * step;
    setAmount(next < 0 ? 0 : next);
  }

  /// Switching measure keeps the same quantity of food.
  void setServing(int next) {
    final i = item;
    if (i == null) return;
    final before = i.servings[serving].perUnit * (amount ?? 0);
    final per = i.servings[next].perUnit;
    if (per > 0) amount = ((before / per) * 100).roundToDouble() / 100;
    serving = next;
    notifyListeners();
  }

  void toggleFavorite() {
    final i = item;
    if (i != null) _repository.toggleFavorite(i, serving: serving, amount: amount);
    notifyListeners();
  }

  /// Logs the food or saves the edit. Returns false when there's nothing to save.
  bool save() {
    final a = amount;
    final i = item;
    if (a == null || a <= 0 || i == null) return false;
    final e = entry;
    if (e != null) {
      e
        ..serving = serving
        ..amount = a
        ..meal = _meal;
      _repository.updateEntry(e);
    } else {
      _repository.log(i, serving: serving, amount: a, meal: _meal, day: _day);
    }
    return true;
  }

  void delete() {
    final e = entry;
    if (e != null) _repository.deleteEntry(e.id);
  }
}
