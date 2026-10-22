import 'dart:math' as math;

import 'format.dart';
import 'plan.dart';

// Everything the app saves, as trim.json. Every field reads with a default when it's missing, so adding a field
// never breaks a file written by an older build. Keys and date format (ISO 8601, UTC, whole seconds) match the
// Swift app, so its trim.json opens unchanged.

typedef Json = Map<String, dynamic>;

String encodeDate(DateTime d) => '${d.toUtc().toIso8601String().split('.').first.replaceAll('Z', '')}Z';

DateTime? decodeDate(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

double? _d(Object? v) => v is num ? v.toDouble() : null;
int? _i(Object? v) => v is num ? v.toInt() : null;
String? _s(Object? v) => v is String ? v : null;
Json _m(Object? v) => v is Map<Object?, Object?> ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Json> _l(Object? v) =>
    v is List<Object?> ? v.whereType<Map<Object?, Object?>>().map((e) => e.cast<String, dynamic>()).toList() : [];

T _enum<T extends Enum>(List<T> values, Object? v, T fallback) =>
    values.firstWhere((e) => e.name == v, orElse: () => fallback);

/// The hall in a `MarketItem.key` or `MarketMenu.key`: the part before `|`, or Union Market for a bare key.
DiningHall _hallOfKey(String key) {
  final bar = key.indexOf('|');
  return bar < 0 ? DiningHall.unionMarket : _enum(DiningHall.values, key.substring(0, bar), DiningHall.unionMarket);
}

/// Random version 4 UUID, upper case like Swift's `UUID().uuidString`.
String newId() {
  final r = math.Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

void _put(Json j, String k, Object? v) {
  if (v != null) j[k] = v;
}

class Nutrients {
  final double calories, protein, carbs, fat, fiber, sugar, sodium, saturatedFat;

  const Nutrients({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
    this.sugar = 0,
    this.sodium = 0,
    this.saturatedFat = 0,
  });

  factory Nutrients.fromJson(Json j) => Nutrients(
    calories: _d(j['calories']) ?? 0,
    protein: _d(j['protein']) ?? 0,
    carbs: _d(j['carbs']) ?? 0,
    fat: _d(j['fat']) ?? 0,
    fiber: _d(j['fiber']) ?? 0,
    sugar: _d(j['sugar']) ?? 0,
    sodium: _d(j['sodium']) ?? 0,
    saturatedFat: _d(j['saturatedFat']) ?? 0,
  );

  Json toJson() => {
    'calories': calories,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': fiber,
    'sugar': sugar,
    'sodium': sodium,
    'saturatedFat': saturatedFat,
  };

  Nutrients scaled(double f) => Nutrients(
    calories: calories * f,
    protein: protein * f,
    carbs: carbs * f,
    fat: fat * f,
    fiber: fiber * f,
    sugar: sugar * f,
    sodium: sodium * f,
    saturatedFat: saturatedFat * f,
  );

  Nutrients operator +(Nutrients b) => Nutrients(
    calories: calories + b.calories,
    protein: protein + b.protein,
    carbs: carbs + b.carbs,
    fat: fat + b.fat,
    fiber: fiber + b.fiber,
    sugar: sugar + b.sugar,
    sodium: sodium + b.sodium,
    saturatedFat: saturatedFat + b.saturatedFat,
  );
}

enum FoodSource {
  nutritionix,
  usda,
  openFoodFacts,
  unionMarket,
  residenceDining,
  westDining,
  twistedTaco,
  custom;

  String get title => const {
    FoodSource.nutritionix: 'Nutritionix',
    FoodSource.usda: 'USDA',
    FoodSource.openFoodFacts: 'Open Food Facts',
    FoodSource.unionMarket: 'NDSU Dining',
    FoodSource.residenceDining: 'NDSU Dining',
    FoodSource.westDining: 'NDSU Dining',
    FoodSource.twistedTaco: 'NDSU Dining',
    FoodSource.custom: 'Your food',
  }[this]!;
}

/// NDSU Dining locations. Each is a Jamix kitchen (`k`) of customer 99035 on usa.jamix.cloud, and they all use
/// the same page layout. The names are the `hall` values the Swift app wrote.
enum DiningHall {
  unionMarket('Union Market', 'Union', 'https://usa.jamix.cloud/menu/?anro=99035&k=10', FoodSource.unionMarket),
  // Kitchen 9 alone opens a "Select menu" page; choosing its one menu goes to mt=3.
  residence(
    'Residence Dining Center',
    'Residence',
    'https://usa.jamix.cloud/menu/?anro=99035&k=9&mt=3',
    FoodSource.residenceDining,
  ),
  west('West Dining Center', 'West', 'https://usa.jamix.cloud/menu/?anro=99035&k=8', FoodSource.westDining),
  // One menu with no meal tabs.
  twistedTaco('Twisted Taco', 'Taco', 'https://usa.jamix.cloud/menu/?anro=99035&k=15', FoodSource.twistedTaco);

  const DiningHall(this.title, this.shortTitle, this.menuURL, this.source);
  final String title;
  final String shortTitle;
  final String menuURL;
  final FoodSource source;

  static DiningHall? ofSource(FoodSource source) => values.where((h) => h.source == source).firstOrNull;
}

/// One way to measure a food. `perUnit` is the multiple of the food's base nutrients in one unit,
/// so "2 cups" is `base × perUnit × 2`.
class Serving {
  final String name;
  final double perUnit;
  final double defaultAmount;

  /// Grams in one unit, when known.
  final double? grams;

  const Serving(this.name, this.perUnit, {this.defaultAmount = 1, this.grams});

  factory Serving.fromJson(Json j) => Serving(
    _s(j['name']) ?? 'serving',
    _d(j['perUnit']) ?? 1,
    defaultAmount: _d(j['defaultAmount']) ?? 1,
    grams: _d(j['grams']),
  );

  Json toJson() {
    final j = <String, dynamic>{'name': name, 'perUnit': perUnit, 'defaultAmount': defaultAmount};
    _put(j, 'grams', grams);
    return j;
  }

  /// Adds g and oz options to a food whose base amount weighs `baseGrams`.
  static List<Serving> weightOptions(double baseGrams) {
    if (baseGrams <= 0) return [];
    return [
      Serving('g', 1 / baseGrams, defaultAmount: baseGrams.roundToDouble(), grams: 1),
      Serving(
        'oz',
        28.3495 / baseGrams,
        defaultAmount: ((baseGrams / 28.3495) * 10).roundToDouble() / 10,
        grams: 28.3495,
      ),
    ];
  }
}

/// A food you can log: its nutrients for one base amount and the ways to measure it.
class FoodItem {
  String name;
  String? brand;
  FoodSource source;

  /// Nutritionix nix_item_id, USDA fdcId, barcode, or Union Market station.
  String? externalID;
  Nutrients base;
  List<Serving> servings;
  String? photoURL;

  FoodItem({
    required this.name,
    this.brand,
    required this.source,
    this.externalID,
    required this.base,
    List<Serving> servings = const [],
    this.photoURL,
  }) : servings = servings.isEmpty ? [const Serving('serving', 1)] : List.of(servings);

  factory FoodItem.fromJson(Json j) => FoodItem(
    name: _s(j['name']) ?? 'Food',
    brand: _s(j['brand']),
    source: _enum(FoodSource.values, j['source'], FoodSource.custom),
    externalID: _s(j['externalID']),
    base: Nutrients.fromJson(_m(j['base'])),
    servings: _l(j['servings']).map(Serving.fromJson).toList(),
    photoURL: _s(j['photoURL']),
  );

  Json toJson() {
    final j = <String, dynamic>{
      'name': name,
      'source': source.name,
      'base': base.toJson(),
      'servings': servings.map((s) => s.toJson()).toList(),
    };
    _put(j, 'brand', brand);
    _put(j, 'externalID', externalID);
    _put(j, 'photoURL', photoURL);
    return j;
  }

  FoodItem copy() => FoodItem.fromJson(toJson());

  /// Identifies the same food across log entries, favorites and recents.
  String get key => '${source.name}|${externalID ?? ''}|${name.toLowerCase()}|${brand?.toLowerCase() ?? ''}';

  Serving serving(int i) => i >= 0 && i < servings.length ? servings[i] : servings[0];

  Nutrients nutrients(int serving, double amount) => base.scaled(this.serving(serving).perUnit * amount);
}

enum Meal {
  breakfast,
  lunch,
  dinner,
  snack;

  String get title => name[0].toUpperCase() + name.substring(1);

  static Meal guess([DateTime? at]) {
    final h = (at ?? DateTime.now()).hour;
    if (h >= 4 && h < 10) return Meal.breakfast;
    if (h >= 10 && h < 15) return Meal.lunch;
    if (h >= 15 && h < 17) return Meal.snack;
    if (h >= 17 && h < 21) return Meal.dinner;
    return Meal.snack;
  }
}

class FoodEntry {
  String id;
  DateTime date;
  Meal meal;
  FoodItem item;
  int serving;
  double amount;

  FoodEntry({
    String? id,
    required this.date,
    required this.meal,
    required this.item,
    required this.serving,
    required this.amount,
  }) : id = id ?? newId();

  factory FoodEntry.fromJson(Json j) => FoodEntry(
    id: _s(j['id']),
    date: decodeDate(j['date']) ?? DateTime.now(),
    meal: _enum(Meal.values, j['meal'], Meal.snack),
    item: FoodItem.fromJson(_m(j['item'])),
    serving: _i(j['serving']) ?? 0,
    amount: _d(j['amount']) ?? 1,
  );

  Json toJson() => {
    'id': id,
    'date': encodeDate(date),
    'meal': meal.name,
    'item': item.toJson(),
    'serving': serving,
    'amount': amount,
  };

  Nutrients get nutrients => item.nutrients(serving, amount);
  String get amountText => '${Fmt.amount(amount)} ${item.serving(serving).name}';
}

/// A food kept for one-tap logging.
class SavedFood {
  FoodItem item;
  int serving;
  double amount;
  bool favorite;
  int uses;
  DateTime lastUsed;

  SavedFood({
    required this.item,
    required this.serving,
    required this.amount,
    this.favorite = false,
    this.uses = 0,
    DateTime? lastUsed,
  }) : lastUsed = lastUsed ?? DateTime.now();

  String get id => item.key;

  factory SavedFood.fromJson(Json j) => SavedFood(
    item: FoodItem.fromJson(_m(j['item'])),
    serving: _i(j['serving']) ?? 0,
    amount: _d(j['amount']) ?? 1,
    favorite: j['favorite'] as bool? ?? false,
    uses: _i(j['uses']) ?? 0,
    lastUsed: decodeDate(j['lastUsed']),
  );

  Json toJson() => {
    'item': item.toJson(),
    'serving': serving,
    'amount': amount,
    'favorite': favorite,
    'uses': uses,
    'lastUsed': encodeDate(lastUsed),
  };
}

class WeightEntry {
  String id;
  DateTime date;
  double kg;
  bool fromHealth;

  WeightEntry({String? id, required this.date, required this.kg, this.fromHealth = false}) : id = id ?? newId();

  factory WeightEntry.fromJson(Json j) => WeightEntry(
    id: _s(j['id']),
    date: decodeDate(j['date']) ?? DateTime.now(),
    kg: _d(j['kg']) ?? 0,
    fromHealth: j['fromHealth'] as bool? ?? false,
  );

  Json toJson() => {'id': id, 'date': encodeDate(date), 'kg': kg, 'fromHealth': fromHealth};
}

class WaistEntry {
  String id;
  DateTime date;
  double cm;

  WaistEntry({String? id, required this.date, required this.cm}) : id = id ?? newId();

  factory WaistEntry.fromJson(Json j) => WaistEntry(
    id: _s(j['id']),
    date: decodeDate(j['date']) ?? DateTime.now(),
    cm: _d(j['cm']) ?? 0,
  );

  Json toJson() => {'id': id, 'date': encodeDate(date), 'cm': cm};
}

/// The non-food parts of a day.
class DayNote {
  /// null: counted for the maintenance estimate when there's a reasonable amount logged. true/false: you said so.
  bool? complete;
  int? hunger;
  int? energy;
  int water;
  String note;

  DayNote({this.complete, this.hunger, this.energy, this.water = 0, this.note = ''});

  factory DayNote.fromJson(Json j) => DayNote(
    complete: j['complete'] as bool?,
    hunger: _i(j['hunger']),
    energy: _i(j['energy']),
    water: _i(j['water']) ?? 0,
    note: _s(j['note']) ?? '',
  );

  Json toJson() {
    final j = <String, dynamic>{'water': water, 'note': note};
    _put(j, 'complete', complete);
    _put(j, 'hunger', hunger);
    _put(j, 'energy', energy);
    return j;
  }
}

/// One day's activity from Apple Health or Health Connect, whatever devices and apps write there.
class DayActivity {
  double? steps;
  double? activeKcal;
  double? restingKcal;
  double? sleepHours;
  double? restingHR;
  int strengthSessions;
  double strengthMinutes;
  double cardioMinutes;
  List<String> workouts;

  DayActivity({
    this.steps,
    this.activeKcal,
    this.restingKcal,
    this.sleepHours,
    this.restingHR,
    this.strengthSessions = 0,
    this.strengthMinutes = 0,
    this.cardioMinutes = 0,
    List<String>? workouts,
  }) : workouts = workouts ?? [];

  factory DayActivity.fromJson(Json j) => DayActivity(
    steps: _d(j['steps']),
    activeKcal: _d(j['activeKcal']),
    restingKcal: _d(j['restingKcal']),
    sleepHours: _d(j['sleepHours']),
    restingHR: _d(j['restingHR']),
    strengthSessions: _i(j['strengthSessions']) ?? 0,
    strengthMinutes: _d(j['strengthMinutes']) ?? 0,
    cardioMinutes: _d(j['cardioMinutes']) ?? 0,
    workouts: (j['workouts'] as List?)?.whereType<String>().toList(),
  );

  Json toJson() {
    final j = <String, dynamic>{
      'strengthSessions': strengthSessions,
      'strengthMinutes': strengthMinutes,
      'cardioMinutes': cardioMinutes,
      'workouts': workouts,
    };
    _put(j, 'steps', steps);
    _put(j, 'activeKcal', activeKcal);
    _put(j, 'restingKcal', restingKcal);
    _put(j, 'sleepHours', sleepHours);
    _put(j, 'restingHR', restingHR);
    return j;
  }

  bool get isEmpty =>
      steps == null &&
      activeKcal == null &&
      restingKcal == null &&
      sleepHours == null &&
      restingHR == null &&
      strengthSessions == 0 &&
      strengthMinutes == 0 &&
      cardioMinutes == 0 &&
      workouts.isEmpty;

  double? get totalKcal {
    final a = activeKcal, r = restingKcal;
    if (a == null || r == null || r <= 0) return null;
    return a + r;
  }
}

class CheckIn {
  String id;
  DateTime date;
  double? trendStartKg;
  double? trendEndKg;
  double? waistCm;
  int loggedDays;
  double? avgCalories;
  double? avgProtein;
  double? avgSteps;
  int strengthSessions;
  double cardioMinutes;
  double? avgSleep;
  int? hunger;
  int? energy;
  int? adherence;
  String note;
  double? maintenanceBefore;
  double? maintenanceAfter;
  int? calorieTarget;
  List<String> feedback;

  CheckIn({
    String? id,
    DateTime? date,
    this.trendStartKg,
    this.trendEndKg,
    this.waistCm,
    this.loggedDays = 0,
    this.avgCalories,
    this.avgProtein,
    this.avgSteps,
    this.strengthSessions = 0,
    this.cardioMinutes = 0,
    this.avgSleep,
    this.hunger,
    this.energy,
    this.adherence,
    this.note = '',
    this.maintenanceBefore,
    this.maintenanceAfter,
    this.calorieTarget,
    List<String>? feedback,
  }) : id = id ?? newId(),
       date = date ?? DateTime.now(),
       feedback = feedback ?? [];

  factory CheckIn.fromJson(Json j) => CheckIn(
    id: _s(j['id']),
    date: decodeDate(j['date']),
    trendStartKg: _d(j['trendStartKg']),
    trendEndKg: _d(j['trendEndKg']),
    waistCm: _d(j['waistCm']),
    loggedDays: _i(j['loggedDays']) ?? 0,
    avgCalories: _d(j['avgCalories']),
    avgProtein: _d(j['avgProtein']),
    avgSteps: _d(j['avgSteps']),
    strengthSessions: _i(j['strengthSessions']) ?? 0,
    cardioMinutes: _d(j['cardioMinutes']) ?? 0,
    avgSleep: _d(j['avgSleep']),
    hunger: _i(j['hunger']),
    energy: _i(j['energy']),
    adherence: _i(j['adherence']),
    note: _s(j['note']) ?? '',
    maintenanceBefore: _d(j['maintenanceBefore']),
    maintenanceAfter: _d(j['maintenanceAfter']),
    calorieTarget: _i(j['calorieTarget']),
    feedback: (j['feedback'] as List?)?.whereType<String>().toList(),
  );

  Json toJson() {
    final j = <String, dynamic>{
      'id': id,
      'date': encodeDate(date),
      'loggedDays': loggedDays,
      'strengthSessions': strengthSessions,
      'cardioMinutes': cardioMinutes,
      'note': note,
      'feedback': feedback,
    };
    _put(j, 'trendStartKg', trendStartKg);
    _put(j, 'trendEndKg', trendEndKg);
    _put(j, 'waistCm', waistCm);
    _put(j, 'avgCalories', avgCalories);
    _put(j, 'avgProtein', avgProtein);
    _put(j, 'avgSteps', avgSteps);
    _put(j, 'avgSleep', avgSleep);
    _put(j, 'hunger', hunger);
    _put(j, 'energy', energy);
    _put(j, 'adherence', adherence);
    _put(j, 'maintenanceBefore', maintenanceBefore);
    _put(j, 'maintenanceAfter', maintenanceAfter);
    _put(j, 'calorieTarget', calorieTarget);
    return j;
  }
}

enum StrengthExperience {
  none,
  some,
  regular;

  String get title => const {
    StrengthExperience.none: 'New to lifting',
    StrengthExperience.some: 'Lifted before',
    StrengthExperience.regular: 'Lift regularly',
  }[this]!;
}

enum DietStyle {
  anything,
  vegetarian,
  vegan,
  pescatarian;

  String get title => this == DietStyle.anything ? 'No restrictions' : name[0].toUpperCase() + name.substring(1);
}

class Profile {
  Sex sex;
  DateTime birthDate;
  double heightCm;
  double startWeightKg;
  double goalKg;
  ActivityLevel activity;
  Pace pace;
  bool metric;
  Screening screening;
  StrengthExperience strength;
  DietStyle diet;
  DateTime planStart;

  /// Current maintenance estimate, kcal/day. Starts from the formula and learns from your log.
  double maintenance;
  DateTime? maintenanceUpdated;
  DateTime? maintenanceBreakUntil;
  bool eatBackExercise;
  bool writeWeightToHealth;
  bool useHealth;

  Profile({
    this.sex = Sex.male,
    DateTime? birthDate,
    this.heightCm = 178,
    this.startWeightKg = 90,
    this.goalKg = 80,
    this.activity = ActivityLevel.light,
    this.pace = Pace.steady,
    this.metric = false,
    Screening? screening,
    this.strength = StrengthExperience.none,
    this.diet = DietStyle.anything,
    DateTime? planStart,
    this.maintenance = 2500,
    this.maintenanceUpdated,
    this.maintenanceBreakUntil,
    this.eatBackExercise = false,
    this.writeWeightToHealth = true,
    this.useHealth = false,
  }) : birthDate = birthDate ?? _yearsAgo(25),
       screening = screening ?? Screening(),
       planStart = planStart ?? DateTime.now();

  static DateTime _yearsAgo(int n) {
    final now = DateTime.now();
    return DateTime(now.year - n, now.month, now.day);
  }

  factory Profile.fromJson(Json j) {
    final d = Profile();
    return Profile(
      sex: _enum(Sex.values, j['sex'], d.sex),
      birthDate: decodeDate(j['birthDate']) ?? d.birthDate,
      heightCm: _d(j['heightCm']) ?? d.heightCm,
      startWeightKg: _d(j['startWeightKg']) ?? d.startWeightKg,
      goalKg: _d(j['goalKg']) ?? d.goalKg,
      activity: _enum(ActivityLevel.values, j['activity'], d.activity),
      pace: _enum(Pace.values, j['pace'], d.pace),
      metric: j['metric'] as bool? ?? d.metric,
      screening: j['screening'] is Map ? Screening.fromJson(_m(j['screening'])) : d.screening,
      strength: _enum(StrengthExperience.values, j['strength'], d.strength),
      diet: _enum(DietStyle.values, j['diet'], d.diet),
      planStart: decodeDate(j['planStart']) ?? d.planStart,
      maintenance: _d(j['maintenance']) ?? d.maintenance,
      maintenanceUpdated: decodeDate(j['maintenanceUpdated']),
      maintenanceBreakUntil: decodeDate(j['maintenanceBreakUntil']),
      eatBackExercise: j['eatBackExercise'] as bool? ?? d.eatBackExercise,
      writeWeightToHealth: j['writeWeightToHealth'] as bool? ?? d.writeWeightToHealth,
      useHealth: j['useHealth'] as bool? ?? d.useHealth,
    );
  }

  Json toJson() {
    final j = <String, dynamic>{
      'sex': sex.name,
      'birthDate': encodeDate(birthDate),
      'heightCm': heightCm,
      'startWeightKg': startWeightKg,
      'goalKg': goalKg,
      'activity': activity.name,
      'pace': pace.name,
      'metric': metric,
      'screening': screening.toJson(),
      'strength': strength.name,
      'diet': diet.name,
      'planStart': encodeDate(planStart),
      'maintenance': maintenance,
      'eatBackExercise': eatBackExercise,
      'writeWeightToHealth': writeWeightToHealth,
      'useHealth': useHealth,
    };
    if (maintenanceUpdated != null) j['maintenanceUpdated'] = encodeDate(maintenanceUpdated!);
    if (maintenanceBreakUntil != null) j['maintenanceBreakUntil'] = encodeDate(maintenanceBreakUntil!);
    return j;
  }

  Profile copy() => Profile.fromJson(toJson());

  int get age => Plan.age(birthDate, DateTime.now());
}

/// Dining hall nutrition, cached by hall and item name: the menu repeats, and each label costs a page visit.
class MarketItem {
  String name;
  DiningHall hall;
  String station;
  Nutrients nutrients;
  String portion;
  double? portionGrams;
  DateTime fetched;

  MarketItem({
    required this.name,
    required this.hall,
    required this.station,
    required this.nutrients,
    required this.portion,
    this.portionGrams,
    DateTime? fetched,
  }) : fetched = fetched ?? DateTime.now();

  factory MarketItem.fromJson(Json j) => MarketItem(
    name: _s(j['name']) ?? '',
    // Labels saved before there was more than one hall are Union Market's.
    hall: _enum(DiningHall.values, j['hall'], DiningHall.unionMarket),
    station: _s(j['station']) ?? '',
    nutrients: Nutrients.fromJson(_m(j['nutrients'])),
    portion: _s(j['portion']) ?? '',
    portionGrams: _d(j['portionGrams']),
    fetched: decodeDate(j['fetched']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Json toJson() {
    final j = <String, dynamic>{
      'name': name,
      'hall': hall.name,
      'station': station,
      'nutrients': nutrients.toJson(),
      'portion': portion,
      'fetched': encodeDate(fetched),
    };
    _put(j, 'portionGrams', portionGrams);
    return j;
  }

  MarketItem copyWithName(String n) => MarketItem(
    name: n,
    hall: hall,
    station: station,
    nutrients: nutrients,
    portion: portion,
    portionGrams: portionGrams,
    fetched: fetched,
  );

  FoodItem get foodItem {
    final g = portionGrams;
    return FoodItem(
      name: name,
      brand: hall.title,
      source: hall.source,
      externalID: station,
      base: nutrients,
      servings: [
        Serving(g != null ? 'portion (${g.toInt()} g)' : 'portion', 1, grams: g),
        if (g != null) ...Serving.weightOptions(g),
      ],
    );
  }

  static String normalized(String name) => name.toLowerCase().trim();

  /// The `AppData.market` key. Union Market's keys are bare names, as they were before the other halls.
  static String key(String name, DiningHall hall) =>
      hall == DiningHall.unionMarket ? normalized(name) : '${hall.name}|${normalized(name)}';
}

class MenuItem {
  final String name;
  final String diets;
  const MenuItem(this.name, this.diets);
  factory MenuItem.fromJson(Json j) => MenuItem(_s(j['name']) ?? '', _s(j['diets']) ?? '');
  Json toJson() => {'name': name, 'diets': diets};
}

class Station {
  final String name;
  final List<MenuItem> items;
  const Station(this.name, this.items);
  factory Station.fromJson(Json j) => Station(_s(j['name']) ?? '', _l(j['items']).map(MenuItem.fromJson).toList());
  Json toJson() => {'name': name, 'items': items.map((i) => i.toJson()).toList()};
}

class MenuTab {
  final String name;
  final List<Station> stations;
  const MenuTab(this.name, this.stations);
  factory MenuTab.fromJson(Json j) => MenuTab(_s(j['name']) ?? '', _l(j['stations']).map(Station.fromJson).toList());
  Json toJson() => {'name': name, 'stations': stations.map((s) => s.toJson()).toList()};
}

class MarketMenu {
  final String day;
  final DiningHall hall;
  final String label;
  final List<MenuTab> tabs;
  final DateTime fetched;

  const MarketMenu({
    required this.day,
    required this.hall,
    required this.label,
    required this.tabs,
    required this.fetched,
  });

  factory MarketMenu.fromJson(Json j) => MarketMenu(
    day: _s(j['day']) ?? '',
    hall: _enum(DiningHall.values, j['hall'], DiningHall.unionMarket),
    label: _s(j['label']) ?? '',
    tabs: _l(j['tabs']).map(MenuTab.fromJson).toList(),
    fetched: decodeDate(j['fetched']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Json toJson() => {
    'day': day,
    'hall': hall.name,
    'label': label,
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'fetched': encodeDate(fetched),
  };

  MarketMenu atHall(DiningHall h) =>
      h == hall ? this : MarketMenu(day: day, hall: h, label: label, tabs: tabs, fetched: fetched);

  /// The `AppData.menus` key. Union Market's keys are bare days, as they were before the other halls.
  static String key(String day, DiningHall hall) => hall == DiningHall.unionMarket ? day : '${hall.name}|$day';

  static String stationKey(DiningHall hall, String day, int tab, int station) => '${hall.name}|$day|$tab|$station';

  /// The tab that matches the time of day, e.g. Lunch at noon.
  int tabIndex(Meal meal) {
    final names = tabs.map((t) => t.name.toLowerCase()).toList();
    final want = switch (meal) {
      Meal.breakfast => ['breakfast', 'brunch'],
      Meal.lunch => ['lunch', 'brunch'],
      Meal.dinner => ['dinner', 'supper'],
      Meal.snack => ['late', 'snack', 'dinner', 'lunch'],
    };
    for (final w in want) {
      final i = names.indexWhere((n) => n.contains(w));
      if (i >= 0) return i;
    }
    return 0;
  }
}

class AppData {
  bool onboarded;
  Profile profile;
  List<FoodEntry> entries;
  List<SavedFood> saved;
  List<WeightEntry> weights;
  List<WaistEntry> waists;

  /// Keyed by `Day.key`.
  Map<String, DayNote> notes;
  Map<String, DayActivity> activity;
  List<CheckIn> checkIns;

  /// Keyed by `MarketItem.key`.
  Map<String, MarketItem> market;

  /// Keyed by `MarketMenu.key`.
  Map<String, MarketMenu> menus;

  /// The dining hall whose menu was opened last.
  DiningHall diningHall;

  /// Health weigh-ins you deleted, as `Store.healthSignature` values, so a sync doesn't bring them back.
  Set<String> dismissedHealthWeights;

  /// Ids of installed plugins (`TrimPlugin.id`). Null in files from before plugins, until `PluginRegistry`
  /// decides which ones you were already using.
  List<String>? plugins;

  AppData({
    this.onboarded = false,
    Profile? profile,
    List<FoodEntry>? entries,
    List<SavedFood>? saved,
    List<WeightEntry>? weights,
    List<WaistEntry>? waists,
    Map<String, DayNote>? notes,
    Map<String, DayActivity>? activity,
    List<CheckIn>? checkIns,
    Map<String, MarketItem>? market,
    Map<String, MarketMenu>? menus,
    this.diningHall = DiningHall.unionMarket,
    Set<String>? dismissedHealthWeights,
    this.plugins,
  }) : profile = profile ?? Profile(),
       entries = entries ?? [],
       saved = saved ?? [],
       weights = weights ?? [],
       waists = waists ?? [],
       notes = notes ?? {},
       activity = activity ?? {},
       checkIns = checkIns ?? [],
       market = market ?? {},
       menus = menus ?? {},
       dismissedHealthWeights = dismissedHealthWeights ?? {};

  static Map<String, T> _map<T>(Object? v, T Function(Json) f) => _m(v).map((k, e) => MapEntry(k, f(_m(e))));

  /// Throws FormatException when the top level isn't an object, like Swift's decoder refusing the file.
  factory AppData.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('trim.json is not a JSON object');
    final j = raw.cast<String, dynamic>();
    return AppData(
      onboarded: j['onboarded'] as bool? ?? false,
      profile: j['profile'] is Map ? Profile.fromJson(_m(j['profile'])) : null,
      entries: _l(j['entries']).map(FoodEntry.fromJson).toList(),
      saved: _l(j['saved']).map(SavedFood.fromJson).toList(),
      weights: _l(j['weights']).map(WeightEntry.fromJson).toList(),
      waists: _l(j['waists']).map(WaistEntry.fromJson).toList(),
      notes: _map(j['notes'], DayNote.fromJson),
      activity: _map(j['activity'], DayActivity.fromJson),
      checkIns: _l(j['checkIns']).map(CheckIn.fromJson).toList(),
      // The hall comes from the key: v1.0.0 of this app rewrote the file without the `hall` fields.
      market: _map(j['market'], MarketItem.fromJson).map((k, v) => MapEntry(k, v..hall = _hallOfKey(k))),
      menus: _map(j['menus'], MarketMenu.fromJson).map((k, v) => MapEntry(k, v.atHall(_hallOfKey(k)))),
      diningHall: _enum(DiningHall.values, j['diningHall'], DiningHall.unionMarket),
      dismissedHealthWeights: (j['dismissedHealthWeights'] as List?)?.whereType<String>().toSet(),
      plugins: (j['plugins'] as List?)?.whereType<String>().toList(),
    );
  }

  Json toJson() => {
    'onboarded': onboarded,
    'profile': profile.toJson(),
    'entries': entries.map((e) => e.toJson()).toList(),
    'saved': saved.map((e) => e.toJson()).toList(),
    'weights': weights.map((e) => e.toJson()).toList(),
    'waists': waists.map((e) => e.toJson()).toList(),
    'notes': notes.map((k, v) => MapEntry(k, v.toJson())),
    'activity': activity.map((k, v) => MapEntry(k, v.toJson())),
    'checkIns': checkIns.map((e) => e.toJson()).toList(),
    'market': market.map((k, v) => MapEntry(k, v.toJson())),
    'menus': menus.map((k, v) => MapEntry(k, v.toJson())),
    'diningHall': diningHall.name,
    'dismissedHealthWeights': (dismissedHealthWeights.toList()..sort()),
    'plugins': ?plugins,
  };
}
