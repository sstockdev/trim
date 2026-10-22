import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/format.dart';
import '../../domain/models.dart';
import '../../domain/plan.dart';
import '../services/data_file_service.dart';
import '../services/health_service.dart';

/// The single source of truth: everything in trim.json, plus the values derived from it. Screens watch it through
/// provider and change it through its methods. Every change ends in [changed], which saves shortly after.
class AppRepository extends ChangeNotifier {
  AppRepository({required this._files, required this._health, LoadedData? loaded})
    : data = loaded?.data ?? AppData(),
      unreadableBackup = loaded?.unreadableBackup,
      saveBlocked = loaded?.saveBlocked ?? false;

  final DataFileService _files;
  final HealthService _health;

  AppData data;

  /// Set when trim.json couldn't be read at launch: the name of the copy kept in Documents, shown once.
  String? unreadableBackup;

  /// True when the unreadable trim.json couldn't be copied aside, so saving would destroy the only copy.
  final bool saveBlocked;

  DateTime? healthLastSync;
  String? healthError;
  bool _syncing = false;

  Timer? _saveTimer;

  // Values derived from `data`, built on first use and dropped whenever `data` changes.
  Map<String, List<FoodEntry>>? _entriesByDay;
  List<WeightPoint>? _trend;

  /// Call after changing `data`: drops cached values, redraws and saves shortly after.
  void changed() {
    _entriesByDay = null;
    _trend = null;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), saveNow);
  }

  /// Changes `data` and saves.
  void update(void Function(AppData d) change) {
    change(data);
    changed();
  }

  void dismissUnreadable() {
    unreadableBackup = null;
    notifyListeners();
  }

  void saveNow() {
    _saveTimer?.cancel();
    if (!saveBlocked) _files.save(data);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  Profile get profile => data.profile;

  // Food

  List<FoodEntry> entries(DateTime day) {
    _entriesByDay ??= () {
      final m = <String, List<FoodEntry>>{};
      for (final e in data.entries) {
        (m[Day.key(e.date)] ??= []).add(e);
      }
      for (final l in m.values) {
        l.sort((a, b) => a.date.compareTo(b.date));
      }
      return m;
    }();
    return _entriesByDay![Day.key(day)] ?? const [];
  }

  Nutrients totals(DateTime day) => entries(day).fold(const Nutrients(), (s, e) => s + e.nutrients);

  String log(FoodItem item, {required int serving, required double amount, required Meal meal, required DateTime day}) {
    // Logged on a past or future day: keep the time of day so meals stay in order.
    final now = DateTime.now();
    final date = Day.same(day, now) ? now : DateTime(day.year, day.month, day.day, now.hour, now.minute);
    final entry = FoodEntry(date: date, meal: meal, item: item.copy(), serving: serving, amount: amount);
    data.entries.add(entry);
    _remember(item, serving, amount);
    changed();
    return entry.id;
  }

  void deleteEntry(String id) => update((d) => d.entries.removeWhere((e) => e.id == id));

  void updateEntry(FoodEntry entry) {
    final i = data.entries.indexWhere((e) => e.id == entry.id);
    if (i < 0) return;
    data.entries[i] = entry;
    changed();
  }

  void copyMeal(Meal meal, DateTime from, DateTime to) {
    for (final e in entries(from).where((e) => e.meal == meal).toList()) {
      log(e.item, serving: e.serving, amount: e.amount, meal: meal, day: to);
    }
  }

  void _remember(FoodItem item, int serving, double amount) {
    final i = data.saved.indexWhere((s) => s.item.key == item.key);
    if (i >= 0) {
      final s = data.saved[i];
      s.item = item.copy();
      s.serving = serving;
      s.amount = amount;
      s.uses += 1;
      s.lastUsed = DateTime.now();
    } else {
      data.saved.add(SavedFood(item: item.copy(), serving: serving, amount: amount, uses: 1));
    }
  }

  bool isFavorite(FoodItem item) => data.saved.where((s) => s.item.key == item.key).firstOrNull?.favorite ?? false;

  void toggleFavorite(FoodItem item, {int serving = 0, double? amount}) {
    final i = data.saved.indexWhere((s) => s.item.key == item.key);
    if (i >= 0) {
      data.saved[i].favorite = !data.saved[i].favorite;
    } else {
      final s = serving >= 0 && serving < item.servings.length ? serving : 0;
      data.saved.add(
        SavedFood(item: item.copy(), serving: s, amount: amount ?? item.servings[s].defaultAmount, favorite: true),
      );
    }
    changed();
  }

  void forget(SavedFood saved) => update((d) => d.saved.removeWhere((s) => s.id == saved.id));

  List<SavedFood> get recents =>
      data.saved.where((s) => s.uses > 0).toList()..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));

  List<SavedFood> get favorites =>
      data.saved.where((s) => s.favorite).toList()..sort((a, b) => a.item.name.compareTo(b.item.name));

  /// Dining hall foods you've logged, most-used first: the one-tap list. All halls, or just [hall].
  List<SavedFood> marketUsuals([DiningHall? hall]) {
    final l = data.saved.where((s) {
      final h = DiningHall.ofSource(s.item.source);
      return h != null && (hall == null || h == hall) && (s.uses > 0 || s.favorite);
    }).toList();
    l.sort((a, b) {
      final f = (b.favorite ? 1 : 0) - (a.favorite ? 1 : 0);
      if (f != 0) return f;
      final u = b.uses - a.uses;
      if (u != 0) return u;
      return b.lastUsed.compareTo(a.lastUsed);
    });
    return l;
  }

  /// Your own foods matching a search, like the "Your foods" section in Nutritionix Track.
  List<SavedFood> savedMatching(String query) {
    final words = query.toLowerCase().split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return [];
    return data.saved.where((s) {
      final hay = '${s.item.name} ${s.item.brand ?? ''}'.toLowerCase();
      return words.every(hay.contains);
    }).toList()..sort((a, b) => b.uses.compareTo(a.uses));
  }

  // Body

  List<WeightEntry> get weightsSorted => [...data.weights]..sort((a, b) => a.date.compareTo(b.date));

  List<WeightPoint> get trend => _trend ??= Plan.trend(weightsSorted.map((w) => WeightPoint(w.date, w.kg)).toList());

  /// Smoothed current weight; the program runs on this, not on any single weigh-in.
  double get trendKg => trend.isEmpty ? data.profile.startWeightKg : trend.last.kg;

  WeightEntry? weight(DateTime day) {
    WeightEntry? best;
    for (final w in data.weights) {
      if (Day.same(w.date, day) && (best == null || w.date.isAfter(best.date))) best = w;
    }
    return best;
  }

  /// One weigh-in per day: a new one replaces that day's.
  void setWeight(double kg, DateTime date, {bool fromHealth = false}) {
    data.weights.removeWhere((w) => Day.same(w.date, date));
    data.weights.add(WeightEntry(date: date, kg: kg, fromHealth: fromHealth));
    changed();
  }

  void deleteWeight(WeightEntry w) {
    // Otherwise the next Health sync imports it again, since its day is now empty.
    if (w.fromHealth) data.dismissedHealthWeights.add(healthSignature(w.date, w.kg));
    data.weights.removeWhere((x) => x.id == w.id);
    changed();
  }

  /// Identifies a Health weigh-in by its time and value (imported entries keep the sample's start date).
  static String healthSignature(DateTime date, double kg) =>
      '${date.millisecondsSinceEpoch ~/ 1000}|${kg.toStringAsFixed(2)}';

  WaistEntry? get latestWaist {
    WaistEntry? best;
    for (final w in data.waists) {
      if (best == null || w.date.isAfter(best.date)) best = w;
    }
    return best;
  }

  void addWaist(double cm, [DateTime? date]) {
    final d = date ?? DateTime.now();
    data.waists.removeWhere((w) => Day.same(w.date, d));
    data.waists.add(WaistEntry(date: d, cm: cm));
    changed();
  }

  // Days

  DayNote note(DateTime day) => data.notes[Day.key(day)] ?? DayNote();

  void setNote(DateTime day, void Function(DayNote n) change) {
    final n = note(day);
    change(n);
    data.notes[Day.key(day)] = n;
    changed();
  }

  DayActivity? activity(DateTime day) => data.activity[Day.key(day)];

  /// Below this, an unmarked day is treated as partly logged and left out of the maintenance estimate.
  static const minimumCountedKcal = 1000.0;

  double? countedIntake(DateTime day) {
    final kcal = totals(day).calories;
    return switch (note(day).complete) {
      true => kcal,
      false => null,
      null => kcal >= minimumCountedKcal ? kcal : null,
    };
  }

  static double? average(Iterable<double?> values) {
    final v = values.whereType<double>().toList();
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  List<DateTime> days(int n, DateTime end) => [for (var i = n - 1; i >= 0; i--) Day.add(-i, Day.start(end))];

  /// Typical daily steps over the last two weeks, for the step goal.
  double? get baselineSteps => average(days(14, Day.add(-1, DateTime.now())).map((d) => activity(d)?.steps));

  double? get baselineActiveKcal => average(days(14, Day.add(-1, DateTime.now())).map((d) => activity(d)?.activeKcal));

  // Program

  List<Warning> get warnings {
    final p = data.profile;
    return Plan.warnings(age: p.age, heightCm: p.heightCm, weightKg: trendKg, goalKg: p.goalKg, screening: p.screening);
  }

  bool get onMaintenanceBreak {
    final until = data.profile.maintenanceBreakUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  Targets get targets {
    final p = data.profile;
    final blocked = Plan.blocksDeficit(warnings);
    final t = Plan.targets(
      sex: p.sex,
      age: p.age,
      heightCm: p.heightCm,
      trendKg: trendKg,
      goalKg: p.goalKg,
      pace: p.pace,
      tdee: p.maintenance,
      maintenanceBreak: onMaintenanceBreak || blocked,
      baselineSteps: baselineSteps,
    );
    if (blocked) t.notes.add('Targets are at maintenance because of your answers in the safety check.');
    return t;
  }

  /// Calories for a given day, including the optional exercise bonus: half of the active energy above your
  /// usual. Off by default, since the maintenance estimate already counts your normal activity and watches tend
  /// to overestimate burns.
  ({int total, int bonus}) calorieTarget(DateTime day) {
    final base = targets.calories;
    final active = activity(day)?.activeKcal;
    final usual = baselineActiveKcal;
    if (!data.profile.eatBackExercise || active == null || usual == null) return (total: base, bonus: 0);
    final over = active - usual > 0 ? active - usual : 0.0;
    final bonus = ((over * 0.5 / 10).round() * 10);
    return (total: base + bonus, bonus: bonus);
  }

  int get weeksInDeficit {
    final p = data.profile;
    final brk = p.maintenanceBreakUntil;
    final start = brk != null && brk.isAfter(p.planStart) ? brk : p.planStart;
    final d = Day.between(start, DateTime.now()) ~/ 7;
    return d < 0 ? 0 : d;
  }

  CheckIn? get lastCheckIn {
    CheckIn? best;
    for (final c in data.checkIns) {
      if (best == null || c.date.isAfter(best.date)) best = c;
    }
    return best;
  }

  int get daysSinceCheckIn => Day.between(lastCheckIn?.date ?? data.profile.planStart, DateTime.now());

  bool get checkInDue => daysSinceCheckIn >= 7;

  /// The estimate moves at most once every 6 days, so an early second check-in doesn't count the same data twice.
  bool get maintenanceUpdatedRecently {
    final u = data.profile.maintenanceUpdated;
    return u != null && Day.between(u, DateTime.now()) < 6;
  }

  /// Re-estimates maintenance from the last three weeks of logging and weigh-ins, unless it was updated recently.
  AdaptiveResult? updateMaintenanceIfDue() {
    final p = data.profile;
    if (maintenanceUpdatedRecently) return null;
    final end = Day.add(-1, DateTime.now());
    final logs = days(21, end).map((d) => DayLog(d, countedIntake(d))).toList();
    final bmr = Plan.bmr(p.sex, trendKg, p.heightCm, p.age);
    final r = Plan.adaptiveTDEE(
      days: logs,
      weighIns: weightsSorted.map((w) => WeightPoint(w.date, w.kg)).toList(),
      prior: p.maintenance,
      bmr: bmr,
      planStart: p.planStart,
      through: end,
    );
    if (r == null) return null;
    data.profile.maintenance = r.tdee;
    data.profile.maintenanceUpdated = DateTime.now();
    changed();
    return r;
  }

  /// The seven days before today.
  WeekReview weekReview([DateTime? endOn]) {
    final end = endOn ?? Day.add(-1, DateTime.now());
    final week = days(7, end);
    final line = trend;
    // With no weigh-in before the week, one on its first day can stand in; a later one would make a
    // part-week change look like a whole week's.
    final startTrend =
        Plan.trendValue(Day.add(-1, week[0]), line) ??
        (line.isNotEmpty && line.first.date.isBefore(Day.add(1, week[0])) ? line.first.kg : null);
    final endTrend = Plan.trendValue(end, line);
    final counted = week.where((d) => countedIntake(d) != null).toList();
    final protein = counted.map((d) => totals(d).protein).toList();
    final proteinGoal = targets.protein * 0.9;
    final acts = week.map(activity).toList();
    return WeekReview(
      trendStart: startTrend,
      trendEnd: endTrend,
      loggedDays: counted.length,
      avgCalories: average(counted.map(countedIntake)),
      avgProtein: average(protein),
      proteinDays: protein.where((p) => p >= proteinGoal).length,
      avgSteps: average(acts.map((a) => a?.steps)),
      strengthSessions: acts.fold(0, (s, a) => s + (a?.strengthSessions ?? 0)),
      cardioMinutes: acts.fold(0.0, (s, a) => s + (a?.cardioMinutes ?? 0)),
      avgSleepHours: average(acts.map((a) => a?.sleepHours)),
    );
  }

  /// Warnings from the last couple of weeks of data.
  List<Warning> get trendAlerts {
    final out = <Warning>[];
    final line = trend;
    final today = DateTime.now();
    final now = Plan.trendValue(today, line);
    final twoWeeks = Plan.trendValue(Day.add(-14, today), line);
    if (now != null && twoWeeks != null && Day.between(data.profile.planStart, today) >= 21 && twoWeeks > 0) {
      final perWeek = (twoWeeks - now) / twoWeeks / 2;
      if (perWeek > 0.015) {
        out.add(
          Warning(
            WarningLevel.caution,
            "You've lost ${(perWeek * 100).toStringAsFixed(1)} % a week for two weeks. That fast, more of it is muscle; eat 200 to 300 kcal more.",
          ),
        );
      }
    }
    final recent = days(7, Day.add(-1, today)).map(countedIntake).whereType<double>().toList();
    if (recent.length >= 4) {
      final avg = recent.reduce((a, b) => a + b) / recent.length;
      final floor = Plan.calorieFloor(data.profile.sex).toDouble();
      if (avg < floor - 100) {
        out.add(
          Warning(
            WarningLevel.caution,
            "You've averaged ${avg.toInt()} kcal this week, under ${floor.toInt()}. Very low intakes cost muscle and are hard to sustain; aim for your target.",
          ),
        );
      }
    }
    return out;
  }

  // Health

  /// Asks for Health access and turns syncing on when granted.
  Future<void> connectHealth() async {
    try {
      await _health.requestAccess();
      healthError = null;
      update((d) => d.profile.useHealth = true);
      await syncHealth();
    } on Exception catch (e) {
      healthError = '$e';
      update((d) => d.profile.useHealth = false);
    }
  }

  void disconnectHealth() => update((d) => d.profile.useHealth = false);

  /// Brings in the last `days` days of activity and any new smart-scale weigh-ins.
  Future<void> syncHealth({int days = 28}) async {
    if (!data.profile.useHealth || _syncing || !await _health.available) return;
    _syncing = true;
    try {
      final snap = await _health.fetch(days: days);
      snap.activity.forEach((key, act) {
        if (!act.isEmpty || data.activity[key] != null) data.activity[key] = act;
      });
      for (final w in snap.weights) {
        if (data.dismissedHealthWeights.contains(healthSignature(w.date, w.kg))) continue;
        // The first weigh-in of each day wins, matching the "weigh in after waking" routine.
        if (weight(w.date) == null) data.weights.add(WeightEntry(date: w.date, kg: w.kg, fromHealth: true));
      }
      healthLastSync = DateTime.now();
      healthError = null;
    } on Exception catch (e) {
      healthError = '$e';
    } finally {
      _syncing = false;
      changed();
    }
  }

  Future<double?> averageTotalBurn() => _health.averageTotalBurn();

  /// Logs a weigh-in typed in the app, and copies it to Health when that's turned on.
  void recordWeighIn(double kg, DateTime date) {
    setWeight(kg, date);
    final p = data.profile;
    if (p.useHealth && p.writeWeightToHealth) {
      _health.saveWeight(kg, date).catchError((Object e) {
        healthError = '$e';
        notifyListeners();
      });
    }
  }

  // Export

  String csv() {
    final tf = DateFormat('HH:mm');
    final food = StringBuffer(
      'date,time,meal,food,brand,amount,calories,protein_g,carbs_g,fat_g,fiber_g,sugar_g,sodium_mg,source\n',
    );
    final sorted = [...data.entries]..sort((a, b) => a.date.compareTo(b.date));
    for (final e in sorted) {
      final n = e.nutrients;
      final cells = [
        Day.key(e.date),
        tf.format(e.date),
        e.meal.name,
        e.item.name,
        e.item.brand ?? '',
        e.amountText,
        n.calories.toStringAsFixed(0),
        n.protein.toStringAsFixed(1),
        n.carbs.toStringAsFixed(1),
        n.fat.toStringAsFixed(1),
        n.fiber.toStringAsFixed(1),
        n.sugar.toStringAsFixed(1),
        n.sodium.toStringAsFixed(0),
        e.item.source.name,
      ];
      food.writeln(cells.map(_csvCell).join(','));
    }
    final daily = StringBuffer(
      'date,weight_kg,trend_kg,calories,protein_g,steps,active_kcal,sleep_h,strength_sessions,hunger,energy,complete\n',
    );
    final keys = {
      ...data.entries.map((e) => Day.key(e.date)),
      ...data.weights.map((w) => Day.key(w.date)),
      ...data.activity.keys,
    }.toList()..sort();
    final line = trend;
    for (final key in keys) {
      final d = Day.date(key);
      if (d == null) continue;
      final t = totals(d);
      final a = activity(d);
      final n = note(d);
      final cells = [
        key,
        weight(d)?.kg.toStringAsFixed(2) ?? '',
        Plan.trendValue(d, line)?.toStringAsFixed(2) ?? '',
        t.calories.toStringAsFixed(0),
        t.protein.toStringAsFixed(0),
        a?.steps?.toStringAsFixed(0) ?? '',
        a?.activeKcal?.toStringAsFixed(0) ?? '',
        a?.sleepHours?.toStringAsFixed(1) ?? '',
        a == null ? '' : '${a.strengthSessions}',
        n.hunger?.toString() ?? '',
        n.energy?.toString() ?? '',
        countedIntake(d) != null ? 'yes' : 'no',
      ];
      daily.writeln(cells.join(','));
    }
    return 'FOOD LOG\n$food\nDAILY\n$daily';
  }

  Future<File> csvExport() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/export');
    await dir.create(recursive: true);
    final file = File('${dir.path}/Trim ${Day.key(DateTime.now())}.csv');
    await file.writeAsString(csv());
    return file;
  }

  static String _csvCell(String s) =>
      s.contains(',') || s.contains('"') || s.contains('\n') ? '"${s.replaceAll('"', '""')}"' : s;

  void resetAll() {
    data = AppData();
    changed();
    saveNow();
  }

  // Dining hall cache

  MarketItem? marketItem(String name, DiningHall hall) => data.market[MarketItem.key(name, hall)];

  void saveMarket(List<MarketItem> items, DiningHall hall, {List<String> menuNames = const []}) {
    for (final item in items.where((i) => i.name.isNotEmpty)) {
      _putMarket(item);
    }
    // Also file each label under the menu's name for it when the label page words it slightly differently,
    // so the menu shows it as cached.
    for (final name in menuNames) {
      if (marketItem(name, hall) != null) continue;
      final lower = name.toLowerCase();
      final match = items.where((i) {
        final n = i.name.toLowerCase();
        return n.contains(lower) || lower.contains(n);
      }).firstOrNull;
      if (match != null) _putMarket(match.copyWithName(name));
    }
    changed();
  }

  void _putMarket(MarketItem item) {
    data.market[MarketItem.key(item.name, item.hall)] = item;
    // Keep saved copies in sync when the dining hall changes a recipe.
    final name = MarketItem.normalized(item.name);
    for (final s in data.saved) {
      if (s.item.source == item.hall.source && MarketItem.normalized(s.item.name) == name) s.item.base = item.nutrients;
    }
  }

  void saveMenu(MarketMenu menu) {
    data.menus[MarketMenu.key(menu.day, menu.hall)] = menu;
    // Only keep a couple of weeks of menus.
    final cutoff = Day.key(Day.add(-14, DateTime.now()));
    data.menus.removeWhere((_, m) => m.day.compareTo(cutoff) < 0);
    changed();
  }
}
